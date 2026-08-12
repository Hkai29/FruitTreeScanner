import XCTest
import ARKit
import AVFoundation
import SwiftUI
import UIKit
@testable import FruitTreeScanner

final class ScanReadinessTests: XCTestCase {
    private let englishReadinessCopy = [
        "scan.readiness.checking.title": "Checking Device Capabilities",
        "scan.readiness.checking.message": "Checking the camera, ARKit, and depth scanning capabilities.",
        "scan.readiness.ar_unsupported.title": "AR Scanning Unavailable",
        "scan.readiness.ar_unsupported.message": "FruitTreeScanner requires ARKit to capture point clouds. Use an ARKit-compatible iPhone or iPad.",
        "scan.readiness.metal_unavailable.title": "Graphics Rendering Unavailable",
        "scan.readiness.metal_unavailable.message": "The scan view requires Metal graphics support. Restart the app, or try again on a Metal-compatible device.",
        "scan.readiness.lidar_unavailable.title": "LiDAR Depth Unavailable",
        "scan.readiness.lidar_unavailable.message": "Scanning requires LiDAR scene depth to generate a valid point cloud. Use a LiDAR-equipped iPhone or iPad.",
        "scan.readiness.camera_denied.title": "Camera Access Off",
        "scan.readiness.camera_denied.message": "Scanning requires camera images and LiDAR depth frames. Allow camera access in Settings.",
        "scan.readiness.camera_restricted.title": "Camera Access Restricted",
        "scan.readiness.camera_restricted.message": "Camera access is restricted by the system, so scanning can't start.",
        "scan.readiness.open_settings": "Open Settings",
        "scan.readiness.back": "Back",
    ]

    private let chineseReadinessCopy = [
        "scan.readiness.checking.title": "正在检查设备能力",
        "scan.readiness.checking.message": "正在确认相机、ARKit 和深度扫描链路。",
        "scan.readiness.ar_unsupported.title": "当前设备不支持 AR 扫描",
        "scan.readiness.ar_unsupported.message": "FruitTreeScanner 需要 ARKit 才能采集点云。请使用支持 ARKit 的 iPhone 或 iPad。",
        "scan.readiness.metal_unavailable.title": "图形渲染不可用",
        "scan.readiness.metal_unavailable.message": "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。",
        "scan.readiness.lidar_unavailable.title": "当前设备没有 LiDAR 深度",
        "scan.readiness.lidar_unavailable.message": "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。",
        "scan.readiness.camera_denied.title": "相机权限未开启",
        "scan.readiness.camera_denied.message": "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。",
        "scan.readiness.camera_restricted.title": "相机权限受限",
        "scan.readiness.camera_restricted.message": "系统限制了相机访问，当前无法开始扫描。",
        "scan.readiness.open_settings": "打开设置",
        "scan.readiness.back": "返回",
    ]

    private let readinessMappings: [
        (state: ScanReadiness, titleKey: String, messageKey: String)
    ] = [
        (.checking, "scan.readiness.checking.title", "scan.readiness.checking.message"),
        (.arUnsupported, "scan.readiness.ar_unsupported.title", "scan.readiness.ar_unsupported.message"),
        (.metalUnavailable, "scan.readiness.metal_unavailable.title", "scan.readiness.metal_unavailable.message"),
        (.lidarUnavailable, "scan.readiness.lidar_unavailable.title", "scan.readiness.lidar_unavailable.message"),
        (.cameraDenied, "scan.readiness.camera_denied.title", "scan.readiness.camera_denied.message"),
        (.cameraRestricted, "scan.readiness.camera_restricted.title", "scan.readiness.camera_restricted.message"),
    ]

    func testEnglishScanReadinessCopyExistsInLocalizedResources() throws {
        let bundle = try localizedBundle(language: "en")
        assertReadinessCopy(in: bundle, matches: englishReadinessCopy)
    }

    func testChineseScanReadinessCopyExistsInLocalizedResources() throws {
        let bundle = try localizedBundle(language: "zh")
        assertReadinessCopy(in: bundle, matches: chineseReadinessCopy)
    }

    func testOnlyReadyDoesNotBlockScanning() {
        XCTAssertFalse(ScanReadiness.ready.blocksScanning)
        XCTAssertTrue(ScanReadiness.checking.blocksScanning)
        XCTAssertTrue(ScanReadiness.arUnsupported.blocksScanning)
        XCTAssertTrue(ScanReadiness.metalUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.lidarUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraDenied.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraRestricted.blocksScanning)
    }

    func testCameraDeniedTextStaysStable() throws {
        let bundle = try localizedBundle(language: "zh")
        XCTAssertEqual(ScanReadiness.cameraDenied.title(in: bundle), "相机权限未开启")
        XCTAssertEqual(
            ScanReadiness.cameraDenied.message(in: bundle),
            "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。"
        )
    }

    func testMetalUnavailableTextStaysStable() throws {
        let bundle = try localizedBundle(language: "zh")
        XCTAssertEqual(ScanReadiness.metalUnavailable.title(in: bundle), "图形渲染不可用")
        XCTAssertEqual(
            ScanReadiness.metalUnavailable.message(in: bundle),
            "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。"
        )
    }

    func testLidarUnavailableTextStaysStable() throws {
        let bundle = try localizedBundle(language: "zh")
        XCTAssertEqual(ScanReadiness.lidarUnavailable.title(in: bundle), "当前设备没有 LiDAR 深度")
        XCTAssertEqual(
            ScanReadiness.lidarUnavailable.message(in: bundle),
            "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。"
        )
    }

    func testReadyHasNoBlockingText() {
        XCTAssertEqual(ScanReadiness.ready.title, "")
        XCTAssertEqual(ScanReadiness.ready.message, "")
    }

    func testCameraAuthorizationMapsToRecoveryReadiness() async {
        var accessRequestCount = 0
        let unexpectedRequest: () async -> Bool = {
            accessRequestCount += 1
            return false
        }

        let authorized = await ScanReadiness.cameraReadiness(
            authorizationStatus: .authorized,
            requestAccess: unexpectedRequest
        )
        let denied = await ScanReadiness.cameraReadiness(
            authorizationStatus: .denied,
            requestAccess: unexpectedRequest
        )
        let restricted = await ScanReadiness.cameraReadiness(
            authorizationStatus: .restricted,
            requestAccess: unexpectedRequest
        )
        XCTAssertEqual(authorized, .ready)
        XCTAssertEqual(denied, .cameraDenied)
        XCTAssertEqual(restricted, .cameraRestricted)
        XCTAssertEqual(accessRequestCount, 0)

        let newlyGranted = await ScanReadiness.cameraReadiness(
            authorizationStatus: .notDetermined,
            requestAccess: { true }
        )
        let newlyDenied = await ScanReadiness.cameraReadiness(
            authorizationStatus: .notDetermined,
            requestAccess: { false }
        )
        XCTAssertEqual(newlyGranted, .ready)
        XCTAssertEqual(newlyDenied, .cameraDenied)
    }

