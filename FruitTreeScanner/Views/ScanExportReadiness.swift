import Foundation

struct ScanExportReadiness {
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
