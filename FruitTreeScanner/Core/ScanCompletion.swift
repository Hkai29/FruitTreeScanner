import Foundation

struct ScanCompletion: Equatable {
    enum CoverageStatus: CaseIterable, Equatable {
        case complete
        case good
        case continueScanning
        case insufficient
    }

    var overall: Float = 0
    var timeScore: Float = 0
    var voxelScore: Float = 0
    var angleCoverageScore: Float = 0
    var angleUniformityScore: Float = 0
    var oppositeSideScore: Float = 1
    var verticalCoverageScore: Float = 0
    var stabilityScore: Float = 0
    var voxelCount: Int = 0
    var scanDuration: TimeInterval = 0
    var discoveryTrend: VoxelDiscoveryTrend = .collecting

    var overallPercent: Int { Int(min(overall * 100, 100)) }

    var coverageStatus: CoverageStatus {
        if overall >= 0.85 { return .complete }
        if overall >= 0.6 { return .good }
        if overall >= 0.3 { return .continueScanning }
        return .insufficient
    }

    var statusTitle: String {
        switch coverageStatus {
        case .complete: return "扫描完成"
        case .good: return "覆盖良好"
        case .continueScanning: return "继续扫描"
        case .insufficient: return "覆盖率不足"
        }
    }

    var statusHint: String {
        if angleCoverageScore < 0.35, voxelCount >= 80 {
            return "补扫树冠另一侧"
        }
        if oppositeSideScore < 0.45,
           angleCoverageScore >= 0.45,
           voxelCount >= 120 {
            return "补扫树冠背面"
        }
        if verticalCoverageScore < 0.45,
           angleCoverageScore >= 0.55,
           voxelCount >= 140 {
            return "放慢补扫树冠上下层"
        }
        if angleUniformityScore < 0.50, angleCoverageScore >= 0.50, voxelCount >= 120 {
            return "补扫稀疏视角"
        }

        switch discoveryTrend {
        case .collecting:
            return "从主干开始慢速环绕"
        case .increasing:
            return "正在发现树冠新区域"
        case .decreasing:
            return "补树冠背面后可保存"
        case .stable:
            return "覆盖完整，可保存分析"
        }
    }

    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
