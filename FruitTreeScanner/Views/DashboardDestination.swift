import Foundation

enum DashboardDestination: Identifiable, Equatable {
    case settings
    case startScan
    case quickScan
    case calibration
    case scanHistory
    case pointCloud(URL?)
    case tagManagement
    case yieldReport
    case compare
    case trends
    case map
    case importFile
    case batchExport

    var id: String {
        switch self {
        case .settings: return "settings"
        case .startScan: return "startScan"
        case .quickScan: return "quickScan"
        case .calibration: return "calibration"
        case .scanHistory: return "scanHistory"
        case .pointCloud(let url): return "pointCloud:\(url?.absoluteString ?? "latest")"
        case .tagManagement: return "tagManagement"
        case .yieldReport: return "yieldReport"
        case .compare: return "compare"
        case .trends: return "trends"
        case .map: return "map"
        case .importFile: return "importFile"
        case .batchExport: return "batchExport"
        }
    }

    var isFullScreen: Bool {
        self == .startScan || self == .quickScan
    }
}
