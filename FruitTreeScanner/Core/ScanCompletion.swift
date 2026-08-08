import Foundation

struct ScanCompletion: Equatable {
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

    var statusTitle: String {
        statusTitle(in: .main)
    }

    var statusHint: String {
        statusHint(in: .main)
    }

    func statusTitle(in bundle: Bundle) -> String {
        L10n.ScanCompletion.text(statusTitleKey, in: bundle)
    }

    func statusHint(in bundle: Bundle) -> String {
        L10n.ScanCompletion.text(statusHintKey, in: bundle)
    }

    private var statusTitleKey: L10n.ScanCompletion.Key {
        if overall >= 0.85 { return .statusComplete }
        if overall >= 0.6 { return .statusCoverageGood }
        if overall >= 0.3 { return .statusContinueScanning }
        return .statusInsufficient
    }

    private var statusHintKey: L10n.ScanCompletion.Key {
        if angleCoverageScore < 0.35, voxelCount >= 80 {
            return .hintOtherSide
        }
        if oppositeSideScore < 0.45,
           angleCoverageScore >= 0.45,
           voxelCount >= 120 {
            return .hintBackSide
        }
        if verticalCoverageScore < 0.45,
           angleCoverageScore >= 0.55,
           voxelCount >= 140 {
            return .hintVertical
        }
        if angleUniformityScore < 0.50, angleCoverageScore >= 0.50, voxelCount >= 120 {
            return .hintSparseAngles
        }

        switch discoveryTrend {
        case .collecting:
            return .hintTrunk
        case .increasing:
            return .hintDiscovering
        case .decreasing:
            return .hintFinishBack
        case .stable:
            return .hintStable
        }
    }

    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
