import Foundation

struct ScanExportReadiness {
    enum RetryAction: Equatable {
        case unavailable, exportPointCloud, estimateYield, persistResult
    }

    static func retryAction(
        state: ScanLifecycleState,
        hasResult: Bool,
        canRetryPersistence: Bool,
        filename: String,
        currentScanIdentity: UUID?,
        resultScanIdentity: UUID?
    ) -> RetryAction {
        guard state == .finishing else { return .unavailable }
        if hasResult {
            guard canRetryPersistence, !filename.isEmpty, let currentScanIdentity,
                  resultScanIdentity == currentScanIdentity else { return .unavailable }
            return .persistResult
        }
        return .exportPointCloud
    }

    static let minimumExportablePointCount = 100

    static func canExport(
        scanIsReady: Bool,
        depthRuntimeStatus: String,
        exportablePointStatus: String,
        pointCount: Int
    ) -> Bool {
        scanIsReady
            && depthRuntimeStatus == "LiDAR"
            && exportablePointStatus == "Ready"
            && pointCount >= minimumExportablePointCount
    }

    static func blockedReason(
        scanIsReady: Bool,
        scanBlockedTitle: String,
        depthRuntimeStatus: String,
        pointCount: Int,
        exportablePointStatus: String = "Ready",
        lifecycleAllowsExport: Bool = true,
        in bundle: Bundle = .main
    ) -> String {
        if !scanIsReady {
            return scanBlockedTitle
        }
        if !lifecycleAllowsExport {
            return L10n.ScanExport.text(.lifecycleBlocked, in: bundle)
        }
        if depthRuntimeStatus == "NoDepth" {
            return L10n.ScanExport.text(.noDepth, in: bundle)
        }
        if depthRuntimeStatus == "Wait" {
            return L10n.ScanExport.text(.waitingDepth, in: bundle)
        }
        if depthRuntimeStatus != "LiDAR" {
            return L10n.ScanExport.text(.depthUnavailable, in: bundle)
        }
        if exportablePointStatus != "Ready" || pointCount == 0 {
            return L10n.ScanExport.text(.noCloud, in: bundle)
        }
        if pointCount < minimumExportablePointCount {
            return L10n.ScanExport.tooFewPoints(pointCount, in: bundle)
        }
        return L10n.ScanExport.text(.preparing, in: bundle)
    }

    static func finishControlIsDisabled(isEstimating: Bool) -> Bool {
        isEstimating
    }
}