    private func assertReadinessCopy(
        in bundle: Bundle,
        matches expectedCopy: [String: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for mapping in readinessMappings {
            XCTAssertEqual(
                mapping.state.title(in: bundle),
                expectedCopy[mapping.titleKey],
                "Incorrect readiness title mapping for \(mapping.titleKey)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                mapping.state.message(in: bundle),
                expectedCopy[mapping.messageKey],
                "Incorrect readiness message mapping for \(mapping.messageKey)",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            L10n.ScanReadiness.text(.openSettings, in: bundle),
            expectedCopy["scan.readiness.open_settings"],
            file: file,
            line: line
        )
        XCTAssertEqual(
            L10n.ScanReadiness.text(.back, in: bundle),
            expectedCopy["scan.readiness.back"],
            file: file,
            line: line
        )
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in app bundle"
        )
        return try XCTUnwrap(Bundle(url: url))
    }
}

final class ScanControlLocalizationTests: XCTestCase {
    func testScanControlCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "scan.control.guide": "Guide",
                "scan.control.measure": "Measure",
                "scan.control.cancel": "Cancel",
                "scan.control.finish": "Finish",
                "scan.control.start_recording": "Start Recording",
                "scan.control.stop_recording": "Stop Recording",
                "scan.control.record_again": "Record Again",
                "scan.control.processing": "Processing",
                "scan.cancel_confirmation.title": "Cancel This Scan?",
                "scan.cancel_confirmation.continue": "Continue Scanning",
                "scan.cancel_confirmation.discard": "Discard",
                "scan.cancel_confirmation.message": "The captured point cloud won't be saved. To keep this scan, tap Finish."
            ],
            "zh": [
                "scan.control.guide": "引导",
                "scan.control.measure": "测量",
                "scan.control.cancel": "取消",
                "scan.control.finish": "完成",
                "scan.control.start_recording": "开始录制",
                "scan.control.stop_recording": "停止录制",
                "scan.control.record_again": "重新录制",
                "scan.control.processing": "处理中",
                "scan.cancel_confirmation.title": "取消本次扫描？",
                "scan.cancel_confirmation.continue": "继续扫描",
                "scan.cancel_confirmation.discard": "放弃",
                "scan.cancel_confirmation.message": "已采集的点云不会保存。若要保留本次采集，请点击完成。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
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
}

final class ScanTransientFeedbackLocalizationTests: XCTestCase {
    private typealias GuidanceExpectation = (
        hint: ScanGuidanceHint,
        englishTitle: String,
        englishMessage: String,
        chineseTitle: String,
        chineseMessage: String
    )

    private let guidanceExpectations: [GuidanceExpectation] = [
        (
            .tooFast,
            "Moving Too Fast",
            "Slow down so canopy and main branches overlap",
            "移动太快",
            "放慢脚步，让树冠和主枝有足够重叠"
        ),
        (
            .tooClose,
            "Too Close",
            "Step back to keep the whole-tree outline",
            "距离太近",
            "后退一步，先保住整棵树轮廓"
        ),
        (
            .tooFar,
            "Too Far",
            "Move closer; prioritize the trunk and fruit-dense areas",
            "距离太远",
            "靠近果树，优先补主干和果实密集区"
        ),
        (
            .trackingLost,
            "Tracking Lost",
            "Aim at the trunk, ground, or textured branches to resume tracking",
            "追踪丢失",
            "对准树干、地面或纹理清晰的枝条恢复追踪"
        ),
        (
            .lowLight,
            "Low Light",
            "Dim light reduces fruit detection and texture quality",
            "光线不足",
            "光线偏暗，果实检测和纹理质量会下降"
        ),
        (
            .sparseDepth,
            "Sparse Canopy Depth",
            "Reduce sky in frame, move closer to the canopy, and slow down",
            "树冠深度稀疏",
            "减少天空占比，靠近树冠并放慢移动速度"
        ),
        (
            .goodPace,
            "Good Pace",
            "Keep this pace and circle the tree to cover rear blind spots",
            "速度良好",
            "保持速度，继续绕树补齐背面盲区"
        ),
    ]

    func testEnglishTransientFeedbackCopyAndAnnouncements() throws {
        let bundle = try localizedBundle(language: "en")

        for expectation in guidanceExpectations {
            assertGuidance(
                expectation,
                title: expectation.englishTitle,
                message: expectation.englishMessage,
                announcement: "\(expectation.englishTitle). \(expectation.englishMessage)",
                in: bundle
            )
        }

        XCTAssertEqual(L10n.Scan.coverageCompleteTitle(in: bundle), "Sufficient Scan Coverage")
        XCTAssertEqual(L10n.Scan.coverageCompleteMessage(in: bundle), "Tap Finish to save the result.")
        XCTAssertEqual(
            L10n.Scan.transientAnnouncement(
                title: L10n.Scan.coverageCompleteTitle(in: bundle),
                message: L10n.Scan.coverageCompleteMessage(in: bundle),
                in: bundle
            ),
            "Sufficient Scan Coverage. Tap Finish to save the result."
        )
    }

    func testChineseTransientFeedbackCopyAndAnnouncements() throws {
        let bundle = try localizedBundle(language: "zh")

        for expectation in guidanceExpectations {
            assertGuidance(
                expectation,
                title: expectation.chineseTitle,
                message: expectation.chineseMessage,
                announcement: "\(expectation.chineseTitle)。\(expectation.chineseMessage)",
                in: bundle
            )
        }

        XCTAssertEqual(L10n.Scan.coverageCompleteTitle(in: bundle), "扫描覆盖充足")
        XCTAssertEqual(L10n.Scan.coverageCompleteMessage(in: bundle), "可以点击完成保存结果")
        XCTAssertEqual(
            L10n.Scan.transientAnnouncement(
                title: L10n.Scan.coverageCompleteTitle(in: bundle),
                message: L10n.Scan.coverageCompleteMessage(in: bundle),
                in: bundle
            ),
            "扫描覆盖充足。可以点击完成保存结果"
        )
    }

    func testNoGuidanceHasNoVisibleOrAnnouncedCopy() throws {
        for language in ["en", "zh"] {
            let bundle = try localizedBundle(language: language)
            XCTAssertEqual(L10n.ScanGuidance.title(for: .none, in: bundle), "")
            XCTAssertEqual(L10n.ScanGuidance.message(for: .none, in: bundle), "")
            XCTAssertEqual(L10n.ScanGuidance.announcement(for: .none, in: bundle), "")
        }
    }

    @MainActor
    func testAnnouncementPostsOnlyForNonemptyCopyWhileVoiceOverIsRunning() {
        var postedMessages: [String] = []
        let poster: ScanTransientAccessibility.AnnouncementPoster = {
            postedMessages.append($0)
        }

        ScanTransientAccessibility.announce(
            "Tracking Lost",
            isVoiceOverRunning: false,
            poster: poster
        )
        ScanTransientAccessibility.announce(
            "",
            isVoiceOverRunning: true,
            poster: poster
        )
        ScanTransientAccessibility.announce(
            "Tracking Lost",
            isVoiceOverRunning: true,
            poster: poster
        )

        XCTAssertEqual(postedMessages, ["Tracking Lost"])
    }

    private func assertGuidance(
        _ expectation: GuidanceExpectation,
        title: String,
        message: String,
        announcement: String,
        in bundle: Bundle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            L10n.ScanGuidance.title(for: expectation.hint, in: bundle),
            title,
            file: file,
            line: line
        )
        XCTAssertEqual(
            L10n.ScanGuidance.message(for: expectation.hint, in: bundle),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            L10n.ScanGuidance.announcement(for: expectation.hint, in: bundle),
            announcement,
            file: file,
            line: line
        )
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in app bundle"
        )
        return try XCTUnwrap(Bundle(url: url))
    }
}

final class ScanPostCaptureLocalizationTests: XCTestCase {
    private let englishCopy: [L10n.ScanPostCapture.Key: String] = [
        .title: "Preview Ready",
        .guidanceComplete: "Coverage is sufficient. You can finish and estimate yield.",
        .guidanceGood: "You can finish now. If the back of the canopy is missing, resume and scan one more pass.",
        .guidanceContinue: "Resume scanning to capture the back of the canopy and occluded trunk areas.",
        .metricPointCloud: "Point Cloud",
        .metricDuration: "Duration",
        .metricStatus: "Status",
        .statusComplete: "Scan Complete",
        .statusGood: "Good Coverage",
        .statusContinue: "Continue Scanning",
        .statusInsufficient: "Insufficient Coverage",
        .coverage: "Coverage",
        .resumeAction: "Resume Scan",
        .finishAction: "Finish & Estimate",
        .resumeAccessibilityHint: "Resumes this scan and keeps the captured point cloud.",
        .finishAccessibilityHint: "Saves this scan and starts yield estimation.",
        .finishUnavailableAccessibilityHint: "Finishing is unavailable until the current scan is ready to export.",
    ]

