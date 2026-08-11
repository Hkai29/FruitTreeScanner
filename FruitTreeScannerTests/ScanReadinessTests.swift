import XCTest
import ARKit
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
    func testFailureRestartResetsSessionBeforeOpeningReliableEvidence() {
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
        XCTAssertTrue(coordinator.acceptsReliableEvidence())

        let restarted = coordinator.lifecycleSnapshot()
        XCTAssertEqual(restarted.state, .recording)
        XCTAssertNotEqual(restarted.scanIdentity, original.scanIdentity)
        XCTAssertEqual(restarted.interruptionCount, 0)
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

    func testRepeatedRestartDoesNotResetActiveReplacementScan() {
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
