import XCTest
import ARKit
import AVFoundation
import MetalKit
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

@MainActor
final class ScanReadinessRequestControllerTests: XCTestCase {
    func testCancellationBeforeExecutionSkipsDetermination() async throws {
        let determiner = ImmediateScanReadinessDeterminer()
        let controller = ScanReadinessRequestController {
            await determiner.determine()
        }
        var results: [ScanReadiness] = []

        let task = try XCTUnwrap(controller.start { results.append($0) })
        controller.cancel()
        await task.value

        XCTAssertEqual(determiner.requestCount, 0)
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(controller.isRunning)
    }

    func testResultPublishesOnceAndClearsRunningState() async throws {
        let determiner = ControlledScanReadinessDeterminer()
        let controller = ScanReadinessRequestController {
            await determiner.determine()
        }
        var results: [ScanReadiness] = []

        let task = try XCTUnwrap(controller.start { results.append($0) })
        await determiner.waitForRequestCount(1)
        XCTAssertTrue(controller.isRunning)

        determiner.resumeRequest(0, returning: .ready)
        await task.value

        XCTAssertEqual(results, [.ready])
        XCTAssertFalse(controller.isRunning)
    }

    func testDuplicateStartDoesNotCreateConcurrentRequest() async throws {
        let determiner = ControlledScanReadinessDeterminer()
        let controller = ScanReadinessRequestController {
            await determiner.determine()
        }

        let task = try XCTUnwrap(controller.start { _ in })
        await determiner.waitForRequestCount(1)

        XCTAssertNil(controller.start { _ in })
        XCTAssertEqual(determiner.requestCount, 1)

        determiner.resumeRequest(0, returning: .ready)
        await task.value
    }

    func testCancellationRejectsLateResult() async throws {
        let determiner = ControlledScanReadinessDeterminer()
        let controller = ScanReadinessRequestController {
            await determiner.determine()
        }
        var results: [ScanReadiness] = []

        let task = try XCTUnwrap(controller.start { results.append($0) })
        await determiner.waitForRequestCount(1)

        controller.cancel()
        controller.cancel()
        determiner.resumeRequest(0, returning: .cameraDenied)
        await task.value

        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(controller.isRunning)
    }

    func testLateCancelledRequestCannotClearOrPublishOverReplacement() async throws {
        let determiner = ControlledScanReadinessDeterminer()
        let controller = ScanReadinessRequestController {
            await determiner.determine()
        }
        var results: [ScanReadiness] = []

        let firstTask = try XCTUnwrap(controller.start { results.append($0) })
        await determiner.waitForRequestCount(1)
        controller.cancel()

        let secondTask = try XCTUnwrap(controller.start { results.append($0) })
        await determiner.waitForRequestCount(2)

        determiner.resumeRequest(0, returning: .cameraDenied)
        await firstTask.value
        XCTAssertTrue(controller.isRunning)
        XCTAssertTrue(results.isEmpty)

        determiner.resumeRequest(1, returning: .ready)
        await secondTask.value
        XCTAssertEqual(results, [.ready])
        XCTAssertFalse(controller.isRunning)
    }
}

@MainActor
private final class ImmediateScanReadinessDeterminer {
    private(set) var requestCount = 0

    func determine() async -> ScanReadiness {
        requestCount += 1
        return .ready
    }
}

@MainActor
private final class ControlledScanReadinessDeterminer {
    private var nextRequestID = 0
    private var pendingRequests: [Int: CheckedContinuation<ScanReadiness, Never>] = [:]
    private var requestCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    private(set) var requestCount = 0

    func determine() async -> ScanReadiness {
        await withCheckedContinuation { continuation in
            let requestID = nextRequestID
            nextRequestID += 1
            requestCount += 1
            pendingRequests[requestID] = continuation
            resumeSatisfiedWaiters()
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard requestCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append((expectedCount, continuation))
        }
    }

    func resumeRequest(_ requestID: Int, returning readiness: ScanReadiness) {
        pendingRequests.removeValue(forKey: requestID)?.resume(returning: readiness)
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in requestCountWaiters {
            if requestCount >= expectedCount {
                continuation.resume()
            } else {
                remaining.append((expectedCount, continuation))
            }
        }
        requestCountWaiters = remaining
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

final class ScanSessionSnapshotTests: XCTestCase {
    @MainActor
    func testFeatureModelRejectsAnOlderQueuedLifecycleSnapshot() {
        let identity = UUID()
        let starting = ScanLifecycleSnapshot(
            state: .recording,
            scanIdentity: identity,
            generation: 4,
            interruptionCount: 0,
            lastInterruptionTimestamp: nil
        )
        let model = ScanFeatureModel(initialSnapshot: starting)
        let finishing = ScanLifecycleSnapshot(
            state: .finishing,
            scanIdentity: identity,
            generation: 5,
            interruptionCount: 0,
            lastInterruptionTimestamp: nil
        )
        let completed = ScanLifecycleSnapshot(
            state: .completed,
            scanIdentity: identity,
            generation: 6,
            interruptionCount: 0,
            lastInterruptionTimestamp: nil
        )

        model.apply(completed)
        model.apply(finishing)

        XCTAssertEqual(model.lifecycleSnapshot, completed)
        XCTAssertFalse(model.isRecording)
    }

    func testCaptureAdmissionGateSeparatesPauseFromInvalidationEpoch() {
        let gate = CaptureAdmissionGate()
        let scanIdentity = UUID()
        let bindingID = gate.snapshot().bindingID
        _ = gate.setOpen(true)
        let token = gate.makeToken(scanIdentity: scanIdentity, bindingID: bindingID)
        let tokenEpoch = token?.invalidationEpoch

        _ = gate.setOpen(false)
        XCTAssertEqual(gate.snapshot().invalidationEpoch, tokenEpoch)
        XCTAssertFalse(gate.snapshot().isOpen)

        gate.invalidate()
        XCTAssertGreaterThan(gate.snapshot().invalidationEpoch, tokenEpoch ?? 0)
        XCTAssertFalse(gate.snapshot().isOpen)

        gate.bind(to: ScanBindingID())
        _ = gate.setOpen(true)
        XCTAssertNil(gate.makeToken(scanIdentity: scanIdentity, bindingID: bindingID))
        XCTAssertNotNil(gate.makeToken(scanIdentity: scanIdentity, bindingID: gate.snapshot().bindingID))
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
final class ScanCoordinatorARSessionIdentityTests: XCTestCase {
    func testStaleSessionInterruptionCannotInvalidateReplacementScan() async throws {
        let coordinator = ScanCoordinator()
        let activeSession = ARSession()
        coordinator.session = activeSession
        coordinator.startRecording(selectedCategory: .apple)
        let recording = coordinator.lifecycleSnapshot()
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.sessionWasInterrupted(ARSession())
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot(), recording)
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(coordinator.acceptsCapturedEvidence(token))
    }

    func testStaleSessionFailureCannotFailReplacementScan() async {
        let coordinator = ScanCoordinator()
        let activeSession = ARSession()
        coordinator.session = activeSession
        coordinator.startRecording(selectedCategory: .apple)
        let recording = coordinator.lifecycleSnapshot()

        coordinator.session(
            ARSession(),
            didFailWithError: ScanSessionTestError.camera
        )
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot(), recording)
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
    }

    func testStaleInterruptionEndCannotRecoverCurrentInterruptedSession() async {
        let coordinator = ScanCoordinator()
        let activeSession = ARSession()
        coordinator.session = activeSession
        coordinator.startRecording(selectedCategory: .apple)

        coordinator.sessionWasInterrupted(activeSession)
        await Task.yield()
        let interrupted = coordinator.lifecycleSnapshot()
        XCTAssertEqual(
            interrupted.state,
            .systemInterrupted(.arSessionInterrupted)
        )

        coordinator.sessionInterruptionEnded(ARSession())
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot(), interrupted)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
    }

    func testAcceptedFailureCannotFailScanStartedAfterSessionReplacement() async {
        let coordinator = ScanCoordinator()
        let replacedSession = ARSession()
        coordinator.session = replacedSession
        coordinator.startRecording(selectedCategory: .apple)

        coordinator.session(
            replacedSession,
            didFailWithError: ScanSessionTestError.camera
        )

        coordinator.session = ARSession()
        let replacementScan = coordinator.scanLifecycle.startNewScan()
        _ = coordinator.setReliableEvidenceAcceptance(true)
        await Task.yield()

        XCTAssertEqual(coordinator.lifecycleSnapshot(), replacementScan)
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
    }
}

@MainActor
final class MetalViewBindingLifecycleTests: XCTestCase {
    func testDismantlingCurrentMetalViewReleasesOnlyBoundRuntime() {
        let coordinator = ScanCoordinator()
        let session = ARSession()
        let metalView = MTKView()
        let hudState = ScanHUDState()
        coordinator.session = session
        coordinator.mtkView = metalView
        coordinator.hudState = hudState
        coordinator.onMeasurementReady = { _ in }
        session.delegate = coordinator

        MetalView.dismantleUIView(
            metalView,
            coordinator: MetalViewCoordinator(coordinator: coordinator)
        )
        MetalView.dismantleUIView(
            metalView,
            coordinator: MetalViewCoordinator(coordinator: coordinator)
        )

        XCTAssertTrue(coordinator.isTornDown)
        XCTAssertNil(coordinator.session)
        XCTAssertNil(coordinator.mtkView)
        XCTAssertNil(session.delegate)
        XCTAssertTrue(coordinator.hudState === hudState)
        XCTAssertNotNil(coordinator.onMeasurementReady)
    }

