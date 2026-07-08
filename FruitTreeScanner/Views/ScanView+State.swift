import SwiftUI

extension ScanView {
    var shouldShowPostCapturePanel: Bool {
        !isRecording && !isEstimating && !showResult && hudState.pointCount > 0
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
            exportablePointStatus: hudState.exportablePointStatus
        )
    }

    var canExportScan: Bool {
        ScanExportReadiness.canExport(
            scanIsReady: scanReadiness == .ready,
            depthRuntimeStatus: hudState.depthRuntimeStatus,
            exportablePointStatus: hudState.exportablePointStatus,
            pointCount: hudState.pointCount
        )
    }
}
