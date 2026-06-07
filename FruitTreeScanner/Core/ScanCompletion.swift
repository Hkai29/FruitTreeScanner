import Foundation

struct ScanCompletion: Equatable {
    var overall: Float = 0
    var timeScore: Float = 0
    var voxelScore: Float = 0
    var stabilityScore: Float = 0
    var voxelCount: Int = 0
    var scanDuration: TimeInterval = 0
    var discoveryTrend: VoxelDiscoveryTrend = .collecting

    var overallPercent: Int { Int(min(overall * 100, 100)) }

    var statusTitle: String {
        if overall >= 0.85 { return "扫描完成" }
        if overall >= 0.6 { return "覆盖良好" }
        if overall >= 0.3 { return "继续扫描" }
        return "覆盖率不足"
    }

    var statusHint: String {
        switch discoveryTrend {
        case .collecting:
            return "请环绕果树扫描"
        case .increasing:
            return "持续发现新区域"
        case .decreasing:
            return "接近完成，可保存"
        case .stable:
            return "覆盖完整，可保存"
        }
    }

    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