    func testLateDismantleOfReplacedViewCannotTearDownCurrentBinding() {
        let coordinator = ScanCoordinator()
        let session = ARSession()
        let replacedView = MTKView()
        let currentView = MTKView()
        coordinator.session = session
        coordinator.mtkView = currentView
        session.delegate = coordinator

        MetalView.dismantleUIView(
            replacedView,
            coordinator: MetalViewCoordinator(coordinator: coordinator)
        )

        XCTAssertFalse(coordinator.isTornDown)
        XCTAssertTrue(coordinator.session === session)
        XCTAssertTrue(coordinator.mtkView === currentView)
        XCTAssertTrue(session.delegate === coordinator)
    }

    func testDismantleRejectsQueuedMeasurementCallbackFromRemovedBinding() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let metalView = MTKView(frame: .zero, device: device)
        let session = ARSession()
        let renderer = Renderer(
            session: session,
            metalDevice: device,
            renderDestination: metalView
        )
        let coordinator = ScanCoordinator(
            sessionRuntime: ScanSessionRuntime(
                isWorldTrackingSupported: { false },
                run: { _, _, _ in }
            )
        )
        var publishedRenderers: [Renderer] = []
        coordinator.onMeasurementReady = { publishedRenderers.append($0) }
        metalView.delegate = renderer

        coordinator.bind(
            session: session,
            renderer: renderer,
            mtkView: metalView
        )
        MetalView.dismantleUIView(
            metalView,
            coordinator: MetalViewCoordinator(coordinator: coordinator)
        )
        await drainMainQueue()

        XCTAssertTrue(publishedRenderers.isEmpty)
        coordinator.teardown()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
final class ScanReadinessRecoveryBindingTests: XCTestCase {
    func testReadinessBlockPreservesParentBindingsAcrossRendererRebind() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let coordinator = ScanCoordinator(
            sessionRuntime: ScanSessionRuntime(
                isWorldTrackingSupported: { false },
                run: { _, _, _ in }
            )
        )
        let oldSession = ARSession()
        let oldView = MTKView(frame: .zero, device: device)
        let hudState = ScanHUDState()
        var publishedRenderers: [Renderer] = []
        coordinator.session = oldSession
        coordinator.mtkView = oldView
        coordinator.hudState = hudState
        coordinator.onMeasurementReady = { publishedRenderers.append($0) }
        coordinator.onQualitySampleUpdate = { _ in }
        coordinator.onCoveragePercentChange = { _ in }
        coordinator.onFruitCategoryMismatch = { _ in }
        coordinator.onCalibrationWarning = { _ in }
        coordinator.onLifecycleStateChange = { _ in }
        #if DEBUG
        coordinator.onDetectionDebugStateChange = { _ in }
        #endif
        coordinator.hasPublishedCategoryMismatch = true
        oldSession.delegate = coordinator

        coordinator.teardownForReadinessBlock()
        coordinator.teardownForReadinessBlock()

        XCTAssertTrue(coordinator.isTornDown)
        XCTAssertNil(coordinator.session)
        XCTAssertNil(coordinator.mtkView)
        XCTAssertNil(oldSession.delegate)
        XCTAssertFalse(coordinator.hasPublishedCategoryMismatch)
        XCTAssertTrue(coordinator.hudState === hudState)
        XCTAssertNotNil(coordinator.onMeasurementReady)
        XCTAssertNotNil(coordinator.onQualitySampleUpdate)
        XCTAssertNotNil(coordinator.onCoveragePercentChange)
        XCTAssertNotNil(coordinator.onFruitCategoryMismatch)
        XCTAssertNotNil(coordinator.onCalibrationWarning)
        XCTAssertNotNil(coordinator.onLifecycleStateChange)
        #if DEBUG
        XCTAssertNotNil(coordinator.onDetectionDebugStateChange)
        #endif

        let replacementSession = ARSession()
        let replacementView = MTKView(frame: .zero, device: device)
        let replacementRenderer = Renderer(
            session: replacementSession,
            metalDevice: device,
            renderDestination: replacementView
        )
        replacementView.delegate = replacementRenderer
        coordinator.bind(
            session: replacementSession,
            renderer: replacementRenderer,
            mtkView: replacementView
        )
        await drainMainQueue()

        XCTAssertEqual(publishedRenderers.count, 1)
        XCTAssertTrue(publishedRenderers.first === replacementRenderer)
        coordinator.teardown()
    }

    func testFullTeardownStillReleasesParentBindings() {
        let coordinator = ScanCoordinator()
        coordinator.hudState = ScanHUDState()
        coordinator.onMeasurementReady = { _ in }
        coordinator.onLifecycleStateChange = { _ in }

        coordinator.teardown()

        XCTAssertNil(coordinator.hudState)
        XCTAssertNil(coordinator.onMeasurementReady)
        XCTAssertNil(coordinator.onLifecycleStateChange)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
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
    var cameraRequests: [ScanCameraRequest] = []
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
        },
        preferredVideoFormat: { [weak self] request in
            self?.cameraRequests.append(request)
            return nil
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
            await coordinator.appendObservations(
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
        XCTAssertEqual(coordinator.detectedFruits.first?.id, detection.id)
        XCTAssertEqual(coordinator.detectedFruits.first?.frameID, detection.frameID)
    }

    func testCapturedEvidenceCanCommitDuringUserPause() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startRecording(selectedCategory: .apple)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())

