import XCTest
@testable import FruitTreeScanner

final class ScanExportReadinessTests: XCTestCase {
    func testBlockedReasonUsesReadinessTitleBeforeDepthOrPointCloud() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: false,
            scanBlockedTitle: "相机权限未开启",
            depthRuntimeStatus: "LiDAR",
            pointCount: 100
        )

        XCTAssertEqual(reason, "相机权限未开启")
    }

    func testBlockedReasonExplainsMissingDepth() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "NoDepth",
            pointCount: 0
        )

        XCTAssertEqual(reason, "当前设备没有 LiDAR 深度，无法生成有效点云")
    }

    func testBlockedReasonExplainsWaitingDepthBeforePointCloud() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "Wait",
            pointCount: 0
        )

        XCTAssertEqual(reason, "LiDAR 深度帧还未到达，请移动设备继续扫描")
    }

    func testBlockedReasonExplainsMissingPointCloud() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "LiDAR",
            pointCount: 0
        )

        XCTAssertEqual(reason, "尚未采集到可导出点云，请先按录制按钮并移动设备扫描")
    }

    func testBlockedReasonFallbackWhenAllChecksPassButExportNotReady() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "LiDAR",
            pointCount: 50
        )

        XCTAssertTrue(reason.contains("仅采集到 50 个点"))
    }

    func testBlockedReasonPriorityOrderScanNotReadyFirst() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: false,
            scanBlockedTitle: "AR 不支持",
            depthRuntimeStatus: "NoDepth",
            pointCount: 0
        )

        XCTAssertEqual(reason, "AR 不支持")
    }

    func testBlockedReasonDepthCheckedBeforePointCloud() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "NoDepth",
            pointCount: 500
        )

        XCTAssertEqual(reason, "当前设备没有 LiDAR 深度，无法生成有效点云")
    }
}
