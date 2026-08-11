import SwiftUI

struct HistoricalComparePresentation: Equatable {
    let title: String
    let subtitle: String
    let navigationTitle: String
    let emptyTitle: String
    let startScan: String
    let prompt: String
    let scanA: String
    let scanB: String
    let versus: String
    let selectScan: String
    let noScanSelected: String
    let pickerTitle: String
    let cancel: String
    let yieldChange: String
    let lidarDetections: String
    let averageDiameter: String
    let confidence: String
    let scanDate: String

    private let emptyMessageOne: String
    private let emptyMessageOtherFormat: String
    private let selectionHintFormat: String
    private let pickerSelectionHintFormat: String
    private let pickerValueFormat: String
    private let treeTitleFormat: String
    private let scanSummaryFormat: String
    private let comparisonValuesFormat: String
    private let comparisonValueFormat: String
    private let yieldAccessibilityValueFormat: String
    private let fruitUnitOne: String
    private let fruitUnitOther: String
    private let kilogramsUnit: String
    private let centimetersUnit: String
    private let unavailableValue: String
    private let confidenceHigh: String
    private let confidenceMedium: String
    private let confidenceLow: String
    private let confidenceManualReview: String
    private let confidenceUnknown: String
    private let trendIncreased: String
    private let trendDecreased: String
    private let trendUnchanged: String
    private let trendUnavailable: String
    private let pickerSelected: String
    private let pickerNotSelected: String

    init(bundle: Bundle = .main) {
        func localized(_ key: String, fallback: String) -> String {
            bundle.localizedString(forKey: key, value: fallback, table: nil)
        }

        title = localized("historical_compare.title", fallback: "树体对比")
        subtitle = localized(
            "historical_compare.subtitle",
            fallback: "选择两条完整扫描，并排比较产量、果数和日期变化。"
        )
        navigationTitle = localized("historical_compare.navigation_title", fallback: "历史对比")
        emptyTitle = localized("historical_compare.empty_title", fallback: "至少需要两条完整扫描")
        emptyMessageOne = localized(
            "historical_compare.empty_message_one",
            fallback: "当前只有 1 条完整扫描。完成两次扫描并保存完整结果后，就可以比较产量、果数和日期变化。"
        )
        emptyMessageOtherFormat = localized(
            "historical_compare.empty_message_other_format",
            fallback: "当前只有 %@ 条完整扫描。完成两次扫描并保存完整结果后，就可以比较产量、果数和日期变化。"
        )
        startScan = localized("historical_compare.start_scan", fallback: "开始扫描")
        prompt = localized(
            "historical_compare.prompt",
            fallback: "选择两条扫描记录后，会显示产量、果实数和日期的并排对比。"
        )
        scanA = localized("historical_compare.scan_a", fallback: "扫描 A")
        scanB = localized("historical_compare.scan_b", fallback: "扫描 B")
        versus = localized("historical_compare.versus", fallback: "对比")
        selectScan = localized("historical_compare.select_scan", fallback: "选择扫描")
        noScanSelected = localized("historical_compare.no_scan_selected", fallback: "尚未选择扫描")
        selectionHintFormat = localized(
            "historical_compare.selection_hint_format",
            fallback: "为%@选择一条完整扫描记录。"
        )
        pickerTitle = localized("historical_compare.picker_title", fallback: "选择扫描")
        cancel = localized("common.cancel", fallback: "取消")
        pickerSelectionHintFormat = localized(
            "historical_compare.picker.selection_hint_format",
            fallback: "将这条记录用于%@。"
        )
        pickerValueFormat = localized("historical_compare.picker.value_format", fallback: "%@；%@")
        yieldChange = localized("historical_compare.yield_change", fallback: "产量变化")
        lidarDetections = localized("historical_compare.lidar_detections", fallback: "LiDAR 检测")
        averageDiameter = localized("historical_compare.average_diameter", fallback: "平均直径")
        confidence = localized("historical_compare.confidence", fallback: "置信度")
        scanDate = localized("historical_compare.scan_date", fallback: "扫描日期")
        treeTitleFormat = localized("historical_compare.tree_title_format", fallback: "树 %@")
        scanSummaryFormat = localized("historical_compare.scan_summary_format", fallback: "%@，%@，%@")
        comparisonValuesFormat = localized(
            "historical_compare.comparison_values_format",
            fallback: "%@：%@；%@：%@。"
        )
        comparisonValueFormat = localized(
            "historical_compare.comparison_value_format",
            fallback: "%@：%@；%@：%@；%@。"
        )
        yieldAccessibilityValueFormat = localized(
            "historical_compare.yield_accessibility_value_format",
            fallback: "%@ %@：%@；%@ %@：%@；变化%@，%@。"
        )
        fruitUnitOne = localized("historical_compare.unit.fruit_one", fallback: "个果实")
        fruitUnitOther = localized("historical_compare.unit.fruit_other", fallback: "个果实")
        kilogramsUnit = localized("historical_compare.unit.kilograms", fallback: "kg")
        centimetersUnit = localized("historical_compare.unit.centimeters", fallback: "cm")
        unavailableValue = localized("historical_compare.unavailable", fallback: "不可用")
        confidenceHigh = localized("historical_compare.confidence.high", fallback: "高")
        confidenceMedium = localized("historical_compare.confidence.medium", fallback: "中")
        confidenceLow = localized("historical_compare.confidence.low", fallback: "低")
        confidenceManualReview = localized("historical_compare.confidence.manual_review", fallback: "需人工复核")
        confidenceUnknown = localized("historical_compare.confidence.unknown", fallback: "未知")
        trendIncreased = localized("historical_compare.trend.increased", fallback: "上升")
        trendDecreased = localized("historical_compare.trend.decreased", fallback: "下降")
        trendUnchanged = localized("historical_compare.trend.unchanged", fallback: "无变化")
        trendUnavailable = localized("historical_compare.trend.unavailable", fallback: "变化不可用")
        pickerSelected = localized("historical_compare.picker.selected", fallback: "已选择")
        pickerNotSelected = localized("historical_compare.picker.not_selected", fallback: "未选择")
    }

