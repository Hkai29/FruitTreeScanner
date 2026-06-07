import SwiftUI

struct ScanItem: Identifiable, Equatable {
    let id: String
    let treeID: String
    let scanDate: Date
    let yieldKg: Double
    let nLidar: Int
    let meanDiameterCm: Double
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

    var confidenceColor: Color {
        switch confidence {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.error
        }
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