        coordinator.stopRecording()
        await coordinator.appendObservations(
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
        await coordinator.appendObservations(
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
        await coordinator.appendObservations(
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
        await coordinator.appendObservations(
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
        await coordinator.appendObservations(
            [makeDetection(timestamp: 6)],
            evidenceToken: token
        )

        XCTAssertTrue(coordinator.detectedFruits.isEmpty)
    }

    private func makeDetection(timestamp: TimeInterval) -> Observation {
        DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            confidence: 0.95,
            timestamp: timestamp
        ).resolvedObservation(frameID: FrameID())
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
    func testVideoFormatSelectionRespectsRequestedCeilingAndPrioritizesFrameRate() {
        let formats = [
            ScanVideoFormatDescriptor(framesPerSecond: 30, imageWidth: 1280),
            ScanVideoFormatDescriptor(framesPerSecond: 60, imageWidth: 1920),
            ScanVideoFormatDescriptor(framesPerSecond: 60, imageWidth: 3840),
            ScanVideoFormatDescriptor(framesPerSecond: 120, imageWidth: 1280)
        ]
        XCTAssertEqual(ScanSessionConfiguration.preferredVideoFormatIndex(in: formats,
            request: ScanCameraRequest(resolution: "4K", frameRate: "30fps")), 0)
        XCTAssertEqual(ScanSessionConfiguration.preferredVideoFormatIndex(in: formats,
            request: ScanCameraRequest(resolution: "4K", frameRate: "60fps")), 2)
        XCTAssertEqual(ScanSessionConfiguration.preferredVideoFormatIndex(in: formats,
            request: ScanCameraRequest(resolution: "4K", frameRate: "120fps")), 3)
        XCTAssertEqual(ScanSessionConfiguration.preferredVideoFormatIndex(in: formats,
            request: ScanCameraRequest(resolution: "720p", frameRate: "60fps")), 1)
    }

    func testVideoFormatSelectionKeepsARKitFallbackWhenNoEligibleFormatExists() {
        let request = ScanCameraRequest(resolution: "1080p", frameRate: "30fps")
        XCTAssertNil(ScanSessionConfiguration.preferredVideoFormatIndex(in: [], request: request))
        XCTAssertNil(ScanSessionConfiguration.preferredVideoFormatIndex(
            in: [ScanVideoFormatDescriptor(framesPerSecond: 60, imageWidth: 1920)], request: request))
    }

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

private actor FixedScanModelIdentityProvider: ScanModelIdentityProviding {
    private let identity: ScanModelIdentity

    init(identity: ScanModelIdentity) {
        self.identity = identity
    }

    func modelIdentity() async -> ScanModelIdentity {
        identity
    }
}

final class ScanPlanTests: XCTestCase {
    @MainActor
    func testRendererSettingsCapturePreservesPresetAndFrozenValues() throws {
        let suite = "RendererCapture-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let presets: [(String, Float, Float)] = [("高", 0.007, 0.08), ("中", 0.01, 0.12), ("低", 0.015, 0.16)]
        for (preset, expectedVoxel, expectedEdge) in presets {
            store.qualityPreset = preset
            store.maxPointCount = 500_000
            store.rgbRadius = 4.25
            store.depthRangeMax = 4.2
            store.depthRangeMin = 0.8
            store.confidenceThreshold = 0
            store.scanPrecision = 0.01
            var depth = DepthExperimentConfig.default
            depth.minimumReliableConfidence = 2
            depth.minimumStableDepthNeighborCount = 9
            depth.projectionSampleGrid = 5
            let capturedDepth = depth
            let captured = RendererScanSettings(store: store, particleCapacity: 12_345, depthConfiguration: depth)

            // Both settings and experiment values may change after a scan is bound.
            store.qualityPreset = "高"
            store.maxPointCount = 900_000
            store.rgbRadius = 7
            store.depthRangeMin = 1
            store.depthRangeMax = 6
            store.confidenceThreshold = 1
            store.scanPrecision = 0.04
            depth.minimumStableDepthNeighborCount = 0
            depth.projectionSampleGrid = 3

            XCTAssertEqual(captured.maxPoints, 12_345)
            XCTAssertEqual(captured.rgbRadius, 4.25)
            XCTAssertEqual(captured.minDepth, 0.8, accuracy: 0.00001)
            XCTAssertEqual(captured.maxDepth, 4.2, accuracy: 0.00001)
            XCTAssertEqual(captured.confidenceThreshold, 2)
            XCTAssertEqual(captured.minimumStableDepthNeighborCount, 4)
            XCTAssertEqual(captured.snapshotVoxelSize, expectedVoxel, accuracy: 0.000001, preset)
            XCTAssertEqual(captured.depthEdgeThreshold, expectedEdge, preset)
            XCTAssertEqual(captured.depthConfiguration, capturedDepth)
        }
    }

    @MainActor
    func testRendererSettingsCaptureKeepsDepthAndVoxelBounds() throws {
        let suite = "RendererCaptureBounds-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.maxPointCount = 200_000
        store.confidenceThreshold = 0
        var depth = DepthExperimentConfig.default
        depth.minimumReliableConfidence = 0
        depth.minimumStableDepthNeighborCount = -5
        for (preset, precision, expectedVoxel) in [("高", 0.001, Float(0.001)), ("低", 0.05, Float(0.06))] {
            store.qualityPreset = preset
            store.scanPrecision = precision
            let captured = RendererScanSettings(store: store, particleCapacity: 300_000, depthConfiguration: depth)
            XCTAssertEqual(captured.maxPoints, 200_000)
            XCTAssertEqual(captured.confidenceThreshold, 1, "Unavailable/low confidence cannot loosen the reliable depth floor")
            XCTAssertEqual(captured.minimumStableDepthNeighborCount, 0)
            XCTAssertEqual(captured.snapshotVoxelSize, expectedVoxel, accuracy: 0.000001)
        }
    }

    @MainActor
    func testNewScanReconfiguresPreviewToFrozenCameraRequestAndWaitsForTracking() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "CameraPlan-\(UUID())")!)
        settings.cameraResolution = "720p"
        settings.cameraFrameRate = "30fps"
        let recorder = ScanSessionRuntimeRecorder()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let session = ARSession()
        let view = MTKView(frame: .zero, device: device)
        let renderer = Renderer(session: session, metalDevice: device, renderDestination: view)
        let coordinator = ScanCoordinator(settings: settings, sessionRuntime: recorder.runtime, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.bind(session: session, renderer: renderer, mtkView: view)
        XCTAssertEqual(recorder.cameraRequests, [ScanCameraRequest(resolution: "720p", frameRate: "30fps")])
        settings.cameraResolution = "4K"
        settings.cameraFrameRate = "60fps"
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("camera-test")),
            resourceBudget: ScanResourceBudget(liveSnapshotSampleLimit: 200, analysisInputSampleLimit: 100))
        await factory.prepareModelIdentity()
        let plan = factory.makePlan(treeID: "camera", season: .mature, selectedCategory: .apple, renderer: renderer)
        settings.cameraResolution = "1080p"
        settings.cameraFrameRate = "120fps"
        coordinator.handleCameraTrackingState(.normal)
        coordinator.startRecording(plan: plan)
        XCTAssertEqual(recorder.cameraRequests.last, plan.cameraRequest)
        XCTAssertEqual(recorder.runOptions.count, 2)
        XCTAssertEqual(recorder.runOptions.last, [])
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        coordinator.handleCameraTrackingState(.normal)
        await Task.yield()
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())
        coordinator.stopRecording()
        coordinator.resumeRecordingPreservingCapture()
        XCTAssertEqual(recorder.runOptions.count, 2, "Same-scan resume must not restart the camera")
        XCTAssertTrue(coordinator.acceptsCapturedEvidence(token))
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertEqual(renderer.analysisInputSampleLimit, 100, "Deferred binding setup must not overwrite the active plan")
        XCTAssertEqual(renderer.liveSnapshotInputSampleLimit, 200)
        XCTAssertTrue(coordinator.beginFinishingScan())
        coordinator.markScanCompleted()
        settings.cameraResolution = plan.requestedCameraResolution
        settings.cameraFrameRate = plan.requestedCameraFrameRate
        let matchingPlan = factory.makePlan(treeID: "same-camera", season: .mature, selectedCategory: .apple, renderer: renderer)
        coordinator.startRecording(plan: matchingPlan)
        XCTAssertEqual(recorder.runOptions.count, 2, "An unchanged camera request must not reset healthy tracking")
        XCTAssertTrue(coordinator.acceptsReliableEvidence())
        XCTAssertFalse(coordinator.acceptsCapturedEvidence(token), "The next scan must reject the previous scan's accepted work")
    }

