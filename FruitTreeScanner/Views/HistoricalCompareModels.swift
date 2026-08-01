import SwiftUI

struct ScanItem: Identifiable, Equatable {
    let id: String
    let treeID: String
    let scanDate: Date
    let yieldKg: Double
    let fruitCount: Int
    let meanDiameterCm: Double?
    let confidence: String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var dateFormatted: String {
        Self.dateFormatter.string(from: scanDate)
    }

    var yieldFormatted: String {
        String(format: "%.1f kg", yieldKg)
    }

    var diameterFormatted: String {
        guard let meanDiameterCm else { return "--" }
        return String(format: "%.1f", meanDiameterCm)
    }

    var confidenceFormatted: String {
        confidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "--"
            : confidence
    }

    var confidenceColor: Color {
        switch confidence {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.error
        }
    }

    func yieldChangePercent(to comparison: ScanItem) -> Double? {
        guard yieldKg > 0 else { return nil }
        return ((comparison.yieldKg - yieldKg) / yieldKg) * 100
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
                fruitCount: record.fruitCount,
                meanDiameterCm: nil,
                confidence: record.confidence
            )
        }
    }
}

struct HistoricalCompareSelection: Equatable {
    let first: ScanItem?
    let second: ScanItem?
}

enum HistoricalCompareSelectionPolicy {
    static func reconciled(
        first: ScanItem?,
        second: ScanItem?,
        availableItems: [ScanItem]
    ) -> HistoricalCompareSelection {
        let refreshedFirst = item(withID: first?.id, in: availableItems)
        var refreshedSecond = item(withID: second?.id, in: availableItems)
        if refreshedFirst?.id == refreshedSecond?.id {
            refreshedSecond = nil
        }
        return HistoricalCompareSelection(
            first: refreshedFirst,
            second: refreshedSecond
        )
    }

    static func selectableItems(
        from availableItems: [ScanItem],
        excluding selectedInOtherSlot: ScanItem?
    ) -> [ScanItem] {
        guard let excludedID = selectedInOtherSlot?.id else { return availableItems }
        return availableItems.filter { $0.id != excludedID }
    }

    private static func item(withID id: String?, in items: [ScanItem]) -> ScanItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }
}

enum TrendDirection {
    case up
    case down
    case neutral

    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up: return Design.Colors.Dark.success
        case .down: return Design.Colors.Dark.error
        case .neutral: return Design.Colors.Dark.textSecondary
        }
    }
}
