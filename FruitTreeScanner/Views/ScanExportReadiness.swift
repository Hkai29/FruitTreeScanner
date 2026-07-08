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
        exportablePointStatus: String = "Ready"
    ) -> String {
        if !scanIsReady {
            return scanBlockedTitle
        }
        if depthRuntimeStatus == "NoDepth" {
            return "当前设备没有 LiDAR 深度，无法生成有效点云"
        }
        if depthRuntimeStatus == "Wait" {
            return "LiDAR 深度帧还未到达，请移动设备继续扫描"
        }
        if exportablePointStatus != "Ready" || pointCount == 0 {
            return "尚未采集到可导出点云，请先按录制按钮并移动设备扫描"
        }
        if pointCount < minimumExportablePointCount {
            return "仅采集到 \(pointCount) 个点（建议至少 200+），请继续从不同角度扫描树冠"
        }
        return "点云数量 (\(pointCount) 点) 仍不足以估算产量，请扩大扫描覆盖范围后重试"
    }
}