    @MainActor
    func testPlannedScanStartFailsClosedWhenBoundARSessionIsUnsupported() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "UnsupportedPlan-\(UUID())")!)
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] })
        let plan = factory.makePlan(treeID: "unsupported", season: .mature, selectedCategory: .apple, renderer: nil)
        let recorder = ScanSessionRuntimeRecorder(isSupported: false)
        let coordinator = ScanCoordinator(settings: settings, sessionRuntime: recorder.runtime, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.session = ARSession()
        coordinator.startRecording(plan: plan)
        XCTAssertTrue(recorder.runOptions.isEmpty)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        guard case .failed(.sessionFailed) = coordinator.lifecycleSnapshot().state else {
            return XCTFail("An unsupported camera must not leave the planned scan recording")
        }
    }

    @MainActor
    func testInterruptedRestartSelectsIncomingPlanBeforeReplacingOldPlan() async {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "CameraRestart-\(UUID())")!)
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("camera-test")))
        await factory.prepareModelIdentity()
        let old = factory.makePlan(treeID: "old", season: .mature, selectedCategory: .apple, renderer: nil)
        settings.cameraResolution = "720p"
        settings.cameraFrameRate = "30fps"
        let next = factory.makePlan(treeID: "next", season: .mature, selectedCategory: .apple, renderer: nil)
        settings.cameraResolution = "4K"
        settings.cameraFrameRate = "120fps"
        let recorder = ScanSessionRuntimeRecorder()
        let coordinator = ScanCoordinator(settings: settings, sessionRuntime: recorder.runtime, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.session = ARSession()
        coordinator.startRecording(plan: old)
        coordinator.handleSessionFailure(ScanSessionTestError.camera)
        let beforeRestart = recorder.runOptions.count
        recorder.beforeRun = {
            XCTAssertEqual(coordinator.activeScanPlan?.id, old.id, "Old failed scan remains the owner until session restart succeeds")
            XCTAssertEqual(recorder.cameraRequests.last, next.cameraRequest)
            XCTAssertFalse(coordinator.acceptsReliableEvidence())
        }
        XCTAssertTrue(coordinator.restartInterruptedScan(plan: next))
        XCTAssertEqual(recorder.runOptions.count, beforeRestart + 1, "Applying the new plan must not run the session twice")
        XCTAssertEqual(coordinator.activeScanPlan?.id, next.id)
        XCTAssertEqual(recorder.cameraRequests.last, next.cameraRequest)
        XCTAssertTrue(recorder.runOptions.last?.contains(.resetTracking) == true)
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        recorder.beforeRun = nil
    }

    @MainActor
    func testCustomPlanConfigurationReachesFrozenEstimateAfterSettingsReload() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "PlanExperiment-\(UUID())")!)
        var experiment = FruitScanExperimentConfig.default
        experiment.fusion.nearestCandidateDistance = 0.07
        experiment.pointCloud.denoisingNeighborCount = 8
        experiment.depth.minimumReliableConfidence = 2
        experiment.depth.projectionSampleGrid = 3
        let capturedExperiment = experiment
        let budget = ScanResourceBudget(liveSnapshotSampleLimit: 200, analysisInputSampleLimit: 100, retainedDetectionFrameLimit: 2)
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("model-config")),
            experimentConfiguration: experiment, resourceBudget: budget)
        await factory.prepareModelIdentity()
        let plan = factory.makePlan(treeID: "config", season: .mature, selectedCategory: .apple, renderer: nil)
        experiment.fusion.nearestCandidateDistance = 0.9
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.startRecording(plan: plan)
        settings.minConfidence = 0.99
        coordinator.loadSettings()
        XCTAssertEqual(plan.rendererSettings.confidenceThreshold, 2)
        XCTAssertEqual(plan.rendererSettings.depthConfiguration, capturedExperiment.depth)
        for timestamp in 1...3 {
            await coordinator.appendDetectedFruits([DetectedFruit(category: .apple, boundingBox: .zero,
                confidence: 0.9, timestamp: Double(timestamp))])
        }
        XCTAssertEqual(Set(coordinator.detectedFruits.map(\.timestamp)), Set([2.0, 3.0]))
        XCTAssertTrue(coordinator.beginFinishingScan())
        let cloud = FinalPointCloud(identity: RendererSnapshotSignature(pointCount: 0, pointIndex: 0,
            voxelSize: 0.005, confidenceThreshold: 2), points: [], inputSampleCount: 0, retainedSampleCount: 0,
            buildDuration: 0, estimatedPeakPayloadBytes: 0)
        let snapshot = try await coordinator.prepareYieldEstimationSnapshot(season: .mature, finalPointCloud: cloud)
        XCTAssertEqual(snapshot.input.experimentConfiguration, capturedExperiment)
        XCTAssertEqual(snapshot.input.calibrationIdentity?.context, plan.fruitConfiguration.calibrationContext)
        XCTAssertEqual(snapshot.input.calibrationIdentity?.algorithmRevision, plan.algorithmRevision)
        XCTAssertEqual(snapshot.input.fusionConfig.minConfidence, plan.fruitConfiguration.fusionConfig.minConfidence)
        XCTAssertEqual(snapshot.input.observations.count, 2)
    }

    @MainActor
    func testChangedExperimentOrSamplingBudgetDoesNotReuseCalibration() throws {
        let empty = ScanFruitConfigurationSnapshot.capture(selectedCategory: .apple, settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] })
        let original = empty.makeConfiguration(modelIdentity: .verified("same-model"))
        let context = try XCTUnwrap(original.calibrationContext)
        let record = CalibrationRecord(id: UUID(), treeID: "config", scanDate: Date(), estimatedFruitCount: 10,
            manualFruitCount: 8, estimatedYieldKg: 5, actualYieldKg: 4, fruitType: FruitCategory.apple.rawValue,
            algorithmRevision: YieldAlgorithmRevision.current, calibrationContext: context)
        let snapshot = ScanFruitConfigurationSnapshot.capture(selectedCategory: .apple, settings: SettingsStore.shared,
            calibrationRecordsLoader: { [record] })
        let same = snapshot.makeConfiguration(modelIdentity: .verified("same-model"))
        var experiment = FruitScanExperimentConfig.default
        experiment.occlusion.lidarPenetrationMeters = 0.2
        let changed = snapshot.makeConfiguration(modelIdentity: .verified("same-model"), experimentConfiguration: experiment)
        let reduced = snapshot.makeConfiguration(modelIdentity: .verified("same-model"),
            resourceBudget: ScanResourceBudget(analysisInputSampleLimit: 100))
        XCTAssertEqual(same.calibrationContext, context)
        XCTAssertFalse(context.contains("resourceBudget"), "Default calibration context retains its existing shape")
        XCTAssertEqual(same.calibrationCorrection.yieldFactor, 0.8, accuracy: 0.001)
        XCTAssertNotEqual(changed.calibrationContext, context)
        XCTAssertNotEqual(reduced.calibrationContext, context)
        XCTAssertEqual(changed.calibrationCorrection, .neutral)
        XCTAssertEqual(reduced.calibrationCorrection, .neutral)
    }

    @MainActor
    func testRendererAppliesBoundedBudgetAndInvalidatesPreviousAnalysisCache() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame: .zero, device: device)
        let renderer = Renderer(session: ARSession(), metalDevice: device, renderDestination: view)
        let settings = RendererScanSettings(store: SettingsStore.shared, particleCapacity: renderer.particlesBuffer.count)
        renderer.fullAnalysisSnapshotSignature = RendererSnapshotSignature(pointCount: 10, pointIndex: 10,
            voxelSize: 0.005, confidenceThreshold: 1)
        renderer.applyScanQualitySettings(settings,
            resourceBudget: ScanResourceBudget(liveSnapshotSampleLimit: 20, analysisInputSampleLimit: 10))
        XCTAssertEqual(renderer.liveSnapshotInputSampleLimit, 20)
        XCTAssertEqual(renderer.analysisInputSampleLimit, 10)
        XCTAssertNil(renderer.fullAnalysisSnapshotSignature)
        XCTAssertEqual(ScanResourceBudget(liveSnapshotSampleLimit: Int.max, analysisInputSampleLimit: Int.max,
            retainedDetectionFrameLimit: Int.max), .default)
        XCTAssertEqual(ScanResourceBudget(analysisInputSampleLimit: 0).analysisInputSampleLimit, 1)
    }

    @MainActor
    func testPlanKeepsScanConfigurationAndBudgetsAfterSettingsChange() async {
        let suiteName = "ScanPlanTests-\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        settings.autoExportCSV = true
        settings.maxPointCount = 250_000
        settings.minConfidence = 0.62
        settings.clusterMinPoints = 8

        let factory = ScanPlanFactory(
            settings: settings,
            calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("model-a"))
        )
        await factory.prepareModelIdentity()

        let plan = factory.makePlan(
            treeID: "T-plan",
            season: .mature,
            selectedCategory: .apple,
            renderer: nil
        )
        let capturedConfidence = plan.fruitConfiguration.fusionConfig.minConfidence
        let capturedClusterMinPoints = plan.fruitConfiguration.clusterConfig.minPoints

        settings.autoExportCSV = false
        settings.maxPointCount = 400_000
        settings.minConfidence = 0.91
        settings.clusterMinPoints = 15

        XCTAssertEqual(plan.treeID, "T-plan")
        XCTAssertEqual(plan.season, .mature)
        XCTAssertEqual(plan.fruitConfiguration.selectedCategory, .apple)
        XCTAssertEqual(plan.modelIdentity, .verified("model-a"))
        XCTAssertEqual(plan.autoExportCSV, true)
        XCTAssertEqual(plan.rendererSettings.maxPoints, 250_000)
        XCTAssertEqual(plan.resourceBudget.liveSnapshotSampleLimit, 240_000)
        XCTAssertEqual(plan.resourceBudget.analysisInputSampleLimit, 120_000)
        XCTAssertEqual(plan.resourceBudget.retainedDetectionFrameLimit, 360)
        XCTAssertEqual(plan.fruitConfiguration.fusionConfig.minConfidence, capturedConfidence)
        XCTAssertEqual(plan.fruitConfiguration.clusterConfig.minPoints, capturedClusterMinPoints)
        XCTAssertNotEqual(settings.fruitScanConfig.minConfidence, capturedConfidence)
    }

    @MainActor
    func testCoordinatorUsesScanPlanAfterSettingsChangeAndReload() async {
        let suiteName = "ScanPlanCoordinatorTests-\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        settings.minConfidence = 0.58
        settings.clusterMinPoints = 7

        let factory = ScanPlanFactory(
            settings: settings,
            calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("model-a"))
        )
        await factory.prepareModelIdentity()
        let plan = factory.makePlan(
            treeID: "T-coordinator-plan",
            season: .off,
            selectedCategory: .pear,
            renderer: nil
        )
        let capturedClusterMinPoints = plan.fruitConfiguration.clusterConfig.minPoints
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })

        coordinator.startRecording(plan: plan)
        settings.minConfidence = 0.93
        settings.clusterMinPoints = 17
        coordinator.loadSettings()

        XCTAssertEqual(coordinator.activeScanPlan?.id, plan.id)
        XCTAssertEqual(coordinator.imageDetector.configSnapshot().minConfidence, plan.fruitConfiguration.fusionConfig.minConfidence)
        XCTAssertEqual(coordinator.activeFruitConfiguration?.clusterConfig.minPoints, capturedClusterMinPoints)
        XCTAssertNotEqual(
            settings.clusterConfig(for: plan.fruitConfiguration.defaultParams).minPoints,
            capturedClusterMinPoints
        )

        coordinator.teardown()
    }

    @MainActor
    func testMissingModelAndUnverifiedIdentityDisableCalibrationWithSpecificReasons() {
        let snapshot = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: .apple,
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] }
        )

        let missingModel = snapshot.makeConfiguration(modelIdentity: .modelMissing)
        XCTAssertNil(missingModel.calibrationContext)
        XCTAssertEqual(missingModel.calibrationCorrection, .neutral)
        XCTAssertEqual(missingModel.calibrationWarning, .modelMissing)

        let unavailableIdentity = snapshot.makeConfiguration(modelIdentity: .fingerprintUnavailable)
        XCTAssertNil(unavailableIdentity.calibrationContext)
        XCTAssertEqual(unavailableIdentity.calibrationCorrection, .neutral)
        XCTAssertEqual(unavailableIdentity.calibrationWarning, .modelIdentityUnavailable)
    }

    @MainActor
    func testChangedModelIdentityDoesNotReuseCalibrationForPreviousModel() throws {
        let snapshotWithoutRecords = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: .apple,
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] }
        )
        let oldContext = try XCTUnwrap(snapshotWithoutRecords.makeConfiguration(
            modelIdentity: .verified("model-a")
        ).calibrationContext)
        var record = CalibrationRecord(
            id: UUID(),
            treeID: "T-model-identity",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: 10,
            manualFruitCount: 8,
            estimatedYieldKg: 5,
            actualYieldKg: 4,
            fruitType: FruitCategory.apple.rawValue
        )
        record.algorithmRevision = YieldAlgorithmRevision.current
        record.calibrationContext = oldContext

        let snapshot = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: .apple,
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [record] }
        )
        let sameModel = snapshot.makeConfiguration(modelIdentity: .verified("model-a"))
        let changedModel = snapshot.makeConfiguration(modelIdentity: .verified("model-b"))

        XCTAssertEqual(sameModel.calibrationCorrection.countFactor, 0.8, accuracy: 0.001)
        XCTAssertEqual(sameModel.calibrationCorrection.yieldFactor, 0.8, accuracy: 0.001)
        XCTAssertNotEqual(sameModel.calibrationContext, changedModel.calibrationContext)
        XCTAssertEqual(changedModel.calibrationCorrection, .neutral)
    }

    @MainActor
    func testPlanCreatedWhileModelIdentityIsPreparingFailsClosed() {
        let factory = ScanPlanFactory(
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("model-a"))
        )

        let plan = factory.makePlan(
            treeID: "T-pending-model",
            season: .mature,
            selectedCategory: .apple,
            renderer: nil
        )

        XCTAssertEqual(plan.modelIdentity, .preparing)
        XCTAssertNil(plan.fruitConfiguration.calibrationContext)
        XCTAssertEqual(plan.fruitConfiguration.calibrationCorrection, .neutral)
        XCTAssertEqual(plan.fruitConfiguration.calibrationWarning, .modelIdentityUnavailable)
    }
}

