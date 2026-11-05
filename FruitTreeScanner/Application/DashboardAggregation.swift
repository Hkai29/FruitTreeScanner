import Foundation
import Combine

/// 产量的统一写法：按当前语言的小数分隔符，固定一位小数。
/// 主页读数与分析报表共用这一套 —— 同一个数不会在两个页面上长得不一样。
enum YieldNumberFormatting {
    static func text(_ yieldKg: Float, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: yieldKg)) ?? "0.0"
    }
}

struct DashboardDailySummary: Equatable, Sendable {
    let scanCount: Int
    let yieldKg: Float
    let treeCount: Int

    init(records: [ScanFileRecord], calendar: Calendar = .current, now: Date = Date()) {
        var todaysScanCount = 0
        var todaysYield: Float = 0
        var treeIDs = Set<String>()

        for record in records where calendar.isDate(record.scanDate, inSameDayAs: now) && record.persistenceState == .complete {
            todaysScanCount += 1
            todaysYield += record.yieldKg
            treeIDs.insert(record.treeID)
        }

        scanCount = todaysScanCount
        yieldKg = todaysYield
        treeCount = treeIDs.count
    }
}

struct YieldReportData: Equatable, Sendable {
    let completeRecords: [ScanFileRecord]
    let latestRecordsByTree: [ScanFileRecord]
    let totalYield: Float?
    let totalFruit: Int?
    let visibleRecords: [ScanFileRecord]

    var totalScans: Int { completeRecords.count }
    var totalTrees: Int { latestRecordsByTree.count }
    var averageYield: Float? { totalYield.map { totalTrees > 0 ? $0 / Float(totalTrees) : 0 } }
    var isEmpty: Bool { latestRecordsByTree.isEmpty }

    init(records: [ScanFileRecord]) {
        let completeRecords = records.filter { $0.persistenceState == .complete }
        self.completeRecords = completeRecords
        latestRecordsByTree = Self.latestRecordsByTree(from: completeRecords)
        visibleRecords = Array(latestRecordsByTree.prefix(20))
        let totals = ScanRecordTotals(records: latestRecordsByTree)
        totalYield = totals.yieldKg
        totalFruit = totals.fruitCount
    }

    private static func latestRecordsByTree(
        from records: [ScanFileRecord]
    ) -> [ScanFileRecord] {
        var latestByTreeID: [String: ScanFileRecord] = [:]
        for record in records {
            let treeID = TreeIdentifierPolicy.normalized(record.treeID)
            guard let existing = latestByTreeID[treeID] else {
                latestByTreeID[treeID] = record
                continue
            }
            if isOrderedBefore(record, existing) {
                latestByTreeID[treeID] = record
            }
        }
        return latestByTreeID.values.sorted(by: isOrderedBefore)
    }

    private static func isOrderedBefore(
        _ lhs: ScanFileRecord,
        _ rhs: ScanFileRecord
    ) -> Bool {
        if lhs.scanDate != rhs.scanDate {
            return lhs.scanDate > rhs.scanDate
        }
        if lhs.treeID != rhs.treeID {
            return lhs.treeID < rhs.treeID
        }
        return lhs.id < rhs.id
    }
}

struct TrendsData: Equatable, Sendable {
    let records: [ScanFileRecord]
    let maxYield: Float

    var isEmpty: Bool { records.isEmpty }

    init(records: [ScanFileRecord]) {
        self.records = records
            .filter { $0.persistenceState == .complete }
            .sorted { $0.scanDate < $1.scanDate }
        maxYield = max(self.records.map(\.yieldKg).max() ?? 1, 1)
    }
}

/// A value calendar and day keep every projection on the same time boundary.
struct DashboardAggregationContext: Equatable, Sendable {
    let calendar: Calendar
    let dayStart: Date

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        dayStart = calendar.startOfDay(for: now)
    }
}

struct DashboardAggregationInput: Sendable {
    let records: [ScanFileRecord]
    let context: DashboardAggregationContext
}

struct DashboardAggregationSnapshot: Equatable, Sendable {
    let records: [ScanFileRecord]
    let context: DashboardAggregationContext
    let daily: DashboardDailySummary
    let report: YieldReportData
    let trends: TrendsData
    let recentRecords: [ScanFileRecord]

    init(input: DashboardAggregationInput) {
        records = input.records
        context = input.context
        daily = DashboardDailySummary(records: records, calendar: context.calendar, now: context.dayStart)
        report = YieldReportData(records: records)
        trends = TrendsData(records: records)
        recentRecords = Array(records.prefix(3))
    }

    nonisolated static func build(_ input: DashboardAggregationInput) async -> DashboardAggregationSnapshot? {
        let worker = Task.detached(priority: .utility) { () -> DashboardAggregationSnapshot? in
            guard !Task.isCancelled else { return nil }
            let snapshot = DashboardAggregationSnapshot(input: input)
            return Task.isCancelled ? nil : snapshot
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

typealias DashboardAggregationBuilder = @Sendable (DashboardAggregationInput) async -> DashboardAggregationSnapshot?

/// Owned by one history store; all Dashboard consumers observe its single publication.
@MainActor
final class DashboardAggregationStore: ObservableObject {
    @Published private(set) var snapshot: DashboardAggregationSnapshot

    private let now: () -> Date
    private let calendar: () -> Calendar
    private let builder: DashboardAggregationBuilder
    private var records: [ScanFileRecord] = []
    private var requestedContext: DashboardAggregationContext
    private var generation: UInt64 = 0
    private var aggregationTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current },
        notificationCenter: NotificationCenter = .default,
        builder: @escaping DashboardAggregationBuilder = { input in
            await DashboardAggregationSnapshot.build(input)
        }
    ) {
        self.now = now
        self.calendar = calendar
        self.builder = builder
        let context = DashboardAggregationContext(now: now(), calendar: calendar())
        requestedContext = context
        snapshot = DashboardAggregationSnapshot(input: .init(records: [], context: context))
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshTimeContext() }
                .store(in: &subscriptions)
        }
    }

    deinit {
        aggregationTask?.cancel()
    }

    @discardableResult
    func updateRecords(_ records: [ScanFileRecord]) -> Task<Void, Never>? {
        let context = DashboardAggregationContext(now: now(), calendar: calendar())
        guard self.records != records || requestedContext != context else { return nil }
        self.records = records
        return schedule(context: context)
    }

    @discardableResult
    func refreshTimeContext() -> Task<Void, Never>? {
        let context = DashboardAggregationContext(now: now(), calendar: calendar())
        guard requestedContext != context else { return nil }
        return schedule(context: context)
    }

    private func schedule(context: DashboardAggregationContext) -> Task<Void, Never> {
        generation &+= 1
        let generation = generation
        requestedContext = context
        aggregationTask?.cancel()
        let input = DashboardAggregationInput(records: records, context: context)
        let builder = builder
        // Never retain the owner across a suspended builder, even if it ignores cancellation.
        let task = Task { [weak self] in
            let value = await builder(input)
            guard !Task.isCancelled else { return }
            self?.publish(value, generation: generation)
        }
        aggregationTask = task
        return task
    }

    private func publish(_ value: DashboardAggregationSnapshot?, generation: UInt64) {
        guard self.generation == generation else { return }
        aggregationTask = nil
        if let value { snapshot = value }
    }
}
