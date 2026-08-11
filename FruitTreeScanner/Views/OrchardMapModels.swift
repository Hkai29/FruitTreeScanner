import SwiftUI
import MapKit

struct OrchardMapPresentation: Equatable {
    let closeMap: String
    let closeMapHint: String
    let emptyTitle: String
    let emptyMessage: String
    let startScan: String
    let orchardTrees: String
    let estimatedYield: String
    let fruitCount: String
    let confidence: String
    let scanDate: String
    let yieldLevelTitle: String
    let filterSelected: String
    let filterNotSelected: String
    let filterHint: String
    let filterSelectedHint: String
    let clearFilter: String
    let clearFilterHint: String
    let closeDetails: String
    let closeDetailsHint: String
    let selectTreeHint: String
    let requiresIOS17: String

    private let confidenceHigh: String
    private let confidenceMedium: String
    private let confidenceLow: String
    private let confidenceUnknown: String
    private let yieldHigh: String
    private let yieldMedium: String
    private let yieldLow: String
    private let treeTitleFormat: String
    private let pinValueFormat: String
    private let treeUnitOne: String
    private let treeUnitOther: String
    private let fruitUnitOne: String
    private let fruitUnitOther: String
    private let kilogramsUnit: String

    init(bundle: Bundle = .main) {
        func localized(_ key: String, fallback: String) -> String {
            bundle.localizedString(forKey: key, value: fallback, table: nil)
        }

        closeMap = localized("orchard_map.close", fallback: "关闭果园地图")
        closeMapHint = localized("orchard_map.close_hint", fallback: "关闭果园地图视图。")
        emptyTitle = localized("orchard_map.empty_title", fallback: "暂无定位扫描")
        emptyMessage = localized(
            "orchard_map.empty_message",
            fallback: "带 GPS 的完整扫描记录会显示在果园地图中，用于查看可靠产量分布。"
        )
        startScan = localized("orchard_map.start_scan", fallback: "开始扫描")
        orchardTrees = localized("orchard_map.orchard_trees", fallback: "园区树木")
        estimatedYield = localized("orchard_map.estimated_yield", fallback: "预估产量")
        fruitCount = localized("orchard_map.fruit_count", fallback: "果实数")
        confidence = localized("orchard_map.confidence", fallback: "置信度")
        scanDate = localized("orchard_map.scan_date", fallback: "扫描日期")
        yieldLevelTitle = localized("orchard_map.yield_level", fallback: "产量等级")
        filterSelected = localized("orchard_map.filter.selected", fallback: "已选择")
        filterNotSelected = localized("orchard_map.filter.not_selected", fallback: "未选择")
        filterHint = localized("orchard_map.filter.hint", fallback: "仅显示此产量等级的树体。")
        filterSelectedHint = localized("orchard_map.filter.selected_hint", fallback: "取消此产量等级筛选。")
        clearFilter = localized("orchard_map.filter.clear", fallback: "清除产量筛选")
        clearFilterHint = localized("orchard_map.filter.clear_hint", fallback: "显示全部有定位的树体。")
        closeDetails = localized("orchard_map.details.close", fallback: "关闭树体详情")
        closeDetailsHint = localized("orchard_map.details.close_hint", fallback: "隐藏当前树体的扫描详情。")
        selectTreeHint = localized("orchard_map.pin.select_hint", fallback: "显示这棵树的扫描详情。")
        requiresIOS17 = localized("orchard_map.requires_ios17", fallback: "果园地图需要 iOS 17 或更高版本。")
        confidenceHigh = localized("orchard_map.confidence.high", fallback: "高")
        confidenceMedium = localized("orchard_map.confidence.medium", fallback: "中")
        confidenceLow = localized("orchard_map.confidence.low", fallback: "低")
        confidenceUnknown = localized("orchard_map.confidence.unknown", fallback: "未知")
        yieldHigh = localized("orchard_map.yield.high", fallback: "高产")
        yieldMedium = localized("orchard_map.yield.medium", fallback: "中产")
        yieldLow = localized("orchard_map.yield.low", fallback: "低产")
        treeTitleFormat = localized("orchard_map.tree_title_format", fallback: "树 %@")
        pinValueFormat = localized("orchard_map.pin_value_format", fallback: "%@，%@，%@")
        treeUnitOne = localized("orchard_map.unit.tree_one", fallback: "棵")
        treeUnitOther = localized("orchard_map.unit.tree_other", fallback: "棵")
        fruitUnitOne = localized("orchard_map.unit.fruit_one", fallback: "个")
        fruitUnitOther = localized("orchard_map.unit.fruit_other", fallback: "个")
        kilogramsUnit = localized("orchard_map.unit.kilograms", fallback: "kg")
    }

    func yieldLevelLabel(_ level: YieldLevel) -> String {
        switch level {
        case .high: return yieldHigh
        case .medium: return yieldMedium
        case .low: return yieldLow
        }
    }