@MainActor
private final class ScanFinalizationTestHarness {
    private(set) var snapshot: ScanLifecycleSnapshot
    private(set) var exportCompletions: [(String?) -> Void] = []
    private(set) var estimateCompletions: [(YieldResult, FruitCountResult?) -> Void] = []
    private(set) var exportCount = 0
    private(set) var estimateCount = 0
    private(set) var preparationCount = 0
    private(set) var estimatedSnapshotIDs: [UUID] = []
    private(set) var estimatedEvidence: [ScanEvidenceIdentity] = []
    private var captureContext: ScanContext?
    private(set) var persistenceCount = 0
    private(set) var persistedInputs: [(UUID, String, Float)] = []
    private(set) var markCompletedCount = 0
    private(set) var historyRefreshCount = 0
    private(set) var discardedFilenames: [String] = []
    private(set) var committedRecordCount = 0
    private(set) var completedPersistenceOperationCount = 0
    var shouldFailFirstPersistence = false
    var shouldSuspendPersistence = false
    var shouldFailFirstEstimation = false
    var shouldFailPreparation = false
    var preparedContextOverride: ScanContext?
    var resultEvidenceOverride: ((ScanEvidenceIdentity) -> ScanEvidenceIdentity)?
    private var persistenceContinuation: CheckedContinuation<Void, Never>?

    init(state: ScanLifecycleState = .recording) {
        snapshot = ScanLifecycleSnapshot(
            state: state,
            scanIdentity: UUID(),
            generation: 1,
            interruptionCount: 0,
            lastInterruptionTimestamp: nil
        )
    }

    var operations: ScanFinalizationOperations {
        ScanFinalizationOperations(
            lifecycleSnapshot: { self.snapshot },
            beginFinishing: {
                guard self.snapshot.state == .recording || self.snapshot.state == .userPaused else { return false }
                self.setState(.finishing)
                return true
            },
            exportPointCloud: { plan, _, _ in
                self.exportCount += 1
                let context = ScanContext(scanID: self.snapshot.scanIdentity, planID: plan.id)
                self.captureContext = context
                return try await withCheckedThrowingContinuation { continuation in
                    self.exportCompletions.append { filename in
                        if let filename {
                            continuation.resume(returning: Self.stagedPointCloud(filename: filename, context: context))
                        } else {
                            continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                        }
                    }
                }
            },
            prepareSnapshot: { season, staged in
                self.preparationCount += 1
                if self.shouldFailPreparation {
                    throw ScanYieldEstimationController.PreparationError.snapshotUnavailable
                }
                let cloud = staged.pointCloud
                let params = FruitVarietyParams(category: .apple)
                let input = ScanYieldEstimationController.Snapshot(context: self.preparedContextOverride ?? self.captureContext, input: .init(
                    points: cloud.points, observations: [], imageDiagnostics: ImageDetectionDiagnostics(),
                    fruitType: "apple", fruitCategory: .apple, paramsSnapshot: ["apple": params],
                    defaultParams: params, clusterConfig: .default, fusionConfig: .default,
                    colorFilter: nil, season: season, finalPointCloudIdentity: cloud.identity
                ))
                return try await ScanEvidenceSnapshot.freeze(snapshot: input, draft: staged.draft)
            },
            estimateYield: { snapshot in
                self.estimateCount += 1
                self.estimatedSnapshotIDs.append(snapshot.snapshot.id)
                self.estimatedEvidence.append(snapshot.identity)
                if self.shouldFailFirstEstimation && self.estimateCount == 1 {
                    throw CocoaError(.coderInvalidValue)
                }
                return await withCheckedContinuation { continuation in
                    self.estimateCompletions.append { result, _ in
                        let identity = self.resultEvidenceOverride?(snapshot.identity) ?? snapshot.identity
                        continuation.resume(returning: ScanEstimate(evidenceIdentity: identity, result: result))
                    }
                }
            },
            persistResult: { plan, receipt, estimate, _, _ in
                XCTAssertEqual(receipt.identity, estimate.evidenceIdentity)
                let draft = receipt.draft
                let result = estimate.result
                self.persistenceCount += 1
                self.persistedInputs.append((plan.id, draft.sourceFilename, result.yieldFinalKg))
                if self.shouldFailFirstPersistence && self.persistenceCount == 1 {
                    throw CocoaError(.fileWriteUnknown)
                }
                self.committedRecordCount += 1
                if self.shouldSuspendPersistence {
                    await withCheckedContinuation { self.persistenceContinuation = $0 }
                }
                self.completedPersistenceOperationCount += 1
                try ScanArchiveAccess.shared.withTransaction(at: draft.sourceURL) {
                    ScanArchiveAccess.shared.releaseDraft(draft)
                }
            },
            markCompleted: {
                self.markCompletedCount += 1
                self.setState(.completed)
            },
            refreshHistory: { self.historyRefreshCount += 1 },
            discardArtifacts: {
                self.discardedFilenames.append($0.sourceFilename)
                let draft = $0
                await Task.detached {
                    try? ScanArchiveAccess.shared.withTransaction(at: draft.sourceURL) {
                        ScanArchiveAccess.shared.releaseDraft(draft)
                    }
                }.value
                return .discarded
            }
        )
    }

    private static func stagedPointCloud(filename: String, context: ScanContext) -> StagedPointCloud {
        let signature = RendererSnapshotSignature(pointCount: 1, pointIndex: 1, voxelSize: 0.005,
                                                   confidenceThreshold: 1, pointBufferRevision: 1)
        let staged = StagedPointCloud(
            draft: DraftScan(sourceURL: URL(fileURLWithPath: "/test-fixtures/\(filename)"),
                             sourceSHA256: "fixture-digest",
                             fileIdentity: ScanSourceFileIdentity(device: 1, inode: 1),
                             ownershipID: UUID(),
                             captureIdentity: ScanCaptureIdentity(context: context, pointCloud: signature)),
            pointCloud: FinalPointCloud(
                identity: signature,
                points: [], inputSampleCount: 0, retainedSampleCount: 0,
                buildDuration: 0, estimatedPeakPayloadBytes: 0
            )
        )
        try? ScanArchiveAccess.shared.withTransaction(at: staged.draft.sourceURL) {
            ScanArchiveAccess.shared.registerDraft(staged.draft)
        }
        return staged
    }

    func setState(_ state: ScanLifecycleState) {
        snapshot = ScanLifecycleSnapshot(
            state: state,
            scanIdentity: snapshot.scanIdentity,
            generation: snapshot.generation + 1,
            interruptionCount: snapshot.interruptionCount,
            lastInterruptionTimestamp: snapshot.lastInterruptionTimestamp
        )
    }

    func releasePersistence() {
        persistenceContinuation?.resume()
        persistenceContinuation = nil
    }
}