    private let chineseCopy: [L10n.ScanPostCapture.Key: String] = [
        .title: "粗预览已就绪",
        .guidanceComplete: "覆盖充足，可直接完成并估算产量。",
        .guidanceGood: "可完成分析；若树冠背面缺失，继续录制补一圈。",
        .guidanceContinue: "建议继续录制，补齐树冠背面和主干遮挡区域。",
        .metricPointCloud: "点云",
        .metricDuration: "时长",
        .metricStatus: "状态",
        .statusComplete: "扫描完成",
        .statusGood: "覆盖良好",
        .statusContinue: "继续扫描",
        .statusInsufficient: "覆盖率不足",
        .coverage: "覆盖率",
        .resumeAction: "继续补扫",
        .finishAction: "完成估算",
        .resumeAccessibilityHint: "继续本次扫描并保留已采集的点云。",
        .finishAccessibilityHint: "保存本次扫描并开始估算产量。",
        .finishUnavailableAccessibilityHint: "当前扫描达到可导出条件后才能完成估算。",
    ]

    func testEnglishPostCaptureCopyExistsInLocalizedResources() throws {
        try assertCopy(in: localizedBundle(language: "en"), matches: englishCopy)
    }

    func testChinesePostCaptureCopyExistsInLocalizedResources() throws {
        try assertCopy(in: localizedBundle(language: "zh"), matches: chineseCopy)
    }

    func testCoverageStatusPreservesExistingThresholdBoundariesAndTitles() {
        let expectations: [
            (overall: Float, status: ScanCompletion.CoverageStatus, title: String)
        ] = [
            (0.85, .complete, "扫描完成"),
            (0.849, .good, "覆盖良好"),
            (0.6, .good, "覆盖良好"),
            (0.599, .continueScanning, "继续扫描"),
            (0.3, .continueScanning, "继续扫描"),
            (0.299, .insufficient, "覆盖率不足"),
        ]

        for expectation in expectations {
            let completion = ScanCompletion(overall: expectation.overall)
            XCTAssertEqual(completion.coverageStatus, expectation.status)
            XCTAssertEqual(completion.statusTitle, expectation.title)
        }
    }

    func testEnglishPresentationMapsEveryCoverageStatus() throws {
        let bundle = try localizedBundle(language: "en")
        let expectations: [
            (status: ScanCompletion.CoverageStatus, title: String, guidance: String)
        ] = [
            (.complete, "Scan Complete", "Coverage is sufficient. You can finish and estimate yield."),
            (.good, "Good Coverage", "You can finish now. If the back of the canopy is missing, resume and scan one more pass."),
            (.continueScanning, "Continue Scanning", "Resume scanning to capture the back of the canopy and occluded trunk areas."),
            (.insufficient, "Insufficient Coverage", "Resume scanning to capture the back of the canopy and occluded trunk areas."),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                L10n.ScanPostCapture.statusTitle(for: expectation.status, in: bundle),
                expectation.title
            )
            XCTAssertEqual(
                L10n.ScanPostCapture.guidance(for: expectation.status, in: bundle),
                expectation.guidance
            )
        }
    }

    func testFinishAccessibilityHintExplainsAvailability() throws {
        let englishBundle = try localizedBundle(language: "en")
        XCTAssertEqual(
            L10n.ScanPostCapture.finishAccessibilityHint(canFinish: true, in: englishBundle),
            "Saves this scan and starts yield estimation."
        )
        XCTAssertEqual(
            L10n.ScanPostCapture.finishAccessibilityHint(canFinish: false, in: englishBundle),
            "Finishing is unavailable until the current scan is ready to export."
        )
    }

    private func assertCopy(
        in bundle: Bundle,
        matches expectedCopy: [L10n.ScanPostCapture.Key: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(expectedCopy.count, L10n.ScanPostCapture.Key.allCases.count)
        for key in L10n.ScanPostCapture.Key.allCases {
            let expected = try XCTUnwrap(expectedCopy[key], file: file, line: line)
            XCTAssertEqual(
                bundle.localizedString(forKey: key.rawValue, value: nil, table: nil),
                expected,
                file: file,
                line: line
            )
            XCTAssertEqual(
                L10n.ScanPostCapture.text(key, in: bundle),
                expected,
                file: file,
                line: line
            )
        }
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in app bundle"
        )
        return try XCTUnwrap(Bundle(url: url))
    }
}

final class CoverageMapLocalizationTests: XCTestCase {
    private let englishCopy: [L10n.ScanCoverage.Key: String] = [
        .coverage: "Scan coverage",
        .coverageAccessibilityValueFormat: "%1$d%%, duration %2$@",
        .scoreAccessibilityValueFormat: "%d%%",
        .statusComplete: "Scan Complete",
        .statusGood: "Good Coverage",
        .statusContinue: "Continue Scanning",
        .statusInsufficient: "Insufficient Coverage",
        .hintOppositeSide: "Scan the other side of the canopy",
        .hintBackSide: "Scan the back of the canopy",
        .hintVerticalCoverage: "Slow down and scan the upper and lower canopy",
        .hintAngleUniformity: "Scan the sparsely covered angles",
        .hintCollecting: "Start at the trunk and circle the tree slowly",
        .hintIncreasing: "Discovering new canopy areas",
        .hintDecreasing: "Scan the back of the canopy, then save",
        .hintStable: "Coverage is complete. You can save and analyze.",
        .spatialSampleOne: "%d spatial sample",
        .spatialSampleOther: "%d spatial samples",
        .metricDuration: "Duration",
        .metricCanopy: "Canopy",
        .metricAngle: "Angles",
        .metricUniformity: "Balance",
        .metricStability: "Stability",
    ]

    private let chineseCopy: [L10n.ScanCoverage.Key: String] = [
        .coverage: "扫描覆盖率",
        .coverageAccessibilityValueFormat: "%1$d%%，时长 %2$@",
        .scoreAccessibilityValueFormat: "%d%%",
        .statusComplete: "扫描完成",
        .statusGood: "覆盖良好",
        .statusContinue: "继续扫描",
        .statusInsufficient: "覆盖率不足",
        .hintOppositeSide: "补扫树冠另一侧",
        .hintBackSide: "补扫树冠背面",
        .hintVerticalCoverage: "放慢补扫树冠上下层",
        .hintAngleUniformity: "补扫稀疏视角",
        .hintCollecting: "从主干开始慢速环绕",
        .hintIncreasing: "正在发现树冠新区域",
        .hintDecreasing: "补树冠背面后可保存",
        .hintStable: "覆盖完整，可保存分析",
        .spatialSampleOne: "%d 个空间采样",
        .spatialSampleOther: "%d 个空间采样",
        .metricDuration: "时长",
        .metricCanopy: "树冠",
        .metricAngle: "视角",
        .metricUniformity: "均衡",
        .metricStability: "稳定",
    ]

    func testEnglishCoverageMapCopyExistsInLocalizedResources() throws {
        try assertCopy(in: localizedBundle(language: "en"), matches: englishCopy)
    }

    func testChineseCoverageMapCopyExistsInLocalizedResources() throws {
        try assertCopy(in: localizedBundle(language: "zh"), matches: chineseCopy)
    }

