import XCTest
import SwiftUI
import UIKit
@testable import FruitTreeScanner

final class ScanExportReadinessTests: XCTestCase {
    func testScanExportReadinessCopyExistsInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "scan.export.requirements_action": "View Requirements",
                "scan.export.requirements_hint": "Shows what is needed before this scan can finish.",
                "scan.export.blocked.lifecycle": "This scan cannot finish in its current state. Start recording or wait for scanning to recover.",
                "scan.export.blocked.no_depth": "LiDAR depth is unavailable on this device, so a valid point cloud cannot be created.",
                "scan.export.blocked.waiting_depth": "LiDAR depth frames have not arrived yet. Move the device and continue scanning.",
                "scan.export.blocked.depth_unavailable": "LiDAR depth is not ready. Keep the camera active and try again.",
                "scan.export.blocked.no_cloud": "No exportable point cloud has been captured. Tap Record and move around the tree.",
                "scan.export.blocked.too_few_points_format": "Only %lld points captured (at least 200 recommended). Continue scanning the canopy from different angles.",
                "scan.export.blocked.preparing": "Scan data is still being prepared. Wait a moment and try Finish again.",
            ],
            "zh": [
                "scan.export.requirements_action": "查看要求",
                "scan.export.requirements_hint": "点击查看完成本次扫描前还需要满足的条件。",
                "scan.export.blocked.lifecycle": "当前扫描状态还不能完成，请开始录制或等待扫描恢复。",
                "scan.export.blocked.no_depth": "当前设备没有 LiDAR 深度，无法生成有效点云",
                "scan.export.blocked.waiting_depth": "LiDAR 深度帧还未到达，请移动设备继续扫描",
                "scan.export.blocked.depth_unavailable": "LiDAR 深度尚未就绪，请保持相机活跃后重试",
                "scan.export.blocked.no_cloud": "尚未采集到可导出点云，请先按录制按钮并移动设备扫描",
                "scan.export.blocked.too_few_points_format": "仅采集到 %lld 个点（建议至少 200+），请继续从不同角度扫描树冠",
                "scan.export.blocked.preparing": "扫描数据仍在准备中，请稍候后重试完成",
            ],
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testBlockedReasonCoversLifecycleUnknownDepthAndPreparationRaces() throws {
        let bundle = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )

        XCTAssertEqual(
            ScanExportReadiness.blockedReason(
                scanIsReady: true,
                scanBlockedTitle: "",
                depthRuntimeStatus: "LiDAR",
                pointCount: 500,
                lifecycleAllowsExport: false,
                in: bundle
            ),
            "This scan cannot finish in its current state. Start recording or wait for scanning to recover."
        )
        XCTAssertEqual(
            ScanExportReadiness.blockedReason(
                scanIsReady: true,
                scanBlockedTitle: "",
                depthRuntimeStatus: "NoAR",
                pointCount: 500,
                in: bundle
            ),
            "LiDAR depth is not ready. Keep the camera active and try again."
        )
        XCTAssertEqual(
            ScanExportReadiness.blockedReason(
                scanIsReady: true,
                scanBlockedTitle: "",
                depthRuntimeStatus: "LiDAR",
                pointCount: 500,
                in: bundle
            ),
            "Scan data is still being prepared. Wait a moment and try Finish again."
        )
    }

    func testFinishControlDisablesOnlyWhileEstimationIsRunning() {
        XCTAssertFalse(ScanExportReadiness.finishControlIsDisabled(isEstimating: false))
        XCTAssertTrue(ScanExportReadiness.finishControlIsDisabled(isEstimating: true))
    }

    @MainActor
    func testBlockedReasonToastRendersInCompactLayout() throws {
        let message = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "LiDAR",
            pointCount: 42
        )
        let content = ScanNoticeToast(message: message)
            .frame(width: 390, height: 844)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 390, height: 844)
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 390, height: 844))

        let attachment = XCTAttachment(image: image)
        attachment.name = "ScanExportBlockedReason-\(Locale.preferredLanguages.first ?? "unknown")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    func testBlockedReasonExplainsNoExportableCloudEvenWithRawPointCount() {
        let reason = ScanExportReadiness.blockedReason(
            scanIsReady: true,
            scanBlockedTitle: "",
            depthRuntimeStatus: "LiDAR",
            pointCount: 500,
            exportablePointStatus: "NoCloud"
        )

        XCTAssertEqual(reason, "尚未采集到可导出点云，请先按录制按钮并移动设备扫描")
    }

    func testCanExportRequiresActiveDepthReadyCloudAndMinimumPointCount() {
        XCTAssertTrue(ScanExportReadiness.canExport(
            scanIsReady: true,
            depthRuntimeStatus: "LiDAR",
            exportablePointStatus: "Ready",
            pointCount: 200
        ))

        XCTAssertFalse(ScanExportReadiness.canExport(
            scanIsReady: true,
            depthRuntimeStatus: "LiDAR",
            exportablePointStatus: "Ready",
            pointCount: 99
        ))

        XCTAssertFalse(ScanExportReadiness.canExport(
            scanIsReady: true,
            depthRuntimeStatus: "LiDAR",
            exportablePointStatus: "NoCloud",
            pointCount: 500
        ))

        XCTAssertFalse(ScanExportReadiness.canExport(
            scanIsReady: true,
            depthRuntimeStatus: "Wait",
            exportablePointStatus: "Ready",
            pointCount: 500
        ))
    }
}
