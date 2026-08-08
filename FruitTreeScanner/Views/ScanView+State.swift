import SwiftUI

extension ScanView {
    var shouldShowPostCapturePanel: Bool {
        lifecycleSnapshot.state == .userPaused
            && !isRecording && !isEstimating && !showResult && hudState.pointCount > 0
    }

    var currentDetectionDebugState: DetectionDebugState? {
        return nil
    }

    var exportBlockedReason: String {
        ScanExportReadiness.blockedReason(
            scanIsReady: scanReadiness == .ready,
            scanBlockedTitle: scanReadiness.title,
            depthRuntimeStatus: hudState.depthRuntimeStatus,
            pointCount: hudState.pointCount,
            exportablePointStatus: hudState.exportablePointStatus,
            lifecycleAllowsExport: lifecycleSnapshot.state == .recording
                || lifecycleSnapshot.state == .userPaused
        )
    }

    var canExportScan: Bool {
        guard lifecycleSnapshot.state == .recording || lifecycleSnapshot.state == .userPaused else {
            return false
        }
        return ScanExportReadiness.canExport(
            scanIsReady: scanReadiness == .ready,
            depthRuntimeStatus: hudState.depthRuntimeStatus,
            exportablePointStatus: hudState.exportablePointStatus,
            pointCount: hudState.pointCount
        )
    }
}