    func emptyMessage(scanCount: Int, locale: Locale) -> String {
        if scanCount == 1 { return emptyMessageOne }
        return String(format: emptyMessageOtherFormat, integerText(scanCount, locale: locale))
    }

    func treeTitle(_ treeID: String) -> String {
        String(format: treeTitleFormat, treeID)
    }

    func dateText(_ date: Date, locale: Locale) -> String {
        date.formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
        )
    }

    func yieldText(_ value: Double, locale: Locale) -> String {
        "\(decimalText(value, locale: locale)) \(kilogramsUnit)"
    }

    func diameterText(_ value: Double?, locale: Locale) -> String {
        guard let value else { return unavailableValue }
        return "\(decimalText(value, locale: locale)) \(centimetersUnit)"
    }

    func fruitCountText(_ count: Int, locale: Locale) -> String {
        let unit = count == 1 ? fruitUnitOne : fruitUnitOther
        return "\(integerText(count, locale: locale)) \(unit)"
    }

    func confidenceText(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return confidenceHigh
        case "medium": return confidenceMedium
        case "low": return confidenceLow
        case "manual_review": return confidenceManualReview
        case "": return unavailableValue
        default: return confidenceUnknown
        }
    }

    func percentageText(_ proportionalChange: Double?, locale: Locale) -> String {
        guard let proportionalChange else { return unavailableValue }
        return proportionalChange.formatted(
            .percent
                .locale(locale)
                .precision(.fractionLength(1))
                .sign(strategy: .always(includingZero: true))
        )
    }

    func trendText(_ trend: TrendDirection) -> String {
        switch trend {
        case .up: return trendIncreased
        case .down: return trendDecreased
        case .neutral: return trendUnchanged
        case .unavailable: return trendUnavailable
        }
    }

    func selectionValue(scan: ScanItem?, locale: Locale) -> String {
        guard let scan else { return noScanSelected }
        return scanSummary(scan, locale: locale)
    }

    func selectionHint(slot: String) -> String {
        String(format: selectionHintFormat, slot)
    }

    func pickerSelectionHint(slot: String) -> String {
        String(format: pickerSelectionHintFormat, slot)
    }

    func pickerState(isSelected: Bool) -> String {
        isSelected ? pickerSelected : pickerNotSelected
    }

    func pickerValue(scan: ScanItem, isSelected: Bool, locale: Locale) -> String {
        String(
            format: pickerValueFormat,
            scanSummary(scan, locale: locale),
            pickerState(isSelected: isSelected)
        )
    }

    func comparisonValue(
        value1: String,
        value2: String,
        trend: TrendDirection?
    ) -> String {
        guard let trend else {
            return String(format: comparisonValuesFormat, scanA, value1, scanB, value2)
        }
        return String(
            format: comparisonValueFormat,
            scanA,
            value1,
            scanB,
            value2,
            trendText(trend)
        )
    }

    func yieldComparisonValue(
        scan1: ScanItem,
        scan2: ScanItem,
        proportionalChange: Double?,
        locale: Locale
    ) -> String {
        let trend = HistoricalCompareMetrics.trend(for: proportionalChange)
        return String(
            format: yieldAccessibilityValueFormat,
            scanA,
            treeTitle(scan1.treeID),
            yieldText(scan1.yieldKg, locale: locale),
            scanB,
            treeTitle(scan2.treeID),
            yieldText(scan2.yieldKg, locale: locale),
            percentageText(proportionalChange, locale: locale),
            trendText(trend)
        )
    }

    private func scanSummary(_ scan: ScanItem, locale: Locale) -> String {
        String(
            format: scanSummaryFormat,
            treeTitle(scan.treeID),
            dateText(scan.scanDate, locale: locale),
            yieldText(scan.yieldKg, locale: locale)
        )
    }

    private func integerText(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.automatic))
    }

    private func decimalText(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(1))
        )
    }
}