    func confidenceLabel(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return confidenceHigh
        case "medium": return confidenceMedium
        case "low": return confidenceLow
        default: return confidenceUnknown
        }
    }

    func treeTitle(_ treeID: String) -> String {
        String(format: treeTitleFormat, treeID)
    }

    func treeCountText(_ count: Int, locale: Locale) -> String {
        "\(integerText(count, locale: locale)) \(count == 1 ? treeUnitOne : treeUnitOther)"
    }

    func fruitCountText(_ count: Int, locale: Locale) -> String {
        "\(integerText(count, locale: locale)) \(count == 1 ? fruitUnitOne : fruitUnitOther)"
    }

    func integerText(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.automatic))
    }

    func yieldText(_ weight: Double, locale: Locale) -> String {
        "\(formattedDecimal(weight, locale: locale)) \(kilogramsUnit)"
    }

    func scanDateText(_ date: Date, locale: Locale) -> String {
        date.formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
        )
    }

    func mapPinValue(for tree: TreeAnnotation, locale: Locale) -> String {
        String(
            format: pinValueFormat,
            yieldLevelLabel(tree.yieldLevel),
            yieldText(tree.weight, locale: locale),
            fruitCountText(tree.fruitCount, locale: locale)
        )
    }

    private func formattedDecimal(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(1))
        )
    }
}

private struct OrchardMapPresentationEnvironmentKey: EnvironmentKey {
    static let defaultValue = OrchardMapPresentation()
}

extension EnvironmentValues {
    var orchardMapPresentation: OrchardMapPresentation {
        get { self[OrchardMapPresentationEnvironmentKey.self] }
        set { self[OrchardMapPresentationEnvironmentKey.self] = newValue }
    }
}

struct OrchardMapData {
    let trees: [TreeAnnotation]

    init(records: [ScanFileRecord]) {
        trees = records
            .filter {
                $0.persistenceState == .complete &&
                    $0.gpsLat != 0 &&
                    $0.gpsLon != 0
            }
            .map(TreeAnnotation.init(record:))
    }
}

struct TreeAnnotation: Identifiable, Hashable {
    let id: String
    let treeID: String
    let coordinate: CLLocationCoordinate2D
    let weight: Double
    let confidence: String
    let scanDate: Date
    let fruitCount: Int

    init(
        id: String,
        treeID: String,
        coordinate: CLLocationCoordinate2D,
        weight: Double,
        confidence: String,
        scanDate: Date,
        fruitCount: Int
    ) {
        self.id = id
        self.treeID = treeID
        self.coordinate = coordinate
        self.weight = weight
        self.confidence = confidence
        self.scanDate = scanDate
        self.fruitCount = fruitCount
    }

    init(record: ScanFileRecord) {
        self.init(
            id: record.id,
            treeID: record.treeID,
            coordinate: CLLocationCoordinate2D(latitude: record.gpsLat, longitude: record.gpsLon),
            weight: Double(record.yieldKg),
            confidence: record.confidence,
            scanDate: record.scanDate,
            fruitCount: record.fruitCount
        )
    }

    var yieldLevel: YieldLevel {
        if weight > 45 { return .high }
        if weight >= 35 { return .medium }
        return .low
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TreeAnnotation, rhs: TreeAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

enum YieldLevel: CaseIterable {
    case high
    case medium
    case low

    var color: Color {
        switch self {
        case .high: return Design.Colors.Dark.success
        case .medium: return Design.Colors.Dark.warning
        case .low: return Design.Colors.Dark.error
        }
    }

    var icon: String {
        switch self {
        case .high: return "arrow.up.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle.fill"
        }
    }
}

struct TreeYieldSummary {
    let totalCount: Int
    private let countsByLevel: [YieldLevel: Int]

    init(trees: [TreeAnnotation]) {
        var counts = Dictionary(uniqueKeysWithValues: YieldLevel.allCases.map { ($0, 0) })
        for tree in trees {
            counts[tree.yieldLevel, default: 0] += 1
        }
        totalCount = trees.count
        countsByLevel = counts
    }

    func count(for level: YieldLevel) -> Int {
        countsByLevel[level, default: 0]
    }
}

enum OrchardMapRegionCalculator {
    static func region(for trees: [TreeAnnotation]) -> MKCoordinateRegion? {
        guard let firstTree = trees.first else { return nil }

        let latValues = trees.map { $0.coordinate.latitude }
        let lonValues = trees.map { $0.coordinate.longitude }

        let minLat = latValues.min() ?? firstTree.coordinate.latitude
        let maxLat = latValues.max() ?? firstTree.coordinate.latitude
        let minLon = lonValues.min() ?? firstTree.coordinate.longitude
        let maxLon = lonValues.max() ?? firstTree.coordinate.longitude

        let latDelta = max((maxLat - minLat) * 1.5, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.005)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