    func testCoverageStatusPreservesExistingThresholdBoundariesAndTitles() {
        let expectations: [
            (overall: Float, status: ScanCompletion.CoverageStatus, title: String)
        ] = [
            (0.85, .complete, "扫描完成"),
            (0.849, .good, "覆盖良好"),
            (0.6, .good, "覆盖良好"),
            (0.599, .continueScanning, "继续扫描"),
            (0.3, .continueScanning, "继续扫描"),
            (0.299, .insufficient, "覆盖率不足"),
        ]

        for expectation in expectations {
            let completion = ScanCompletion(overall: expectation.overall)
            XCTAssertEqual(completion.coverageStatus, expectation.status)
            XCTAssertEqual(completion.statusTitle, expectation.title)
        }
    }

    func testCoverageHintPreservesExistingPrecedenceAndChineseCopy() {
        let expectations: [
            (completion: ScanCompletion, hint: ScanCompletion.CoverageHint, text: String)
        ] = [
            (
                ScanCompletion(angleCoverageScore: 0.2, voxelCount: 80),
                .oppositeSide,
                "补扫树冠另一侧"
            ),
            (
                ScanCompletion(
                    angleCoverageScore: 0.5,
                    angleUniformityScore: 0.8,
                    oppositeSideScore: 0.2,
                    verticalCoverageScore: 0.8,
                    voxelCount: 120
                ),
                .backSide,
                "补扫树冠背面"
            ),
            (
                ScanCompletion(
                    angleCoverageScore: 0.6,
                    angleUniformityScore: 0.8,
                    oppositeSideScore: 0.8,
                    verticalCoverageScore: 0.2,
                    voxelCount: 140
                ),
                .verticalCoverage,
                "放慢补扫树冠上下层"
            ),
            (
                ScanCompletion(
                    angleCoverageScore: 0.55,
                    angleUniformityScore: 0.3,
                    oppositeSideScore: 0.8,
                    verticalCoverageScore: 0.8,
                    voxelCount: 120
                ),
                .angleUniformity,
                "补扫稀疏视角"
            ),
            (ScanCompletion(discoveryTrend: .collecting), .collecting, "从主干开始慢速环绕"),
            (ScanCompletion(discoveryTrend: .increasing), .increasing, "正在发现树冠新区域"),
            (ScanCompletion(discoveryTrend: .decreasing), .decreasing, "补树冠背面后可保存"),
            (ScanCompletion(discoveryTrend: .stable), .stable, "覆盖完整，可保存分析"),
        ]

        for expectation in expectations {
            XCTAssertEqual(expectation.completion.coverageHint, expectation.hint)
            XCTAssertEqual(expectation.completion.statusHint, expectation.text)
        }
    }

    func testEnglishPresentationMapsEveryStatusAndHint() throws {
        let bundle = try localizedBundle(language: "en")
        let statuses: [(ScanCompletion.CoverageStatus, String)] = [
            (.complete, "Scan Complete"),
            (.good, "Good Coverage"),
            (.continueScanning, "Continue Scanning"),
            (.insufficient, "Insufficient Coverage"),
        ]
        let hints: [(ScanCompletion.CoverageHint, String)] = [
            (.oppositeSide, "Scan the other side of the canopy"),
            (.backSide, "Scan the back of the canopy"),
            (.verticalCoverage, "Slow down and scan the upper and lower canopy"),
            (.angleUniformity, "Scan the sparsely covered angles"),
            (.collecting, "Start at the trunk and circle the tree slowly"),
            (.increasing, "Discovering new canopy areas"),
            (.decreasing, "Scan the back of the canopy, then save"),
            (.stable, "Coverage is complete. You can save and analyze."),
        ]

        for (status, expected) in statuses {
            XCTAssertEqual(L10n.ScanCoverage.statusTitle(for: status, in: bundle), expected)
        }
        for (hint, expected) in hints {
            XCTAssertEqual(L10n.ScanCoverage.statusHint(for: hint, in: bundle), expected)
        }
    }

    func testLocalizedCountsAndAccessibilityValues() throws {
        let englishBundle = try localizedBundle(language: "en")
        XCTAssertEqual(L10n.ScanCoverage.spatialSamples(1, in: englishBundle), "1 spatial sample")
        XCTAssertEqual(L10n.ScanCoverage.spatialSamples(2, in: englishBundle), "2 spatial samples")
        XCTAssertEqual(
            L10n.ScanCoverage.coverageAccessibilityValue(
                percent: 85,
                duration: "1:05",
                in: englishBundle
            ),
            "85%, duration 1:05"
        )
        XCTAssertEqual(L10n.ScanCoverage.scoreAccessibilityValue(-0.2, in: englishBundle), "0%")
        XCTAssertEqual(L10n.ScanCoverage.scoreAccessibilityValue(0.496, in: englishBundle), "50%")
        XCTAssertEqual(L10n.ScanCoverage.scoreAccessibilityValue(1.2, in: englishBundle), "100%")
    }

    private func assertCopy(
        in bundle: Bundle,
        matches expectedCopy: [L10n.ScanCoverage.Key: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(expectedCopy.count, L10n.ScanCoverage.Key.allCases.count)
        for key in L10n.ScanCoverage.Key.allCases {
            let expected = try XCTUnwrap(expectedCopy[key], file: file, line: line)
            XCTAssertEqual(
                bundle.localizedString(forKey: key.rawValue, value: nil, table: nil),
                expected,
                file: file,
                line: line
            )
            XCTAssertEqual(
                L10n.ScanCoverage.text(key, in: bundle),
                expected,
                file: file,
                line: line
            )
        }
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in app bundle"
        )
        return try XCTUnwrap(Bundle(url: url))
    }
}

final class ScanLifecycleControllerTests: XCTestCase {
    func testRecordingToInactiveStopsReliableEvidenceAndDoesNotAutoResume() {
        let controller = ScanLifecycleController()
        let recording = controller.startNewScan()
        XCTAssertTrue(recording.acceptsReliableEvidence)
        let interrupted = controller.interrupt(.appInactive)
        XCTAssertEqual(interrupted.state, .systemInterrupted(.appInactive))
        XCTAssertFalse(interrupted.acceptsReliableEvidence)
        XCTAssertGreaterThan(interrupted.generation, recording.generation)
        XCTAssertEqual(controller.interruptionEnded().state, .recovering)
    }

    func testInactiveThenBackgroundDoesNotDuplicateInterruption() {
        let controller = ScanLifecycleController()
        _ = controller.startNewScan()
        let first = controller.interrupt(.appInactive)
        let second = controller.interrupt(.appBackgrounded)
        XCTAssertEqual(second.state, .systemInterrupted(.appInactive))
        XCTAssertEqual(second.interruptionCount, 1)
        XCTAssertEqual(second.generation, first.generation)
    }

    func testUserPauseAndSystemInterruptionHaveDifferentRecoveryPolicies() {
        let controller = ScanLifecycleController()
        _ = controller.startNewScan()
        XCTAssertEqual(controller.userPaused().state, .userPaused)
        XCTAssertEqual(controller.resumeUserPaused().state, .recording)
        _ = controller.interrupt(.arSessionInterrupted)
        XCTAssertEqual(controller.resumeUserPaused().state, .systemInterrupted(.arSessionInterrupted))
        XCTAssertEqual(controller.interruptionEnded().state, .recovering)
    }

    func testRestartCreatesNewIdentityAndClearsInterruptionDiagnostics() {
        let controller = ScanLifecycleController()
        let first = controller.startNewScan()
        _ = controller.interrupt(.appBackgrounded)
        let restarted = controller.startNewScan()
        XCTAssertNotEqual(restarted.scanIdentity, first.scanIdentity)
        XCTAssertEqual(restarted.state, .recording)
        XCTAssertEqual(restarted.interruptionCount, 0)
        XCTAssertNil(restarted.lastInterruptionTimestamp)
    }