private struct HistoricalComparePresentationEnvironmentKey: EnvironmentKey {
    static let defaultValue = HistoricalComparePresentation()
}

extension EnvironmentValues {
    var historicalComparePresentation: HistoricalComparePresentation {
        get { self[HistoricalComparePresentationEnvironmentKey.self] }
        set { self[HistoricalComparePresentationEnvironmentKey.self] = newValue }
    }
}

struct ScanItem: Identifiable, Equatable {
    let id: String
    let treeID: String
    let scanDate: Date
    let yieldKg: Double
    let nLidar: Int
    let meanDiameterCm: Double?
    let confidence: String

    var dateFormatted: String {
        HistoricalComparePresentation().dateText(scanDate, locale: .current)
    }

    var yieldFormatted: String {
        HistoricalComparePresentation().yieldText(yieldKg, locale: .current)
    }

    var diameterFormatted: String {
        HistoricalComparePresentation().diameterText(meanDiameterCm, locale: .current)
    }

    var confidenceFormatted: String {
        HistoricalComparePresentation().confidenceText(confidence)
    }

    var confidenceColor: Color {
        switch confidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        case "low": return Design.Colors.Dark.error
        default: return Design.Colors.Dark.textSecondary
        }
    }
}

enum HistoricalCompareDataSource {
    static func items(from records: [ScanFileRecord]) -> [ScanItem] {
        records.compactMap { record in
            guard record.persistenceState == .complete else { return nil }
            return ScanItem(
                id: record.id,
                treeID: record.treeID,
                scanDate: record.scanDate,
                yieldKg: Double(record.yieldKg),
                nLidar: record.fruitCount,
                meanDiameterCm: nil,
                confidence: record.confidence
            )
        }
    }
}

enum HistoricalCompareSelectionPolicy {
    static func reconciledSelection(
        _ selection: ScanItem?,
        availableScans: [ScanItem]
    ) -> ScanItem? {
        guard let selection else { return nil }
        return availableScans.first { $0.id == selection.id }
    }
}

enum HistoricalCompareMetrics {
    static func proportionalYieldChange(from baseline: Double, to comparison: Double) -> Double? {
        guard baseline.isFinite, comparison.isFinite, baseline > 0 else { return nil }
        let change = (comparison - baseline) / baseline
        return change.isFinite ? change : nil
    }

    static func trend<T: Comparable>(from value1: T, to value2: T) -> TrendDirection {
        if value1 < value2 { return .up }
        if value1 > value2 { return .down }
        return .neutral
    }

    static func trend<T: Comparable>(from value1: T?, to value2: T?) -> TrendDirection {
        guard let value1, let value2 else { return .unavailable }
        return trend(from: value1, to: value2)
    }

    static func trend(for proportionalChange: Double?) -> TrendDirection {
        guard let proportionalChange else { return .unavailable }
        if proportionalChange > 0 { return .up }
        if proportionalChange < 0 { return .down }
        return .neutral
    }
}

enum TrendDirection {
    case up
    case down
    case neutral
    case unavailable

    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        case .unavailable: return "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .up: return Design.Colors.Dark.success
        case .down: return Design.Colors.Dark.error
        case .neutral, .unavailable: return Design.Colors.Dark.textSecondary
        }
    }
}