final class ScanFinalizationWorkflowTests: XCTestCase {
    @MainActor
    func testProductionFinalizationUsesInjectedRepositoryAndHistoryCallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScanRepository(scansDirectory: directory)
        let dependencies = AppDependencies(scanRepository: repository)
        XCTAssertTrue(dependencies.scanRepository === repository)
        let coordinator = ScanCoordinator(calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let plan = makePlan()
        coordinator.startRecording(plan: plan)
        var refreshes = 0
        let production = ScanFinalizationOperations.production(coordinator: coordinator, repository: repository,
                                                               refreshHistory: { refreshes += 1 })
        let operations = operationsWithSyntheticCapture(
            production: production, coordinator: coordinator, repository: repository,
            filename: "production-injected.ply"
        )
        let workflow = ScanFinalizationWorkflow()
        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: operations)
        await waitUntil { workflow.phase == .completed }
        XCTAssertEqual(refreshes, 1)
        let source = try repository.pointCloudDestination(filename: "production-injected.ply")
        let record = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(record.summary.treeID, plan.treeID)
        XCTAssertEqual(record.summary.yieldKg, workflow.result?.yieldFinalKg)
        XCTAssertEqual(record.manifest?.scanID, "production-injected")
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .completed)
    }

    @MainActor
    func testRootFinalizationRefreshesInjectedHistoryWithoutCallerReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScanRepository(scansDirectory: directory)
        let dependencies = AppDependencies(scanRepository: repository)
        await dependencies.historyStore.reloadRecords()
        XCTAssertTrue(dependencies.historyStore.scanFiles.isEmpty)
        let coordinator = ScanCoordinator(calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let plan = makePlan()
        coordinator.startRecording(plan: plan)
        let operations = operationsWithSyntheticCapture(
            production: dependencies.finalizationOperations(coordinator: coordinator),
            coordinator: coordinator, repository: repository, filename: "root-finalization.ply"
        )
        let workflow = ScanFinalizationWorkflow()

        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: operations)
        await waitUntil { workflow.phase == .completed }
        await waitUntil { dependencies.historyStore.scanFiles.count == 1 }

        let source = try repository.pointCloudDestination(filename: "root-finalization.ply")
        let record = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(dependencies.historyStore.scanFiles, [record.summary])
        XCTAssertEqual(record.summary.yieldKg, workflow.result?.yieldFinalKg)
        XCTAssertEqual(record.manifest?.scanID, "root-finalization")
        XCTAssertNil(dependencies.historyStore.loadFailure)
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .completed)
    }

    @MainActor
    private func operationsWithSyntheticCapture(
        production: ScanFinalizationOperations,
        coordinator: ScanCoordinator,
        repository: ScanRepository,
        filename: String
    ) -> ScanFinalizationOperations {
        ScanFinalizationOperations(
            lifecycleSnapshot: production.lifecycleSnapshot,
            beginFinishing: production.beginFinishing,
            exportPointCloud: { plan, latitude, longitude in
                // Replace only the physical LiDAR boundary unavailable on Simulator.
                let context = ScanContext(scanID: coordinator.lifecycleSnapshot().scanIdentity, planID: plan.id)
                let signature = RendererSnapshotSignature(pointCount: 1, pointIndex: 1, voxelSize: 0.005, confidenceThreshold: 1)
                let points = [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)]
                let source = try repository.pointCloudDestination(filename: filename)
                let draft = try repository.stagePointCloud(to: source, captureIdentity: ScanCaptureIdentity(context: context, pointCloud: signature)) {
                    try PLYPointCloudWriter.write(points: points, treeID: plan.treeID, scanDate: "2026-09-28 00:00:00",
                                                  gpsLat: latitude, gpsLon: longitude, to: source)
                }
                return StagedPointCloud(draft: draft, pointCloud: FinalPointCloud(
                    identity: signature, points: points, inputSampleCount: 1, retainedSampleCount: 1,
                    buildDuration: 0, estimatedPeakPayloadBytes: 0
                ))
            },
            prepareSnapshot: production.prepareSnapshot,
            estimateYield: production.estimateYield,
            persistResult: production.persistResult,
            markCompleted: production.markCompleted,
            refreshHistory: production.refreshHistory,
            discardArtifacts: production.discardArtifacts
        )
    }

    @MainActor
    func testPreparedEvidenceFromAnotherSourceWithSameCaptureIsRejected() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        let original = harness.operations
        var otherDraft: DraftScan?
        let operations = ScanFinalizationOperations(
            lifecycleSnapshot: original.lifecycleSnapshot,
            beginFinishing: original.beginFinishing,
            exportPointCloud: original.exportPointCloud,
            prepareSnapshot: { season, staged in
                let prepared = try await original.prepareSnapshot(season, staged)
                let originalDraft = staged.draft
                let replacement = DraftScan(
                    sourceURL: originalDraft.sourceURL.deletingLastPathComponent().appendingPathComponent("other-source.ply"),
                    sourceSHA256: originalDraft.sourceSHA256, fileIdentity: originalDraft.fileIdentity,
                    ownershipID: UUID(), captureIdentity: originalDraft.captureIdentity
                )
                otherDraft = replacement
                try ScanArchiveAccess.shared.withTransaction(at: replacement.sourceURL) {
                    ScanArchiveAccess.shared.registerDraft(replacement)
                }
                return try await ScanEvidenceSnapshot.freeze(snapshot: prepared.snapshot, draft: replacement)
            },
            estimateYield: original.estimateYield,
            persistResult: original.persistResult,
            markCompleted: original.markCompleted,
            refreshHistory: original.refreshHistory,
            discardArtifacts: original.discardArtifacts
        )
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("original-source.ply")
        await waitUntil { workflow.retryAction == .estimateYield }
        XCTAssertEqual(harness.estimateCount, 0)
        XCTAssertEqual(harness.persistenceCount, 0)
        workflow.cancel()
        await waitUntil { workflow.cancellationSettlement != nil }
        if let otherDraft {
            try? ScanArchiveAccess.shared.withTransaction(at: otherDraft.sourceURL) {
                ScanArchiveAccess.shared.releaseDraft(otherDraft)
            }
        }
    }

    @MainActor
    func testSnapshotFromAnotherScanOrPlanCannotReachEstimation() async {
        for mismatch in ["scan", "plan"] {
            let workflow = ScanFinalizationWorkflow()
            let harness = ScanFinalizationTestHarness()
            let plan = makePlan()
            harness.preparedContextOverride = ScanContext(
                scanID: mismatch == "scan" ? UUID() : harness.snapshot.scanIdentity,
                planID: mismatch == "plan" ? UUID() : plan.id
            )
            workflow.finish(plan: plan, latitude: 0, longitude: 0, operations: harness.operations)
            await waitUntil { harness.exportCompletions.count == 1 }
            harness.exportCompletions[0]("mismatched-\(mismatch).ply")
            await waitUntil { workflow.retryAction == .estimateYield }
            XCTAssertEqual(harness.estimateCount, 0, mismatch)
            XCTAssertEqual(harness.persistenceCount, 0, mismatch)
            workflow.cancel()
            await waitUntil { workflow.cancellationSettlement != nil }
        }
    }

    @MainActor
    func testEstimateFromAnotherObservationSnapshotIsRejectedAndCanRetryOriginalInput() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        harness.resultEvidenceOverride = { identity in
            ScanEvidenceIdentity(capture: identity.capture, snapshotID: UUID(),
                                 sourceOwnershipID: identity.sourceOwnershipID, sourceSHA256: identity.sourceSHA256)
        }
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: harness.operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("foreign-result.ply")
        await waitUntil { harness.estimateCompletions.count == 1 }
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 99), nil)
        await waitUntil { workflow.retryAction == .estimateYield }
        XCTAssertEqual(harness.persistenceCount, 0)
        XCTAssertNil(workflow.result)
        XCTAssertNotNil(workflow.estimationSnapshot)
        harness.resultEvidenceOverride = nil
        workflow.retry()
        await waitUntil { harness.estimateCompletions.count == 2 }
        harness.estimateCompletions[1](YieldResult(yieldFinalKg: 3), nil)
        await waitUntil { workflow.phase == .completed }
        XCTAssertEqual(harness.preparationCount, 1)
        XCTAssertEqual(harness.estimatedEvidence[0], harness.estimatedEvidence[1])
        XCTAssertEqual(harness.persistedInputs.map(\.2), [3])
    }

    @MainActor
    func testProductionSnapshotEstimateAndRepositoryPreserveOneEvidenceIdentity() async throws {
        let plan = makePlan()
        let coordinator = ScanCoordinator(calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.startRecording(plan: plan)
        XCTAssertTrue(coordinator.beginFinishingScan())
        let context = ScanContext(scanID: coordinator.lifecycleSnapshot().scanIdentity, planID: plan.id)
        let signature = RendererSnapshotSignature(pointCount: 1, pointIndex: 1, voxelSize: 0.005,
                                                   confidenceThreshold: 1, pointBufferRevision: 7)
        let points = [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)]
        let cloud = FinalPointCloud(identity: signature, points: points, inputSampleCount: 1,
                                   retainedSampleCount: 1, buildDuration: 0, estimatedPeakPayloadBytes: 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("identity-integration.ply")
        let draft = try ScanRepository.shared.stagePointCloud(
            to: source, captureIdentity: ScanCaptureIdentity(context: context, pointCloud: signature)
        ) {
            try PLYPointCloudWriter.write(points: points, treeID: plan.treeID, scanDate: "2026-09-28 00:00:00",
                                          gpsLat: 0, gpsLon: 0, to: source)
        }
        let input = try await coordinator.prepareYieldEstimationSnapshot(season: plan.season, finalPointCloud: cloud)
        XCTAssertEqual(input.context, context)
        XCTAssertEqual(input.input.points.count, points.count)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: input, draft: draft)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        XCTAssertEqual(estimate.evidenceIdentity, frozen.identity)
        XCTAssertEqual(estimate.evidenceIdentity.snapshotID, input.id)
        let assessment = ScanAssessment(receipt: frozen.receipt, estimate: estimate,
                                        treeID: plan.treeID, fruitType: plan.fruitConfiguration.selectedCategory.rawValue,
                                        scanDate: Date(timeIntervalSince1970: 1), gpsLat: 0, gpsLon: 0, includeCSV: true)
        let service = ScanResultExportService(scansDirectory: directory)
        let otherSnapshot = ScanYieldEstimationController.Snapshot(context: context, input: input.input)
        do {
            _ = try await ScanEvidenceSnapshot.freeze(snapshot: otherSnapshot, draft: draft)
            XCTFail("A different observation snapshot must not replace the first binding")
        } catch {
            XCTAssertTrue(error is ScanEvidenceError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["identity-integration.ply"])
        let committed = try ScanRepository.shared.commit(assessment, using: service)
        let manifest = try XCTUnwrap(ScanLegacyArchiveCodec.readManifest(at: committed.manifestURL))
        XCTAssertEqual(manifest.scanID, "identity-integration")
        XCTAssertEqual(manifest.sourcePLYSHA256, frozen.identity.sourceSHA256)
        let verified = try XCTUnwrap(ScanRepository.shared.readVerifiedRecord(at: source))
        XCTAssertEqual(verified.summary.yieldKg, estimate.result.yieldFinalKg)
        XCTAssertEqual(verified.manifest?.sourcePLYSHA256, draft.sourceSHA256)
        let retried = try ScanRepository.shared.commit(assessment, using: service)
        XCTAssertEqual(retried.exportRevision, committed.exportRevision)
    }

    @MainActor
    func testCancelPropagatesToTheInFlightExportTask() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        let original = harness.operations
        var started = false
        var cancelled = false
        let operations = ScanFinalizationOperations(
            lifecycleSnapshot: original.lifecycleSnapshot,
            beginFinishing: original.beginFinishing,
            exportPointCloud: { _, _, _ in
                started = true
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw PointCloudExportError.emptyPointCloud
                } catch {
                    cancelled = Task.isCancelled
                    throw error
                }
            },
            prepareSnapshot: original.prepareSnapshot,
            estimateYield: original.estimateYield,
            persistResult: original.persistResult,
            markCompleted: original.markCompleted,
            refreshHistory: original.refreshHistory,
            discardArtifacts: original.discardArtifacts
        )
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: operations)
        await waitUntil { started }
        workflow.cancel()
        await waitUntil { cancelled }
        XCTAssertEqual(workflow.phase, .cancelled)
        XCTAssertEqual(harness.estimateCount, 0)
        XCTAssertEqual(harness.discardedFilenames, [])
    }

    @MainActor
    func testLateExportSettlesOldScanWithoutChangingNewScan() async {
        let workflow = ScanFinalizationWorkflow()
        let original = ScanFinalizationTestHarness()
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: original.operations)
        await waitUntil { original.exportCompletions.count == 1 }
        workflow.cancel()
        workflow.resetForNewScan()
        let replacement = ScanFinalizationTestHarness()
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: replacement.operations)
        await waitUntil { replacement.exportCompletions.count == 1 }
        original.exportCompletions[0]("late-original.ply")
        await waitUntil { original.historyRefreshCount == 1 }
        XCTAssertEqual(original.discardedFilenames, ["late-original.ply"])
        XCTAssertEqual(workflow.scanIdentity, replacement.snapshot.scanIdentity)
        XCTAssertEqual(workflow.phase, .exportingPointCloud)
        XCTAssertNil(workflow.filename)
        XCTAssertNil(workflow.cancellationSettlement)
        workflow.cancel()
        replacement.exportCompletions[0](nil)
    }

    @MainActor
    func testDuplicateFinishIsRejectedAndFailedExportCanRetryWithSameScanIdentity() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        let plan = makePlan()
        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: harness.operations)
        let scanIdentity = workflow.scanIdentity

        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: harness.operations)
        await waitUntil { harness.exportCount == 1 }
        XCTAssertEqual(harness.exportCount, 1)
        XCTAssertTrue(workflow.isWorking)

        harness.exportCompletions[0](nil)
        await waitUntil { workflow.retryAction == .exportPointCloud }
        guard case .failed(.pointCloudExport) = workflow.phase else {
            XCTFail("Expected the PLY export failure to remain retryable")
            return
        }

        workflow.retry()
        await waitUntil { harness.exportCount == 2 }
        XCTAssertEqual(harness.exportCount, 2)
        XCTAssertEqual(workflow.scanIdentity, scanIdentity)
        workflow.cancel()
        harness.exportCompletions[1]("late.ply")
        await waitUntil { workflow.cancellationSettlement != nil }

        XCTAssertEqual(workflow.phase, .cancelled)
        XCTAssertEqual(harness.estimateCount, 0)
        XCTAssertEqual(harness.discardedFilenames, ["late.ply"])
    }

    @MainActor
    func testPersistenceRetryReusesResultAndRefreshesHistoryOnlyAfterCommit() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        harness.shouldFailFirstPersistence = true
        let plan = makePlan()
        let expected = YieldResult(yieldFinalKg: 3.25)
        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: harness.operations)
        let scanIdentity = workflow.scanIdentity

        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("tree_scan.ply")
        await waitUntil { harness.estimateCompletions.count == 1 }
        harness.estimateCompletions[0](expected, nil)
        await waitUntil { workflow.phase.isPersistenceFailure }

        XCTAssertEqual(workflow.scanIdentity, scanIdentity)
        XCTAssertEqual(workflow.filename, "tree_scan.ply")
        XCTAssertEqual(workflow.result?.yieldFinalKg, expected.yieldFinalKg)
        XCTAssertEqual(harness.historyRefreshCount, 0)
        XCTAssertEqual(workflow.retryAction, .persistResult)
        XCTAssertNil(workflow.stagedPointCloud, "Persistence retry must not retain the point cloud")
        XCTAssertNil(workflow.estimationSnapshot, "Persistence retry only needs the completed result")

        workflow.retry()
        await waitUntil { workflow.phase == .completed }

        XCTAssertEqual(harness.exportCount, 1)
        XCTAssertEqual(harness.estimateCount, 1)
        XCTAssertEqual(harness.persistenceCount, 2)
        XCTAssertEqual(harness.persistedInputs.map(\.0), [plan.id, plan.id])
        XCTAssertEqual(harness.persistedInputs.map(\.1), ["tree_scan.ply", "tree_scan.ply"])
        XCTAssertEqual(harness.persistedInputs.map(\.2), [expected.yieldFinalKg, expected.yieldFinalKg])
        XCTAssertEqual(harness.markCompletedCount, 1)
        XCTAssertEqual(harness.historyRefreshCount, 1)

        workflow.cancel()
        XCTAssertEqual(workflow.phase, .completed)
        XCTAssertEqual(harness.discardedFilenames, [])
    }

    @MainActor
    func testCancelRacingWithCommittedPersistencePreservesTheRecord() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        harness.shouldSuspendPersistence = true
        let plan = makePlan()
        workflow.finish(plan: plan, latitude: 1, longitude: 2, operations: harness.operations)

        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("committed_scan.ply")
        await waitUntil { harness.estimateCompletions.count == 1 }
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 2.5), nil)
        await waitUntil { harness.persistenceCount == 1 }

        workflow.cancel()
        harness.releasePersistence()
        await waitUntil { harness.completedPersistenceOperationCount == 1 }

        XCTAssertEqual(workflow.phase, .cancelled)
        XCTAssertEqual(harness.committedRecordCount, 1)
        XCTAssertEqual(harness.discardedFilenames, [])
        XCTAssertEqual(harness.markCompletedCount, 0)
        XCTAssertEqual(harness.historyRefreshCount, 1)
        XCTAssertEqual(workflow.cancellationSettlement, .preservedCommitted)
    }

    @MainActor
    func testCancelledFailedPersistenceSettlesTheDraft() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        let original = harness.operations
        var pending: CheckedContinuation<Void, Error>?
        let operations = ScanFinalizationOperations(
            lifecycleSnapshot: original.lifecycleSnapshot,
            beginFinishing: original.beginFinishing,
            exportPointCloud: original.exportPointCloud,
            prepareSnapshot: original.prepareSnapshot,
            estimateYield: original.estimateYield,
            persistResult: { _, _, _, _, _ in
                try await withCheckedThrowingContinuation { pending = $0 }
            },
            markCompleted: original.markCompleted,
            refreshHistory: original.refreshHistory,
            discardArtifacts: original.discardArtifacts
        )
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("cancelled_failure.ply")
        await waitUntil { harness.estimateCount == 1 }
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 2.5), nil)
        await waitUntil { pending != nil }
        workflow.cancel()
        pending?.resume(throwing: CocoaError(.fileWriteUnknown))
        await waitUntil { workflow.cancellationSettlement != nil }
        XCTAssertEqual(workflow.phase, .cancelled)
        XCTAssertEqual(workflow.cancellationSettlement, .discarded)
        XCTAssertEqual(harness.discardedFilenames, ["cancelled_failure.ply"])
        XCTAssertEqual(harness.historyRefreshCount, 1)
    }

    @MainActor
    func testEstimationFailureRetriesTheSameFrozenInputWithoutReexportOrRedrain() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        harness.shouldFailFirstEstimation = true
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: harness.operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("estimate_retry.ply")
        await waitUntil { workflow.retryAction == .estimateYield }
        XCTAssertFalse(workflow.isWorking)
        XCTAssertNotNil(workflow.stagedPointCloud)
        XCTAssertNotNil(workflow.estimationSnapshot)
        workflow.retry()
        await waitUntil { harness.estimateCompletions.count == 1 }
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 2.75), nil)
        await waitUntil { workflow.phase == .completed }
        XCTAssertEqual(harness.exportCount, 1)
        XCTAssertEqual(harness.preparationCount, 1)
        XCTAssertEqual(harness.estimateCount, 2)
        XCTAssertEqual(Set(harness.estimatedSnapshotIDs).count, 1)
        XCTAssertEqual(harness.persistedInputs.first?.2, 2.75)
    }

    @MainActor
    func testUnavailableSnapshotHasAnExplicitRetryableFailure() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        harness.shouldFailPreparation = true
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: harness.operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("snapshot_retry.ply")
        await waitUntil { workflow.retryAction == .estimateYield }
        XCTAssertFalse(workflow.isWorking)
        XCTAssertEqual(harness.estimateCount, 0)
        XCTAssertEqual(harness.persistenceCount, 0)
        workflow.cancel()
        await waitUntil { workflow.cancellationSettlement != nil }
        XCTAssertEqual(harness.discardedFilenames, ["snapshot_retry.ply"])
    }

    @MainActor
    func testCancelledEstimationCannotPersistLateResult() async {
        let workflow = ScanFinalizationWorkflow()
        let harness = ScanFinalizationTestHarness()
        workflow.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: harness.operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("cancelled_estimate.ply")
        await waitUntil { harness.estimateCompletions.count == 1 }
        workflow.cancel()
        XCTAssertNil(workflow.stagedPointCloud)
        XCTAssertNil(workflow.estimationSnapshot)
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 9), nil)
        await waitUntil { workflow.cancellationSettlement != nil }
        XCTAssertEqual(workflow.phase, .cancelled)
        XCTAssertEqual(harness.persistenceCount, 0)
        XCTAssertNil(workflow.result)
    }

    @MainActor
    func testCancelledWorkflowIsReleasedWhileEstimatorIsStillSuspended() async {
        var workflow: ScanFinalizationWorkflow? = ScanFinalizationWorkflow()
        weak let weakWorkflow = workflow
        let harness = ScanFinalizationTestHarness()
        workflow?.finish(plan: makePlan(), latitude: 0, longitude: 0, operations: harness.operations)
        await waitUntil { harness.exportCompletions.count == 1 }
        harness.exportCompletions[0]("released_estimate.ply")
        await waitUntil { harness.estimateCompletions.count == 1 }
        workflow?.cancel()
        workflow = nil
        XCTAssertNil(weakWorkflow)
        harness.estimateCompletions[0](YieldResult(yieldFinalKg: 9), nil)
        await waitUntil { harness.discardedFilenames == ["released_estimate.ply"] }
        XCTAssertEqual(harness.persistenceCount, 0)
    }

    @MainActor
    private func makePlan() -> ScanPlan {
        ScanPlanFactory(
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] },
            modelIdentityProvider: FixedScanModelIdentityProvider(identity: .verified("model-a"))
        ).makePlan(
            treeID: "T-finalization",
            season: .mature,
            selectedCategory: .apple,
            renderer: nil
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for workflow state")
    }
}