    func testLateEventsCannotReplaceCompletedOrCancelledState() {
        let controller = ScanLifecycleController()
        _ = controller.startNewScan()
        _ = controller.beginFinishing()
        XCTAssertEqual(controller.complete().state, .completed)
        XCTAssertEqual(controller.interrupt(.arSessionInterrupted).state, .completed)
        let second = ScanLifecycleController()
        _ = second.startNewScan()
        XCTAssertEqual(second.cancel().state, .cancelled)
        XCTAssertEqual(second.fail(.sessionFailed("camera")).state, .cancelled)
    }
}

@MainActor
final class ScanCoordinatorSessionRestartTests: XCTestCase {
    func testCameraUnauthorizedFailureRequiresCameraReadinessRecovery() {
        let coordinator = ScanCoordinator()
        _ = coordinator.scanLifecycle.startNewScan()
        let error = NSError(
            domain: ARErrorDomain,
            code: ARError.Code.cameraUnauthorized.rawValue
        )

        coordinator.handleSessionFailure(error)

        guard case .failed(.cameraUnavailable(let message)) =
                coordinator.lifecycleSnapshot().state else {
            return XCTFail("Camera authorization failure must use readiness recovery")
        }
        XCTAssertEqual(message, error.localizedDescription)
        XCTAssertTrue(
            ScanFailureReason.cameraUnavailable("camera").requiresCameraReadinessRecovery
        )
        XCTAssertFalse(
            ScanFailureReason.sessionFailed("camera").requiresCameraReadinessRecovery
        )
    }

    func testSensorUnavailableFailureRemainsGenericSessionFailure() {
        let coordinator = ScanCoordinator()
        _ = coordinator.scanLifecycle.startNewScan()

        coordinator.handleSessionFailure(
            NSError(
                domain: ARErrorDomain,
                code: ARError.Code.sensorUnavailable.rawValue
            )
        )

        guard case .failed(.sessionFailed) = coordinator.lifecycleSnapshot().state else {
            return XCTFail("Sensor failures must retain generic restart recovery")
        }
    }

    func testMatchingErrorCodeOutsideARKitDomainRemainsGenericSessionFailure() {
        let coordinator = ScanCoordinator()
        _ = coordinator.scanLifecycle.startNewScan()

        coordinator.handleSessionFailure(
            NSError(
                domain: "FruitTreeScannerTests",
                code: ARError.Code.cameraUnauthorized.rawValue
            )
        )

        guard case .failed(.sessionFailed) = coordinator.lifecycleSnapshot().state else {
            return XCTFail("Only ARKit camera authorization failures use permission recovery")
        }
    }

    func testRestartInstallsSessionDelegateBeforeRunningReplacementSession() {
        let recorder = ScanSessionRuntimeRecorder()
        let session = ARSession()
        var coordinator: ScanCoordinator!
        recorder.beforeRun = {
            XCTAssertIdentical(session.delegate as AnyObject?, coordinator)
        }
        coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = session
        _ = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSessionFailure(ScanSessionTestError.camera)

        XCTAssertNil(session.delegate)
        XCTAssertTrue(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertIdentical(session.delegate as AnyObject?, coordinator)
    }

    func testFailureRestartWaitsForNormalTrackingBeforeOpeningReliableEvidence() async {
        let recorder = ScanSessionRuntimeRecorder()
        var coordinator: ScanCoordinator!
        recorder.beforeRun = {
            XCTAssertFalse(coordinator.acceptsReliableEvidence())
            if case .failed = coordinator.lifecycleSnapshot().state {
                // Expected: session reset happens while the failed generation is still closed.
            } else {
                XCTFail("Expected failed lifecycle state while restarting ARSession")
            }
        }
        coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = ARSession()

        let original = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSessionFailure(ScanSessionTestError.camera)

        XCTAssertTrue(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(recorder.runOptions.count, 1)
        XCTAssertTrue(recorder.runOptions[0].contains(.resetTracking))
        XCTAssertTrue(recorder.runOptions[0].contains(.removeExistingAnchors))
        XCTAssertFalse(coordinator.acceptsReliableEvidence())

        let restarted = coordinator.lifecycleSnapshot()
        XCTAssertEqual(restarted.state, .recording)
        XCTAssertNotEqual(restarted.scanIdentity, original.scanIdentity)
        XCTAssertEqual(restarted.interruptionCount, 0)
        XCTAssertTrue(
            coordinator.isCaptureSuspendedForCameraTracking(
                scanIdentity: restarted.scanIdentity
            )
        )

        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.isCaptureSuspendedForCameraTracking())
    }

    func testRestartWithoutBoundSessionFailsClosed() {
        let recorder = ScanSessionRuntimeRecorder()
        let coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        _ = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSystemInterruption(.appInactive)
        coordinator.handleSessionInterruptionEnded()

        XCTAssertFalse(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(recorder.runOptions.count, 0)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        if case .failed = coordinator.lifecycleSnapshot().state {
            // Expected: a missing bound ARSession remains a recoverable UI failure.
        } else {
            XCTFail("Expected restart without ARSession to remain fail-closed")
        }
    }

    func testUserPausedResumeDoesNotResetARSession() {
        let recorder = ScanSessionRuntimeRecorder()
        let coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = ARSession()

        coordinator.startRecording(selectedCategory: .apple)
        coordinator.stopRecording()

        XCTAssertFalse(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .userPaused)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertEqual(recorder.runOptions.count, 0)

        coordinator.resumeRecordingPreservingCapture()
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertEqual(recorder.runOptions.count, 0)
    }

    func testRepeatedRestartDoesNotResetActiveReplacementScan() async {
        let recorder = ScanSessionRuntimeRecorder()
        let coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = ARSession()
        _ = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSystemInterruption(.appBackgrounded)
        coordinator.handleSessionInterruptionEnded()

        XCTAssertTrue(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertFalse(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(recorder.runOptions.count, 1)
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(coordinator.isCaptureSuspendedForCameraTracking())

        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertTrue(coordinator.acceptsReliableEvidence())
    }

    func testUnsupportedRestartFailsClosedWithoutCallingSessionRun() {
        let recorder = ScanSessionRuntimeRecorder(isSupported: false)
        let coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = ARSession()
        _ = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSessionFailure(ScanSessionTestError.camera)

        XCTAssertFalse(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(recorder.runOptions.count, 0)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        if case .failed = coordinator.lifecycleSnapshot().state {
            // Expected.
        } else {
            XCTFail("Expected unsupported AR restart to remain failed")
        }
    }

    func testRestartAfterTeardownFailsClosedWithoutCallingSessionRun() {
        let recorder = ScanSessionRuntimeRecorder()
        let coordinator = ScanCoordinator(sessionRuntime: recorder.runtime)
        coordinator.session = ARSession()
        _ = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        coordinator.handleSessionFailure(ScanSessionTestError.camera)
        coordinator.teardown()

        XCTAssertFalse(coordinator.restartInterruptedScan(selectedCategory: .apple))
        XCTAssertEqual(recorder.runOptions.count, 0)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        if case .failed = coordinator.lifecycleSnapshot().state {
            // Expected: teardown preserves the failure while permanently closing evidence.
        } else {
            XCTFail("Expected teardown restart to preserve failed lifecycle state")
        }
    }
}

@MainActor
final class ScanCoordinatorCameraTrackingTests: XCTestCase {
    func testOnlyNormalCameraTrackingAcceptsReliableCapture() {
        let expectations: [(ARCamera.TrackingState, ScanGuidanceHint)] = [
            (.notAvailable, .trackingLost),
            (.limited(.initializing), .trackingLost),
            (.limited(.excessiveMotion), .tooFast),
            (.limited(.insufficientFeatures), .trackingLost),
            (.limited(.relocalizing), .trackingLost),
        ]

        for (trackingState, expectedHint) in expectations {
            let status = ScanCameraTrackingStatus.make(from: trackingState)
            XCTAssertFalse(status.acceptsReliableCapture)
            XCTAssertEqual(status.guidanceHint, expectedHint)
        }

        let normal = ScanCameraTrackingStatus.make(from: .normal)
        XCTAssertTrue(normal.acceptsReliableCapture)
        XCTAssertEqual(normal.guidanceHint, .none)
        XCTAssertEqual(
            ScanGuidanceHelper.trackingHint(
                for: .limited(.insufficientFeatures),
                lightIntensity: 80
            ),
            .lowLight
        )
    }

    func testLimitedTrackingSuspendsEvidenceAndNormalResumesSameScan() async throws {
        let coordinator = ScanCoordinator()
        let hudState = ScanHUDState()
        coordinator.hudState = hudState
        coordinator.startRecording(selectedCategory: .apple)
        let recording = coordinator.lifecycleSnapshot()
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.handleCameraTrackingState(.limited(.excessiveMotion))

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, recording.scanIdentity)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(coordinator.acceptsCapturedEvidence(token))
        XCTAssertNil(coordinator.capturedEvidenceToken())
        XCTAssertTrue(
            coordinator.isCaptureSuspendedForCameraTracking(
                scanIdentity: recording.scanIdentity
            )
        )
        await Task.yield()
        XCTAssertEqual(hudState.guidanceHint, .tooFast)

        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, recording.scanIdentity)
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.isCaptureSuspendedForCameraTracking())
        XCTAssertEqual(hudState.guidanceHint, .none)
    }

    func testNewScanWaitsForNormalTrackingAfterSessionRun() async {
        let coordinator = ScanCoordinator()
        coordinator.resetCameraTrackingForSessionRun()

        coordinator.startRecording(selectedCategory: .apple)
        let waiting = coordinator.lifecycleSnapshot()

        XCTAssertEqual(waiting.state, .recording)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(
            coordinator.isCaptureSuspendedForCameraTracking(
                scanIdentity: waiting.scanIdentity
            )
        )

        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.isCaptureSuspendedForCameraTracking())
    }

    func testUserPauseDuringTrackingLossPreventsAutomaticResume() async {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        coordinator.handleCameraTrackingState(.limited(.insufficientFeatures))

        coordinator.stopRecording()
        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .userPaused)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.isCaptureSuspendedForCameraTracking())
    }

    func testUserResumeWaitsWhileTrackingRemainsLimited() async {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let originalIdentity = coordinator.lifecycleSnapshot().scanIdentity
        coordinator.stopRecording()
        coordinator.handleCameraTrackingState(.limited(.initializing))

        coordinator.resumeRecordingPreservingCapture()

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, originalIdentity)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(coordinator.isCaptureSuspendedForCameraTracking())

        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()

        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, originalIdentity)
    }

    func testRepeatedLimitedStateDoesNotInvalidateEvidenceTwice() {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)

        coordinator.handleCameraTrackingState(.limited(.excessiveMotion))
        let firstInvalidation = coordinator.evidenceGenerationSnapshot()
        coordinator.handleCameraTrackingState(.limited(.excessiveMotion))

        XCTAssertEqual(coordinator.evidenceGenerationSnapshot(), firstInvalidation)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
    }

    func testStaleNormalRecoveryCannotReopenAfterNewLimitedState() async {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        coordinator.handleCameraTrackingState(.limited(.excessiveMotion))
        coordinator.handleCameraTrackingState(.normal)
        coordinator.handleCameraTrackingState(.limited(.insufficientFeatures))

        await Task.yield()

        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(coordinator.isCaptureSuspendedForCameraTracking())
        XCTAssertEqual(
            coordinator.cameraTrackingStatusSnapshot().guidanceHint,
            .trackingLost
        )
    }

    func testHardSessionInterruptionStillPreventsTrackingAutoResume() async {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        coordinator.handleCameraTrackingState(.limited(.insufficientFeatures))
        coordinator.handleCameraTrackingState(.normal)
        coordinator.handleSystemInterruption(.arSessionInterrupted)
        await Task.yield()

        XCTAssertEqual(
            coordinator.lifecycleSnapshot().state,
            .systemInterrupted(.arSessionInterrupted)
        )
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.isCaptureSuspendedForCameraTracking())
    }
}

