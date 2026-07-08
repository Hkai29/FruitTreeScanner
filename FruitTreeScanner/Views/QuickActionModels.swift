import SwiftUI

enum QuickActionKind: String {
    case startScan
    case quickScan
    case calibration
    case scanHistory
    case pointCloud
    case tagManagement
    case yieldReport
    case compare
    case trends
    case map
    case importFile
    case batchExport
}

struct QuickAction: Identifiable {
    let kind: QuickActionKind
    let title: String
    let icon: String
    let color: Color
    let description: String

    var id: QuickActionKind { kind }

    var imageName: String {
        switch kind {
        case .startScan: return "FeatureStartScan"
        case .quickScan: return "FeatureQuickScan"
        case .calibration: return "FeatureCalibration"
        case .scanHistory: return "FeatureScanHistory"
        case .pointCloud: return "FeaturePointCloud"
        case .tagManagement: return "FeatureTagManagement"
        case .yieldReport: return "FeatureYieldReport"
        case .compare: return "FeatureCompare"
        case .trends: return "FeatureTrends"
        case .map: return "FeatureMap"
        case .importFile: return "FeatureImportFile"
        case .batchExport: return "FeatureBatchExport"
        }
    }
}