private extension ScanFinalizationWorkflow.Phase {
    var isPersistenceFailure: Bool {
        guard case .failed(.resultPersistence(_)) = self else { return false }
        return true
    }
}

@MainActor
final class ScanLiveFruitCountTests: XCTestCase {
    func testLiveCountExcludesOtherFruitCategories() async throws {
        let (coordinator, _) = try makeCoordinator()
        await coordinator.appendObservations(observations(category: .apple) + observations(category: .pear),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 1,
            "A stable pear must not enter an apple scan's confirmed count")
    }

    func testLiveCountKeepsScanConfigurationWhenSettingsChange() async throws {
        let (coordinator, settings) = try makeCoordinator()
        await coordinator.appendObservations(observations(),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 1)
        settings.fruitType = FruitCategory.grape.rawValue
        settings.qualityPreset = "高"
        settings.minConfidence = 0.99
        coordinator.loadSettings()
        XCTAssertEqual(settings.fruitType, FruitCategory.grape.rawValue)
        XCTAssertEqual(coordinator.activeFruitConfiguration?.selectedCategory, .apple)
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: coordinator.imageDetector.configSnapshot()), 1,
            "Changing settings cannot change the already captured scan's cluster geometry")
    }

    func testLiveCountUsesPlanClusterSizeLimit() async throws {
        var cluster = ClusterConfig.default
        cluster.maxDiameter = 0.04
        let (coordinator, _) = try makeCoordinator(cluster: cluster)
        await coordinator.appendObservations(observations(),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 0,
            "A 4 cm candidate is outside the apple's 8 cm size prior and allowed tolerance")
    }

    func testLiveCountUsesPlanFusionDistanceLimits() async throws {
        var experiment = FruitScanExperimentConfig.default
        experiment.fusion.nearestCandidateDistance = 0.01
        experiment.fusion.relaxedDistanceMultiplier = 0.1
        experiment.fusion.relaxedDistanceCap = 0.02
        let (coordinator, _) = try makeCoordinator(experiment: experiment)
        // The projection lies 6 cm behind the ROI candidate. Default 15 cm
        // matching accepts it, while this plan's 1 cm gate must reject it.
        await coordinator.appendObservations(observations(projectionDepth: 2.06),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 0)
    }

    func testLiveCountKeepsStricterPlanConfidenceThanCallerConfiguration() async throws {
        var fusion = FruitScanConfig.default
        fusion.minConfidence = 0.96
        let (coordinator, _) = try makeCoordinator(fusion: fusion)
        await coordinator.appendObservations(observations(),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 0,
            "An older detector snapshot cannot loosen the active scan's confidence gate")
    }

    func testNewerOtherCategoryFramesStillExpireOldTargetEvidence() async throws {
        let (coordinator, _) = try makeCoordinator()
        await coordinator.appendObservations(observations() + observations(category: .pear, timestamp: 30),
            evidenceToken: try XCTUnwrap(coordinator.capturedEvidenceToken()))
        XCTAssertEqual(coordinator.confirmedLiveFruitCount(detectorConfig: .default), 0,
            "Filtering pears must not make a 20-second-old apple track recent again")
    }

    private func makeCoordinator(
        cluster: ClusterConfig = .default,
        fusion: FruitScanConfig = .default,
        experiment: FruitScanExperimentConfig = .default
    ) throws -> (ScanCoordinator, SettingsStore) {
        let suite = "LiveCountPlan-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = FruitCategory.apple.rawValue
        settings.qualityPreset = "中"
        settings.clusterMinPoints = 3
        let parameters = FruitVarietyParams(category: .apple)
        let fruitConfiguration = ScanFruitConfiguration(selectedCategory: .apple,
            parametersSnapshot: ["apple": parameters], defaultParams: parameters,
            clusterConfig: cluster, fusionConfig: fusion, colorFilter: FruitCategory.apple.colorFilter,
            calibrationCorrection: .neutral, calibrationWarning: nil, calibrationContext: nil,
            modelIdentity: .modelMissing)
        let plan = ScanPlan(treeID: "live-count-fixture", season: .mature, fruitConfiguration: fruitConfiguration,
            rendererSettings: RendererScanSettings(store: settings, particleCapacity: 100), resourceBudget: .default,
            requestedCameraResolution: "1080p", requestedCameraFrameRate: "60fps", autoExportCSV: false,
            modelIdentity: .modelMissing, experimentConfiguration: experiment)
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })
        addTeardownBlock {
            await MainActor.run {
                coordinator.teardown()
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        }
        coordinator.startRecording(plan: plan)
        return (coordinator, settings)
    }

    private func observations(
        category: FruitCategory = .apple,
        projectionDepth: Float = 2,
        timestamp: TimeInterval = 10
    ) -> [Observation] {
        // A fixed 9 x 9 grid spans 4.8 cm at 2 m. It represents one compact
        // ROI candidate near (0, 0, -2), observed twice more than 0.35 s apart.
        let samples = (0..<9).flatMap { row in
            (0..<9).map { column in
                ObservationDepthSample(normalizedImageX: 0.488 + (Float(column) + 0.5) * 0.024 / 9,
                    normalizedImageY: 0.488 + (Float(row) + 0.5) * 0.024 / 9,
                    depthMeters: 2, row: row, column: column)
            }
        }
        return (0..<2).map { index in
            Observation(id: UUID(), frameID: FrameID(), category: category,
                boundingBox: CGRect(x: 0.488, y: 0.488, width: 0.024, height: 0.024), confidence: 0.9,
                timestamp: timestamp + Double(index) * 0.6, cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: simd_float3x3(SIMD3<Float>(1000, 0, 0), SIMD3<Float>(0, 1000, 0), SIMD3<Float>(500, 500, 1)),
                imageSize: CGSize(width: 1000, height: 1000), coordinateConvention: .visionNormalizedLowerLeft,
                depthConfidenceProvenance: .available, hasDepthMap: true, roiDepthSamples: samples,
                projectionDepthSamples: Array(repeating: projectionDepth, count: 81), rejectionReasons: [])
        }
    }
}