private final class ScanSessionRuntimeRecorder {
    var runOptions: [ARSession.RunOptions] = []
    var beforeRun: (() -> Void)?
    private let isSupported: Bool

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    lazy var runtime = ScanSessionRuntime(
        isWorldTrackingSupported: { [isSupported] in isSupported },
        run: { [weak self] _, _, options in
            self?.beforeRun?()
            self?.runOptions.append(options)
        }
    )
}

private enum ScanSessionTestError: LocalizedError {
    case camera

    var errorDescription: String? {
        "Camera session failed"
    }
}

@MainActor
final class ScanCapturedEvidenceConcurrencyTests: XCTestCase {
    func testFinishingFlushCommitsInFlightCapturedEvidence() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())
        let gate = ScanCapturedEvidenceTestGate()
        let detection = makeDetection(timestamp: 1)
        XCTAssertTrue(coordinator.beginDetectionProcessing())
        let inFlightTask = Task {
            await gate.wait()
            defer { coordinator.finishDetectionProcessing() }
            await coordinator.appendDetectedFruits(
                [detection],
                evidenceToken: token
            )
        }
        coordinator.detectionTask = inFlightTask

        coordinator.stopRecording()
        XCTAssertTrue(coordinator.beginFinishingScan())
        await gate.open()
        await coordinator.flushPendingDetections()

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .finishing)
        XCTAssertEqual(coordinator.detectedFruits.count, 1)
    }

    func testCapturedEvidenceCanCommitDuringUserPause() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.stopRecording()
        await coordinator.appendDetectedFruits(
            [makeDetection(timestamp: 2)],
            evidenceToken: token
        )

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .userPaused)
        XCTAssertEqual(coordinator.detectedFruits.count, 1)
    }

    func testCapturedEvidenceCanCommitAfterRapidPauseResumeOfSameScan() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.stopRecording()
        coordinator.resumeRecordingPreservingCapture()
        await coordinator.appendDetectedFruits(
            [makeDetection(timestamp: 3)],
            evidenceToken: token
        )

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertEqual(coordinator.detectedFruits.count, 1)
    }

    func testHardInvalidationRejectsCapturedEvidenceBeforeLifecycleCallback() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())
        coordinator.stopRecording()

        coordinator.invalidateReliableEvidenceImmediately()
        await coordinator.appendDetectedFruits(
            [makeDetection(timestamp: 4)],
            evidenceToken: token
        )

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .userPaused)
        XCTAssertTrue(coordinator.detectedFruits.isEmpty)
    }

    func testReplacementScanRejectsCapturedEvidenceFromPreviousIdentity() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.startRecording(selectedCategory: .apple)
        await coordinator.appendDetectedFruits(
            [makeDetection(timestamp: 5)],
            evidenceToken: token
        )

        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertTrue(coordinator.detectedFruits.isEmpty)
    }

    func testTeardownRejectsCapturedEvidence() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.teardown()
        await coordinator.appendDetectedFruits(
            [makeDetection(timestamp: 6)],
            evidenceToken: token
        )

        XCTAssertTrue(coordinator.detectedFruits.isEmpty)
    }

    private func makeDetection(timestamp: TimeInterval) -> DetectedFruit {
        DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            confidence: 0.95,
            timestamp: timestamp
        )
    }
}

private actor ScanCapturedEvidenceTestGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

final class ScanCompletionEvaluatorTests: XCTestCase {
    func testAngleCoverageContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let narrow = evaluator.evaluate(.init(
            voxelCount: 500,
            scanDuration: 60,
            angleCoverage: 0.18,
            discoveryTrend: .stable,
            discoveryRate: 8
        ))
        let broad = evaluator.evaluate(.init(
            voxelCount: 500,
            scanDuration: 60,
            angleCoverage: 0.82,
            discoveryTrend: .stable,
            discoveryRate: 8
        ))

        XCTAssertLessThan(narrow.angleCoverageScore, broad.angleCoverageScore)
        XCTAssertLessThan(narrow.overall, broad.overall)
    }

    func testCompletionHintRequestsOppositeSideWhenAngleCoverageIsLow() {
        let completion = ScanCompletion(
            overall: 0.55,
            timeScore: 0.7,
            voxelScore: 0.8,
            angleCoverageScore: 0.2,
            angleUniformityScore: 0.9,
            stabilityScore: 0.8,
            voxelCount: 120,
            scanDuration: 35,
            discoveryTrend: .stable
        )

        XCTAssertEqual(completion.statusHint, "补扫树冠另一侧")
    }

    func testAngleUniformityContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let skewed = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.9,
            angleUniformity: 0.35,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let balanced = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.9,
            angleUniformity: 0.95,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(skewed.angleUniformityScore, balanced.angleUniformityScore)
        XCTAssertLessThan(skewed.overall, balanced.overall)
        XCTAssertEqual(skewed.statusHint, "补扫稀疏视角")
    }

    func testOppositeSideCoverageContributesGentlyToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let oneSided = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.70,
            angleUniformity: 0.82,
            oppositeSideCoverage: 0.12,
            verticalCoverage: 0.86,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let pairedSides = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.70,
            angleUniformity: 0.82,
            oppositeSideCoverage: 0.92,
            verticalCoverage: 0.86,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(oneSided.oppositeSideScore, pairedSides.oppositeSideScore)
        XCTAssertLessThan(oneSided.overall, pairedSides.overall)
        XCTAssertGreaterThan(oneSided.overall, 0.65, "对侧覆盖不足应提示补扫，但不应让受限果园行扫描直接失败")
    }

    func testCompletionHintRequestsBackSideWhenCoverageIsMostlyOneSided() {
        let evaluator = ScanCompletionEvaluator()
        let oneSided = evaluator.evaluate(.init(
            voxelCount: 360,
            scanDuration: 55,
            angleCoverage: 0.62,
            angleUniformity: 0.78,
            oppositeSideCoverage: 0.08,
            verticalCoverage: 0.82,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertEqual(oneSided.statusHint, "补扫树冠背面")
    }

    func testVerticalCoverageGentlyContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let middleOnly = evaluator.evaluate(.init(
            voxelCount: 700,
            scanDuration: 80,
            angleCoverage: 0.86,
            angleUniformity: 0.86,
            verticalCoverage: 0.25,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let fullHeight = evaluator.evaluate(.init(
            voxelCount: 700,
            scanDuration: 80,
            angleCoverage: 0.86,
            angleUniformity: 0.86,
            verticalCoverage: 0.95,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(middleOnly.verticalCoverageScore, fullHeight.verticalCoverageScore)
        XCTAssertLessThan(middleOnly.overall, fullHeight.overall)
        XCTAssertGreaterThan(middleOnly.overall, 0.65, "垂直覆盖不足应提示补扫，但不应把现场可用扫描直接打成失败")
    }

    func testCompletionHintRequestsVerticalCoverageOnlyAfterHorizontalCoverageIsUseful() {
        let completion = ScanCompletion(
            overall: 0.72,
            timeScore: 0.9,
            voxelScore: 0.9,
            angleCoverageScore: 0.70,
            angleUniformityScore: 0.85,
            verticalCoverageScore: 0.32,
            stabilityScore: 0.8,
            voxelCount: 180,
            scanDuration: 65,
            discoveryTrend: .stable
        )

        XCTAssertEqual(completion.statusHint, "放慢补扫树冠上下层")
    }
}

final class ScanSessionConfigurationTests: XCTestCase {
    func testPreferredDepthSemanticsPrefersSmoothedDepthWhenAvailable() {
        let semantics = ScanSessionConfiguration.preferredDepthSemantics { requested in
            requested == .sceneDepth || requested == .smoothedSceneDepth
        }

        XCTAssertEqual(semantics, .smoothedSceneDepth)
    }

    func testPreferredDepthSemanticsFallsBackToSceneDepth() {
        let semantics = ScanSessionConfiguration.preferredDepthSemantics { requested in
            requested == .sceneDepth
        }

        XCTAssertEqual(semantics, .sceneDepth)
    }

    func testPreferredDepthSemanticsReturnsNilWithoutDepthSupport() {
        let semantics = ScanSessionConfiguration.preferredDepthSemantics { _ in false }

        XCTAssertNil(semantics)
    }
}

final class ScanCompletionPresentationTests: XCTestCase {
    private let expectedCopy: [String: [String: String]] = [
        "en": [
            "scan.completion.status.complete": "Scan Complete",
            "scan.completion.status.coverage_good": "Good Coverage",
            "scan.completion.status.continue_scanning": "Keep Scanning",
            "scan.completion.status.insufficient": "Coverage Low",
            "scan.completion.hint.other_side": "Scan the other side of the canopy",
            "scan.completion.hint.back_side": "Scan the back of the canopy",
            "scan.completion.hint.vertical": "Move slowly across the upper and lower canopy",
            "scan.completion.hint.sparse_angles": "Fill sparse viewing angles",
            "scan.completion.hint.trunk": "Start at the trunk and circle slowly",
            "scan.completion.hint.discovering": "Discovering new canopy areas",
            "scan.completion.hint.finish_back": "Scan the canopy back, then save",
            "scan.completion.hint.stable": "Coverage complete; ready to analyze",
            "scan.completion.spatial_samples_format": "%d spatial samples",
            "scan.completion.metric.duration": "Duration",
            "scan.completion.metric.canopy": "Canopy",
            "scan.completion.metric.angles": "Angles",
            "scan.completion.metric.balance": "Balance",
            "scan.completion.metric.stability": "Stability",
            "scan.completion.metric.point_cloud": "Point Cloud",
            "scan.completion.metric.status": "Status",
            "scan.completion.preview_ready": "Rough Preview Ready",
            "scan.completion.next.high": "Coverage is sufficient. Finish now to estimate yield.",
            "scan.completion.next.medium": "You can finish; if the canopy back is missing, record one more pass.",
            "scan.completion.next.low": "Continue recording to cover the canopy back and occluded trunk areas.",
            "scan.completion.resume": "Continue Scan",
            "scan.completion.finish_estimate": "Finish Estimate",
            "scan.completion.toast.title": "Coverage Sufficient",
            "scan.completion.toast.message": "Tap Finish to save the result",
            "scan.controls.guide": "Guide",
            "scan.controls.measure": "Measure",
            "scan.controls.cancel": "Cancel",
            "scan.controls.start_recording": "Start Recording",
            "scan.controls.stop_recording": "Stop Recording",
            "scan.controls.rerecord": "Record Again",
            "scan.controls.finish": "Finish",
            "scan.controls.processing": "Processing",
        ],
        "zh": [
            "scan.completion.status.complete": "扫描完成",
            "scan.completion.status.coverage_good": "覆盖良好",
            "scan.completion.status.continue_scanning": "继续扫描",
            "scan.completion.status.insufficient": "覆盖率不足",
            "scan.completion.hint.other_side": "补扫树冠另一侧",
            "scan.completion.hint.back_side": "补扫树冠背面",
            "scan.completion.hint.vertical": "放慢补扫树冠上下层",
            "scan.completion.hint.sparse_angles": "补扫稀疏视角",
            "scan.completion.hint.trunk": "从主干开始慢速环绕",
            "scan.completion.hint.discovering": "正在发现树冠新区域",
            "scan.completion.hint.finish_back": "补树冠背面后可保存",
            "scan.completion.hint.stable": "覆盖完整，可保存分析",
            "scan.completion.spatial_samples_format": "%d 个空间采样",
            "scan.completion.metric.duration": "时长",
            "scan.completion.metric.canopy": "树冠",
            "scan.completion.metric.angles": "视角",
            "scan.completion.metric.balance": "均衡",
            "scan.completion.metric.stability": "稳定",
            "scan.completion.metric.point_cloud": "点云",
            "scan.completion.metric.status": "状态",
            "scan.completion.preview_ready": "粗预览已就绪",
            "scan.completion.next.high": "覆盖充足，可直接完成并估算产量。",
            "scan.completion.next.medium": "可完成分析；若树冠背面缺失，继续录制补一圈。",
            "scan.completion.next.low": "建议继续录制，补齐树冠背面和主干遮挡区域。",
            "scan.completion.resume": "继续补扫",
            "scan.completion.finish_estimate": "完成估算",
            "scan.completion.toast.title": "扫描覆盖充足",
            "scan.completion.toast.message": "可以点击完成保存结果",
            "scan.controls.guide": "引导",
            "scan.controls.measure": "测量",
            "scan.controls.cancel": "取消",
            "scan.controls.start_recording": "开始录制",
            "scan.controls.stop_recording": "停止录制",
            "scan.controls.rerecord": "重新录制",
            "scan.controls.finish": "完成",
            "scan.controls.processing": "处理中",
        ],
    ]

    func testCompletionAndControlCopyExistsInEnglishAndChinese() throws {
        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
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

    func testCompletionStatusAndHintMappingsKeepExistingDecisionBoundaries() throws {
        let coverageCopy: [String: [String: String]] = [
            "en": [
                "complete": "Scan Complete",
                "good": "Good Coverage",
                "continue": "Continue Scanning",
                "insufficient": "Insufficient Coverage",
                "other_side": "Scan the other side of the canopy",
                "back_side": "Scan the back of the canopy",
                "vertical": "Slow down and scan the upper and lower canopy",
                "sparse_angles": "Scan the sparsely covered angles",
                "trunk": "Start at the trunk and circle the tree slowly",
                "discovering": "Discovering new canopy areas",
                "finish_back": "Scan the back of the canopy, then save",
                "stable": "Coverage is complete. You can save and analyze."
            ],
            "zh": [
                "complete": "扫描完成",
                "good": "覆盖良好",
                "continue": "继续扫描",
                "insufficient": "覆盖率不足",
                "other_side": "补扫树冠另一侧",
                "back_side": "补扫树冠背面",
                "vertical": "放慢补扫树冠上下层",
                "sparse_angles": "补扫稀疏视角",
                "trunk": "从主干开始慢速环绕",
                "discovering": "正在发现树冠新区域",
                "finish_back": "补树冠背面后可保存",
                "stable": "覆盖完整，可保存分析"
            ]
        ]

        for language in ["en", "zh"] {
            let bundle = try localizedBundle(language: language)
            let copy = try XCTUnwrap(coverageCopy[language])

            XCTAssertEqual(L10n.ScanCoverage.statusTitle(for: ScanCompletion(overall: 0.85).coverageStatus, in: bundle), copy["complete"])
            XCTAssertEqual(L10n.ScanCoverage.statusTitle(for: ScanCompletion(overall: 0.60).coverageStatus, in: bundle), copy["good"])
            XCTAssertEqual(L10n.ScanCoverage.statusTitle(for: ScanCompletion(overall: 0.30).coverageStatus, in: bundle), copy["continue"])
            XCTAssertEqual(L10n.ScanCoverage.statusTitle(for: ScanCompletion(overall: 0.29).coverageStatus, in: bundle), copy["insufficient"])

            let hintCases: [(ScanCompletion, String)] = [
                (
                    ScanCompletion(angleCoverageScore: 0.2, voxelCount: 120, discoveryTrend: .stable),
                    "other_side"
                ),
                (
                    ScanCompletion(
                        angleCoverageScore: 0.6,
                        angleUniformityScore: 1,
                        oppositeSideScore: 0.2,
                        verticalCoverageScore: 1,
                        voxelCount: 120,
                        discoveryTrend: .stable
                    ),
                    "back_side"
                ),
                (
                    ScanCompletion(
                        angleCoverageScore: 0.6,
                        angleUniformityScore: 1,
                        oppositeSideScore: 1,
                        verticalCoverageScore: 0.2,
                        voxelCount: 140,
                        discoveryTrend: .stable
                    ),
                    "vertical"
                ),
                (
                    ScanCompletion(
                        angleCoverageScore: 0.6,
                        angleUniformityScore: 0.2,
                        oppositeSideScore: 1,
                        verticalCoverageScore: 1,
                        voxelCount: 120,
                        discoveryTrend: .stable
                    ),
                    "sparse_angles"
                ),
                (ScanCompletion(discoveryTrend: .collecting), "trunk"),
                (ScanCompletion(discoveryTrend: .increasing), "discovering"),
                (ScanCompletion(discoveryTrend: .decreasing), "finish_back"),
                (ScanCompletion(discoveryTrend: .stable), "stable"),
            ]

            for (completion, key) in hintCases {
                XCTAssertEqual(
                    L10n.ScanCoverage.statusHint(for: completion.coverageHint, in: bundle),
                    copy[key],
                    "Incorrect hint mapping for \(key)"
                )
            }
        }
    }

    func testSpatialSampleFormattingUsesTheSelectedLocalizationBundle() throws {
        XCTAssertEqual(
            L10n.ScanCompletion.spatialSamples(420, in: try localizedBundle(language: "en")),
            "420 spatial samples"
        )
        XCTAssertEqual(
            L10n.ScanCompletion.spatialSamples(420, in: try localizedBundle(language: "zh")),
            "420 个空间采样"
        )
    }

    @MainActor
    func testCompletionFeedbackAndControlsRenderInCompactLayout() throws {
        let hudState = ScanHUDState()
        hudState.update(
            pointCount: 12_345,
            coveragePercent: 68,
            scanCompletion: ScanCompletion(
                overall: 0.68,
                timeScore: 0.8,
                voxelScore: 0.75,
                angleCoverageScore: 0.65,
                angleUniformityScore: 0.72,
                oppositeSideScore: 0.58,
                verticalCoverageScore: 0.70,
                stabilityScore: 0.82,
                voxelCount: 420,
                scanDuration: 75,
                discoveryTrend: .decreasing
            )
        )
        let measurementController = MetalMeasurementController()

        let rootView = VStack(spacing: 14) {
            CoverageMapView(completion: hudState.scanCompletion)
                .padding(.horizontal, Design.Space.lg)

            ScanPostCapturePanel(
                pointCount: hudState.pointCount,
                coveragePercent: hudState.coveragePercent,
                completion: hudState.scanCompletion,
                canFinish: true,
                onResume: {},
                onFinish: {}
            )

            #if DEBUG
                ScanBottomControlBar(
                    isRecording: false,
                    isEstimating: false,
                    canFinish: true,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: {},
                    onToggleRecording: {},
                    onToggleMeasurement: {},
                    onCancel: {},
                    onFinish: {},
                    onDebug: {}
                )
            #else
                ScanBottomControlBar(
                    isRecording: false,
                    isEstimating: false,
                    canFinish: true,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: {},
                    onToggleRecording: {},
                    onToggleMeasurement: {},
                    onCancel: {},
                    onFinish: {}
                )
            #endif

            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .frame(width: 390, height: 844, alignment: .top)
        .background(Design.Colors.Dark.bgDeep)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: rootView)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 390, height: 844)
        let renderedImage = try XCTUnwrap(renderer.uiImage)

        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "ScanCompletion-\(Locale.preferredLanguages.first ?? "unknown")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
}
