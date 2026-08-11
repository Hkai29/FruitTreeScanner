import XCTest
import ARKit
import CoreVideo
import Metal
import SceneKit
import simd
@testable import FruitTreeScanner

final class PointCloudProcessingTests: XCTestCase {

    func testPointCloudColorModesAlwaysUseOriginalPLYColors() throws {
        let vertices = [
            SCNVector3(0, 0, 0),
            SCNVector3(0, 1, 0),
        ]
        let colors = [
            PointCloudColor(r: 0.8, g: 0.1, b: 0.1, a: 1),
            PointCloudColor(r: 0.1, g: 0.8, b: 0.1, a: 1),
        ]
        let node = try XCTUnwrap(
            SceneKitPointCloudGeometry.makePointCloudNode(
                vertices: vertices,
                colors: colors,
                pointSize: 3
            )
        )

        XCTAssertTrue(
            SceneKitPointCloudColorRenderer.apply(
                colorMode: .height,
                to: node,
                sourceVertices: vertices,
                sourceColors: colors
            )
        )
        var renderedColors = try renderedPointCloudColors(from: node)
        assertColor(renderedColors[0], r: 0.24, g: 0.28, b: 1)
        assertColor(renderedColors[1], r: 1, g: 0.28, b: 0.3)

        XCTAssertTrue(
            SceneKitPointCloudColorRenderer.apply(
                colorMode: .fruit,
                to: node,
                sourceVertices: vertices,
                sourceColors: colors
            )
        )

        renderedColors = try renderedPointCloudColors(from: node)
        assertColor(renderedColors[0], r: 1, g: 0.58, b: 0.04)
        assertColor(renderedColors[1], r: 0.042, g: 0.336, b: 0.042)

        XCTAssertTrue(
            SceneKitPointCloudColorRenderer.apply(
                colorMode: .uniform,
                to: node,
                sourceVertices: vertices,
                sourceColors: colors
            )
        )
        XCTAssertTrue(
            SceneKitPointCloudColorRenderer.apply(
                colorMode: .density,
                to: node,
                sourceVertices: vertices,
                sourceColors: colors
            )
        )

        renderedColors = try renderedPointCloudColors(from: node)
        assertColor(renderedColors[0], r: 0.31, g: 0.413_333, b: 0.526_667)
    }

    func testPointCloudColorRendererRejectsMismatchedSourceWithoutChangingGeometry() throws {
        let vertices = [SCNVector3(0, 0, 0)]
        let colors = [PointCloudColor(r: 0.8, g: 0.1, b: 0.1, a: 1)]
        let node = try XCTUnwrap(
            SceneKitPointCloudGeometry.makePointCloudNode(
                vertices: vertices,
                colors: colors,
                pointSize: 3
            )
        )
        let originalGeometry = try XCTUnwrap(node.geometry)

        XCTAssertFalse(
            SceneKitPointCloudColorRenderer.apply(
                colorMode: .fruit,
                to: node,
                sourceVertices: vertices,
                sourceColors: []
            )
        )
        XCTAssertTrue(node.geometry === originalGeometry)
    }

    func testTreeIdentifierPolicyRejectsPathAndHeaderInjectionCharacters() {
        XCTAssertTrue(TreeIdentifierPolicy.isValid("T001"))
        XCTAssertTrue(TreeIdentifierPolicy.isValid("三号地块 12-A"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid(""))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("../escape"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A/B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A\\B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A:B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A\ncomment gps_lat 90"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid(String(repeating: "A", count: 65)))
    }

    func testTreeIdentifierPolicyClassifiesValidationIssuesWithoutChangingLegacyMessages() {
        XCTAssertEqual(TreeIdentifierPolicy.validationIssue(for: "  "), .empty)
        XCTAssertEqual(
            TreeIdentifierPolicy.validationIssue(for: String(repeating: "A", count: 65)),
            .tooLong(maximumCharacterCount: 64)
        )
        XCTAssertEqual(TreeIdentifierPolicy.validationIssue(for: ".."), .pathMarker)
        XCTAssertEqual(TreeIdentifierPolicy.validationIssue(for: "A/B"), .forbiddenCharacters)
        XCTAssertNil(TreeIdentifierPolicy.validationIssue(for: "三号地块 12-A"))

        XCTAssertEqual(TreeIdentifierPolicy.validationError(for: "  "), "请输入果树编号")
        XCTAssertEqual(
            TreeIdentifierPolicy.validationError(for: String(repeating: "A", count: 65)),
            "编号最多 64 个字符"
        )
        XCTAssertEqual(TreeIdentifierPolicy.validationError(for: ".."), "编号不能使用路径标记")
        XCTAssertEqual(TreeIdentifierPolicy.validationError(for: "A/B"), "编号不能包含 /、\\、: 或换行")
    }

    func testTreeIdentifierPolicyMakesBoundedSafeFileComponent() {
        let component = TreeIdentifierPolicy.safeFileComponent(
            from: " ../果园 A/B:\n" + String(repeating: "树", count: 80)
        )

        XCTAssertFalse(component.isEmpty)
        XCTAssertFalse(component.contains("/"))
        XCTAssertFalse(component.contains("\\"))
        XCTAssertFalse(component.contains(":"))
        XCTAssertFalse(component.contains("\n"))
        XCTAssertLessThanOrEqual(component.utf8.count, 80)
    }

    func testTreeFilenameIsSafeAndUniqueForSameTimestamp() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let first = makeTreeFileName(
            treeID: "../Tree/A",
            lat: 35.1,
            lon: 139.2,
            date: date,
            uniqueSuffix: "ABCDEF123456"
        )
        let second = makeTreeFileName(
            treeID: "../Tree/A",
            lat: 35.1,
            lon: 139.2,
            date: date,
            uniqueSuffix: "654321FEDCBA"
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(first))
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(second))
        XCTAssertFalse(LocalFileStorage.isSafeLeafFilename("../escape.ply"))
        XCTAssertFalse(LocalFileStorage.isSafeLeafFilename("nested/scan.ply"))
        XCTAssertTrue(first.hasSuffix("_lat35.1000_lon139.2000.ply"))
    }

    func testStableDataFormattingUsesPOSIXDecimalSeparator() {
        XCTAssertEqual(StableDataFormatting.decimal(35.1, precision: 4), "35.1000")
        XCTAssertEqual(StableDataFormatting.decimal(-45.987654321, precision: 6), "-45.987654")
    }

    func testStableDataFormattingUsesGregorianDateOutput() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let formatter = StableDataFormatting.dateFormatter(
            dateFormat: "yyyyMMdd_HHmmss",
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(formatter.string(from: date), "20250615_150640")
    }

    func testHorizontalAngleCoverageDistinguishesSingleSideFromFullRing() {
        var singleSide = Set<RendererVoxelKey>()
        var fullRing = Set<RendererVoxelKey>()
        for i in 0..<120 {
            let narrowAngle = (-Float.pi / 8) + Float(i) / 119.0 * (Float.pi / 4)
            singleSide.insert(voxelKey(angle: narrowAngle, radius: 20))

            let fullAngle = Float(i) / 120.0 * 2 * Float.pi
            fullRing.insert(voxelKey(angle: fullAngle, radius: 20))
        }

        let singleSideCoverage = RendererDepthCoverage.estimateHorizontalAngleCoverage(from: singleSide)
        let fullRingCoverage = RendererDepthCoverage.estimateHorizontalAngleCoverage(from: fullRing)

        XCTAssertLessThan(singleSideCoverage, 0.35)
        XCTAssertGreaterThan(fullRingCoverage, 0.85)
    }

    func testHorizontalAngleUniformityPenalizesSkewedFullRing() {
        var uniformRing = Set<RendererVoxelKey>()
        var skewedRing = Set<RendererVoxelKey>()

        for bin in 0..<36 {
            let angle = Float(bin) / 36.0 * 2 * Float.pi
            for y in 0..<4 {
                uniformRing.insert(voxelKey(angle: angle, radius: 24, y: Int32(y)))
            }
            for y in 0..<2 {
                skewedRing.insert(voxelKey(angle: angle, radius: 24, y: Int32(y)))
            }
        }

        for y in 2..<82 {
            skewedRing.insert(voxelKey(angle: 0, radius: 24, y: Int32(y)))
            skewedRing.insert(voxelKey(angle: Float.pi, radius: 24, y: Int32(y)))
        }

        let uniformity = RendererDepthCoverage.estimateHorizontalAngleUniformity(from: uniformRing)
        let skewedUniformity = RendererDepthCoverage.estimateHorizontalAngleUniformity(from: skewedRing)

        XCTAssertGreaterThan(uniformity, 0.95)
        XCTAssertLessThan(skewedUniformity, uniformity)
        XCTAssertLessThan(skewedUniformity, 0.75)
        XCTAssertGreaterThan(
            RendererDepthCoverage.estimateHorizontalAngleCoverage(from: skewedRing),
            0.85,
            "该指标应补充覆盖范围，避免全角度有点但分布高度不均时误判完成"
        )
    }

    func testOppositeSideCoverageUsesCameraFacingDirection() {
        var singleSide = Set<RendererCameraRegionKey>()
        var pairedSides = Set<RendererCameraRegionKey>()

        for x in 0..<8 {
            singleSide.insert(cameraRegion(x: x, forwardX: 10, forwardZ: 0))
            pairedSides.insert(cameraRegion(x: x, forwardX: 10, forwardZ: 0))
        }
        for x in 8..<16 {
            pairedSides.insert(cameraRegion(x: x, forwardX: -10, forwardZ: 0))
        }

        let singleSideScore = RendererDepthCoverage.estimateOppositeSideCoverage(from: singleSide)
        let pairedSideScore = RendererDepthCoverage.estimateOppositeSideCoverage(from: pairedSides)

        XCTAssertLessThan(singleSideScore, 0.20)
        XCTAssertGreaterThan(pairedSideScore, 0.85)
    }

    func testVerticalCoverageDistinguishesSingleLayerFromFullCanopyHeight() {
        var singleLayer = Set<RendererVoxelKey>()
        var fullHeight = Set<RendererVoxelKey>()

        for x in -4...4 {
            for z in -4...4 {
                singleLayer.insert(RendererVoxelKey(x: Int32(x), y: 4, z: Int32(z)))
                for y in 0...11 {
                    fullHeight.insert(RendererVoxelKey(x: Int32(x), y: Int32(y), z: Int32(z)))
                }
            }
        }

        let singleLayerCoverage = RendererDepthCoverage.estimateVerticalCoverage(from: singleLayer)
        let fullHeightCoverage = RendererDepthCoverage.estimateVerticalCoverage(from: fullHeight)

        XCTAssertLessThan(singleLayerCoverage, 0.25)
        XCTAssertGreaterThan(fullHeightCoverage, 0.85)
    }

    func testRendererMotionGateUsesPaperFiveCentimeterTranslationThreshold() {
        let base = matrix_identity_float4x4
        var belowThreshold = base
        belowThreshold.columns.3.x = Renderer.cameraTranslationThresholdMeters * 0.98
        var atThreshold = base
        atThreshold.columns.3.x = Renderer.cameraTranslationThresholdMeters

        XCTAssertEqual(Renderer.cameraTranslationThresholdMeters, 0.05, accuracy: 0.0001)
        XCTAssertFalse(
            Renderer.shouldAccumulateCameraMotion(
                currentTransform: belowThreshold,
                lastTransform: base,
                currentPointCount: 10_000,
                rotationCosineThreshold: cos(Renderer.cameraRotationThresholdDegrees * Float.degreesToRadian),
                translationSquaredThreshold: Renderer.cameraTranslationThresholdSquared
            ),
            "小于 5cm 的平移帧应被视为冗余，不再累积点云"
        )
        XCTAssertTrue(
            Renderer.shouldAccumulateCameraMotion(
                currentTransform: atThreshold,
                lastTransform: base,
                currentPointCount: 10_000,
                rotationCosineThreshold: cos(Renderer.cameraRotationThresholdDegrees * Float.degreesToRadian),
                translationSquaredThreshold: Renderer.cameraTranslationThresholdSquared
            ),
            "达到 5cm 平移时应允许累积新视角点云"
        )
        XCTAssertTrue(
            Renderer.shouldAccumulateCameraMotion(
                currentTransform: belowThreshold,
                lastTransform: base,
                currentPointCount: 0,
                rotationCosineThreshold: cos(Renderer.cameraRotationThresholdDegrees * Float.degreesToRadian),
                translationSquaredThreshold: Renderer.cameraTranslationThresholdSquared
            ),
            "首帧没有历史点云时仍应允许累积"
        )
    }

    func testSparseOutdoorCanopyDepthQualityIsAcceptedWithoutAcceptingEmptyDepth() {
        let sparseCanopy = RendererDepthQuality(
            validSampleCount: 4,
            totalSampleCount: 81,
            medianDepth: 2.4
        )
        let belowMinimum = RendererDepthQuality(
            validSampleCount: 3,
            totalSampleCount: 81,
            medianDepth: 2.4
        )

        XCTAssertTrue(RendererDepthCoverage.acceptsCaptureDepthQuality(sparseCanopy))
        XCTAssertFalse(RendererDepthCoverage.acceptsCaptureDepthQuality(belowMinimum))
        XCTAssertFalse(
            RendererDepthCoverage.acceptsCaptureDepthQuality(
                RendererDepthQuality(validSampleCount: 0, totalSampleCount: 81, medianDepth: 0)
            )
        )
    }

    func testDepthQualitySamplingCoversReliableOuterFrameBands() throws {
        let depthMap = try makeDepthMap(width: 70, height: 70) { _, row in
            row < 10 || row >= 60 ? 2.0 : 0
        }
        let confidenceMap = try makeConfidenceMap(width: 70, height: 70, value: 2)

        let quality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: confidenceMap,
            minDepth: 0.5,
            maxDepth: 5,
            confidenceThreshold: 2
        )

        XCTAssertEqual(quality.validSampleCount, 18)
        XCTAssertEqual(quality.totalSampleCount, 81)
        XCTAssertEqual(quality.validRatio, 18.0 / 81.0, accuracy: 0.0001)
        XCTAssertTrue(RendererDepthCoverage.acceptsCaptureDepthQuality(quality))
        XCTAssertEqual(quality.medianDepth, 2, accuracy: 0.0001)
    }

    func testDepthQualitySamplingRejectsLowConfidenceOuterFrameBands() throws {
        let depthMap = try makeDepthMap(width: 70, height: 70) { _, row in
            row < 10 || row >= 60 ? 2.0 : 0
        }
        let confidenceMap = try makeConfidenceMap(width: 70, height: 70, value: 1)

        let quality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: confidenceMap,
            minDepth: 0.5,
            maxDepth: 5,
            confidenceThreshold: 2
        )

        XCTAssertEqual(quality.validSampleCount, 0)
        XCTAssertEqual(quality.validRatio, 0)
        XCTAssertEqual(quality.medianDepth, 0)
    }

    func testDepthQualitySamplingRejectsInvalidOuterFrameDepth() throws {
        let depthMap = try makeDepthMap(width: 70, height: 70) { column, row in
            if row < 10 {
                return .nan
            }
            if row >= 60 {
                return column.isMultiple(of: 2) ? .infinity : 0
            }
            return 0
        }
        let confidenceMap = try makeConfidenceMap(width: 70, height: 70, value: 2)

        let quality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: confidenceMap,
            minDepth: 0.5,
            maxDepth: 5,
            confidenceThreshold: 2
        )

        XCTAssertEqual(quality.validSampleCount, 0)
        XCTAssertEqual(quality.validRatio, 0)
    }

    func testDepthTextureFormatsMatchDocumentedARKitBuffers() throws {
        let depthMap = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_DepthFloat32
        )
        let confidenceMap = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_OneComponent8
        )

        XCTAssertEqual(RendererMetalHelpers.depthMetalPixelFormat(for: depthMap), .r32Float)
        XCTAssertEqual(RendererMetalHelpers.confidenceMetalPixelFormat(for: confidenceMap), .r8Uint)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let textureCache = RendererMetalHelpers.makeTextureCache(device: device)
        XCTAssertNotNil(
            RendererMetalHelpers.makeDepthTexturePair(
                depthMap: depthMap,
                confidenceMap: confidenceMap,
                textureCache: textureCache
            )
        )
    }

    func testCaptureUsesMediumAndHighConfidenceButStillRejectsLowConfidence() throws {
        let depthMap = try makeDepthMap(width: 90, height: 90, value: 2.0)
        let mediumConfidenceMap = try makeConfidenceMap(width: 90, height: 90, value: 1)
        let lowConfidenceMap = try makeConfidenceMap(width: 90, height: 90, value: 0)

        let mediumQuality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: mediumConfidenceMap,
            minDepth: 0.5,
            maxDepth: 5.0,
            confidenceThreshold: 1
        )
        let lowQuality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: lowConfidenceMap,
            minDepth: 0.5,
            maxDepth: 5.0,
            confidenceThreshold: 1
        )

        XCTAssertEqual(
            RendererScanSettings.reliableConfidenceThreshold(storedThreshold: 0),
            1,
            "ARKit low confidence (0) must remain excluded"
        )
        XCTAssertEqual(RendererScanSettings.reliableConfidenceThreshold(storedThreshold: 1), 1)
        XCTAssertEqual(mediumQuality.validSampleCount, 81)
        XCTAssertTrue(RendererDepthCoverage.acceptsCaptureDepthQuality(mediumQuality))
        XCTAssertEqual(lowQuality.validSampleCount, 0)
        XCTAssertFalse(RendererDepthCoverage.acceptsCaptureDepthQuality(lowQuality))
    }

    func testOutdoorCaptureDiagnosticsRetainRejectionReasonAndRecoverAfterAcceptedFrame() {
        let sparse = RendererDepthQuality(validSampleCount: 2, totalSampleCount: 81, medianDepth: 2.1)
        let recovered = RendererDepthQuality(validSampleCount: 7, totalSampleCount: 81, medianDepth: 2.0)
        var diagnostics = RendererCaptureDiagnostics()

        diagnostics.record(.rejectedSparseReliableDepth(sparse))
        diagnostics.record(.accepted(recovered))

        XCTAssertEqual(diagnostics.sparseDepthRejectedFrameCount, 1)
        XCTAssertEqual(diagnostics.acceptedFrameCount, 1)
        XCTAssertEqual(diagnostics.latestDepthQuality, recovered)
    }

    func testThinCanopyEdgePolicyRequiresOneStableNeighbor() {
        let depthConfig = FruitScanExperimentConfig.default.depth

        XCTAssertEqual(depthConfig.minimumReliableConfidence, 1)
        XCTAssertEqual(depthConfig.minimumStableDepthNeighborCount, 1)
    }

    func testGuidanceReportsSparseCanopyDepthAndClearsAfterRecovery() {
        let sparse = RendererDepthQuality(validSampleCount: 2, totalSampleCount: 81, medianDepth: 2.2)
        let recovered = RendererDepthQuality(validSampleCount: 8, totalSampleCount: 81, medianDepth: 2.2)

        XCTAssertEqual(
            ScanGuidanceHelper.evaluate(
                speed: 0.1,
                medianDepth: 2.2,
                trackingState: .normal,
                lightIntensity: 1_000,
                captureDepthQuality: sparse
            ),
            .sparseDepth
        )
        XCTAssertEqual(
            ScanGuidanceHelper.evaluate(
                speed: 0.1,
                medianDepth: 2.2,
                trackingState: .normal,
                lightIntensity: 1_000,
                captureDepthQuality: recovered
            ),
            .goodPace
        )
    }

    @MainActor
    func testGuidancePresentationDismissesCurrentGoodPaceAfterDelay() async throws {
        let delayDriver = ScanGuidanceDismissDelayDriver()
        let controller = ScanGuidancePresentationController {
            await delayDriver.wait()
        }

        let dismissTask = try XCTUnwrap(
            controller.update(hint: .goodPace, isRecording: true)
        )
        let request = await delayDriver.nextRequest()

        XCTAssertEqual(controller.visibleHint, .goodPace)

        await delayDriver.resume(request: request)
        await dismissTask.value

        XCTAssertNil(controller.visibleHint)
    }

    @MainActor
    func testGuidancePresentationRejectsSupersededDismissalForRepeatedGoodPace() async throws {
        let delayDriver = ScanGuidanceDismissDelayDriver()
        let controller = ScanGuidancePresentationController {
            await delayDriver.wait()
        }

        let firstTask = try XCTUnwrap(
            controller.update(hint: .goodPace, isRecording: true)
        )
        let firstRequest = await delayDriver.nextRequest()

        XCTAssertNil(controller.update(hint: .none, isRecording: true))

        let secondTask = try XCTUnwrap(
            controller.update(hint: .goodPace, isRecording: true)
        )
        let secondRequest = await delayDriver.nextRequest()

        await delayDriver.resume(request: firstRequest)
        await firstTask.value

        XCTAssertEqual(
            controller.visibleHint,
            .goodPace,
            "A canceled delay from an earlier hint must not hide a newer presentation"
        )

        await delayDriver.resume(request: secondRequest)
        await secondTask.value

        XCTAssertNil(controller.visibleHint)
    }

    @MainActor
    func testGuidancePresentationKeepsWarningAfterGoodPaceCancellation() async throws {
        let delayDriver = ScanGuidanceDismissDelayDriver()
        let controller = ScanGuidancePresentationController {
            await delayDriver.wait()
        }

        let staleTask = try XCTUnwrap(
            controller.update(hint: .goodPace, isRecording: true)
        )
        let staleRequest = await delayDriver.nextRequest()

        XCTAssertNil(controller.update(hint: .tooFast, isRecording: true))
        await delayDriver.resume(request: staleRequest)
        await staleTask.value

        XCTAssertEqual(controller.visibleHint, .tooFast)
    }

    @MainActor
    func testGuidancePresentationInvalidateRejectsLateDismissal() async throws {
        let delayDriver = ScanGuidanceDismissDelayDriver()
        let controller = ScanGuidancePresentationController {
            await delayDriver.wait()
        }

        let staleTask = try XCTUnwrap(
            controller.update(hint: .goodPace, isRecording: true)
        )
        let staleRequest = await delayDriver.nextRequest()

        controller.invalidate()
        await delayDriver.resume(request: staleRequest)
        await staleTask.value

        XCTAssertNil(controller.visibleHint)
        XCTAssertNil(controller.update(hint: .tooClose, isRecording: false))
        XCTAssertNil(controller.visibleHint)
    }

    func testDepthTexturePairFailsClosedForUnsupportedPixelFormats() throws {
        let unsupportedDepth = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_OneComponent8
        )
        let unsupportedConfidence = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        let supportedDepth = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_DepthFloat32
        )
        let supportedConfidence = try makePixelBuffer(
            width: 8,
            height: 8,
            pixelFormat: kCVPixelFormatType_OneComponent8
        )

        XCTAssertNil(RendererMetalHelpers.depthMetalPixelFormat(for: unsupportedDepth))
        XCTAssertNil(RendererMetalHelpers.confidenceMetalPixelFormat(for: unsupportedConfidence))
        XCTAssertEqual(
            RendererDepthCoverage.sampleDepthQuality(
                from: unsupportedDepth,
                confidenceMap: supportedConfidence,
                minDepth: 0.5,
                maxDepth: 5,
                confidenceThreshold: 1
            ),
            RendererDepthQuality(validSampleCount: 0, totalSampleCount: 81, medianDepth: 0)
        )

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let textureCache = RendererMetalHelpers.makeTextureCache(device: device)
        XCTAssertNil(
            RendererMetalHelpers.makeDepthTexturePair(
                depthMap: unsupportedDepth,
                confidenceMap: supportedConfidence,
                textureCache: textureCache
            )
        )
        XCTAssertNil(
            RendererMetalHelpers.makeDepthTexturePair(
                depthMap: supportedDepth,
                confidenceMap: unsupportedConfidence,
                textureCache: textureCache
            )
        )
    }

    func testCanopyGeometryEstimatorReportsOuterVolumeAndPorosityAdjustedVolume() throws {
        let positions: [SIMD3<Float>] = (0...100).map { index in
            let fraction = Float(index) / 100.0
            return SIMD3<Float>(
                -1.0 + 2.0 * fraction,
                4.0 * fraction,
                -0.5 + fraction
            )
        }

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.crownWidthM, 1.8, accuracy: 0.001)
        XCTAssertEqual(estimate.treeHeightM, 3.6, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 0.9, accuracy: 0.001)
        XCTAssertEqual(
            estimate.outerCrownVolumeM3,
            Float.pi / 6 * 1.8 * 3.6 * 0.9,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(estimate.voxelSizeM, 0)
        XCTAssertEqual(estimate.partitionSizeM, 5 * estimate.voxelSizeM, accuracy: 0.01)
        XCTAssertGreaterThan(estimate.partitionCount, 1)
        XCTAssertLessThan(estimate.effectiveVolumeCoefficient, 0.05)
        XCTAssertLessThan(estimate.projectionEffectiveCoefficient, 0.10)
        XCTAssertLessThan(estimate.crownVolumeM3, estimate.outerCrownVolumeM3)
        XCTAssertEqual(estimate.pointCount, 101)
        XCTAssertEqual(estimate.preprocessedPointCount, 101)
        XCTAssertEqual(estimate.groundFilteredPointCount, 0)
        XCTAssertEqual(estimate.trunkFilteredPointCount, 0)
        XCTAssertEqual(estimate.neighborFilteredPointCount, 0)
        XCTAssertEqual(estimate.canopyClusterCount, 1)
        XCTAssertEqual(estimate.robustPointCount, 91)
    }

    func testCanopyGeometryEstimatorKeepsDenseCanopyNearOuterVolume() throws {
        var positions: [SIMD3<Float>] = []
        for xi in 0...10 {
            for yi in 0...10 {
                for zi in 0...10 {
                    positions.append(SIMD3<Float>(
                        -1 + Float(xi) * 0.2,
                        Float(yi) * 0.2,
                        -1 + Float(zi) * 0.2
                    ))
                }
            }
        }

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.crownWidthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.treeHeightM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 2, accuracy: 0.001)
        XCTAssertGreaterThan(estimate.effectiveVolumeCoefficient, 0.95)
        XCTAssertGreaterThan(estimate.projectionXYCoefficient, 0.95)
        XCTAssertGreaterThan(estimate.projectionXZCoefficient, 0.95)
        XCTAssertGreaterThan(estimate.projectionYZCoefficient, 0.95)
        XCTAssertGreaterThan(estimate.projectionEffectiveCoefficient, 0.95)
        XCTAssertEqual(estimate.crownVolumeM3, estimate.outerCrownVolumeM3, accuracy: 0.001)
        XCTAssertEqual(estimate.voxelSizeM, 0.2, accuracy: 0.001)
        XCTAssertEqual(estimate.partitionSizeM, 1.0, accuracy: 0.001)
        XCTAssertEqual(estimate.partitionCount, 2)
        XCTAssertEqual(estimate.neighborFilteredPointCount, 0)
        XCTAssertEqual(estimate.canopyClusterCount, 1)
    }

    func testCanopyGeometryEstimatorRemovesGroundBandBeforeHeightAndVolume() throws {
        var positions = makeDenseCanopyPositions(yBase: 1, yStep: 0.2)
        for xi in 0...20 {
            for zi in 0...20 {
                positions.append(SIMD3<Float>(
                    -1 + Float(xi) * 0.1,
                    0,
                    -1 + Float(zi) * 0.1
                ))
            }
        }

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.treeHeightM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownWidthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.pointCount, positions.count)
        XCTAssertGreaterThan(estimate.groundFilteredPointCount, 0)
        XCTAssertEqual(estimate.trunkFilteredPointCount, 0)
        XCTAssertEqual(estimate.neighborFilteredPointCount, 0)
        XCTAssertEqual(estimate.canopyClusterCount, 1)
        XCTAssertEqual(
            estimate.preprocessedPointCount,
            estimate.pointCount - estimate.groundFilteredPointCount
        )
    }

    func testCanopyGeometryEstimatorRemovesLowCentralTrunkBeforeCrownVolume() throws {
        var positions = makeDenseCanopyPositions(yBase: 1, yStep: 0.2)
        for yi in 0...14 {
            let y = Float(yi) * 0.1
            for angleIndex in 0..<10 {
                let angle = 2 * Float.pi * Float(angleIndex) / 10
                let radius: Float = angleIndex.isMultiple(of: 2) ? 0.03 : 0.05
                positions.append(SIMD3<Float>(
                    cos(angle) * radius,
                    y,
                    sin(angle) * radius
                ))
            }
        }

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.treeHeightM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownWidthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.pointCount, positions.count)
        XCTAssertEqual(estimate.groundFilteredPointCount, 0)
        XCTAssertGreaterThan(estimate.trunkFilteredPointCount, 0)
        XCTAssertEqual(estimate.neighborFilteredPointCount, 0)
        XCTAssertEqual(estimate.canopyClusterCount, 1)
        XCTAssertEqual(
            estimate.preprocessedPointCount,
            estimate.pointCount - estimate.trunkFilteredPointCount
        )
    }

    func testCanopyGeometryEstimatorUsesThreeProjectionCoefficientToPenalizeVerticalVoids() throws {
        var positions: [SIMD3<Float>] = []
        for xi in 0...20 {
            for zi in 0...20 {
                positions.append(SIMD3<Float>(
                    -1 + Float(xi) * 0.1,
                    0,
                    -1 + Float(zi) * 0.1
                ))
            }
        }
        for y in [Float(1), Float(3)] {
            for xi in 0...10 {
                for zi in 0...10 {
                    positions.append(SIMD3<Float>(
                        -1 + Float(xi) * 0.2,
                        y,
                        -1 + Float(zi) * 0.2
                    ))
                }
            }
        }

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.treeHeightM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownWidthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 2, accuracy: 0.001)
        XCTAssertGreaterThan(estimate.groundFilteredPointCount, 0)
        XCTAssertGreaterThan(estimate.projectionXZCoefficient, 0.95)
        XCTAssertLessThan(estimate.projectionXYCoefficient, 0.35)
        XCTAssertLessThan(estimate.projectionYZCoefficient, 0.35)
        XCTAssertLessThan(estimate.projectionEffectiveCoefficient, 0.50)
        XCTAssertEqual(
            estimate.effectiveVolumeCoefficient,
            estimate.projectionEffectiveCoefficient,
            accuracy: 0.001
        )
        XCTAssertLessThan(estimate.crownVolumeM3, estimate.outerCrownVolumeM3 * 0.50)
    }

    func testCanopyGeometryEstimatorKeepsDominantTargetClusterWhenNeighborCanopyIsSeparated() throws {
        var positions = makeDenseCanopyPositions(yBase: 1, yStep: 0.2)
        positions += makeSparseCanopyPositions(xOffset: 3.4, yBase: 1, zOffset: 0)

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertEqual(estimate.crownWidthM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.treeHeightM, 2, accuracy: 0.001)
        XCTAssertEqual(estimate.crownDepthM, 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(estimate.canopyClusterCount, 2)
        XCTAssertGreaterThan(estimate.neighborFilteredPointCount, 0)
        XCTAssertEqual(estimate.groundFilteredPointCount, 0)
        XCTAssertEqual(estimate.trunkFilteredPointCount, 0)
        XCTAssertEqual(
            estimate.preprocessedPointCount,
            estimate.pointCount - estimate.neighborFilteredPointCount
        )
    }

    func testCanopyGeometryEstimatorKeepsAmbiguousSeparatedCanopiesForManualRescan() throws {
        var positions = makeDenseCanopyPositions(yBase: 1, yStep: 0.2)
        positions += makeDenseCanopyPositions(xOffset: 3.4, yBase: 1, yStep: 0.2, zOffset: 0)

        let estimate = try XCTUnwrap(CanopyGeometryEstimator.estimate(positions: positions))

        XCTAssertGreaterThanOrEqual(estimate.canopyClusterCount, 2)
        XCTAssertEqual(estimate.neighborFilteredPointCount, 0)
        XCTAssertGreaterThan(estimate.crownWidthM, 4.0)
    }

    func testCanopyGeometryEstimatorRejectsSparsePointCloud() {
        let positions: [SIMD3<Float>] = (0..<10).map { index in
            SIMD3<Float>(Float(index) * 0.01, 0, 0)
        }

        XCTAssertNil(CanopyGeometryEstimator.estimate(positions: positions))
    }

    private func makeDenseCanopyPositions(
        xOffset: Float = 0,
        yBase: Float,
        yStep: Float,
        zOffset: Float = 0
    ) -> [SIMD3<Float>] {
        var positions: [SIMD3<Float>] = []
        for xi in 0...10 {
            for yi in 0...10 {
                for zi in 0...10 {
                    positions.append(SIMD3<Float>(
                        xOffset - 1 + Float(xi) * 0.2,
                        yBase + Float(yi) * yStep,
                        zOffset - 1 + Float(zi) * 0.2
                    ))
                }
            }
        }
        return positions
    }

    private func makeSparseCanopyPositions(
        xOffset: Float,
        yBase: Float,
        zOffset: Float
    ) -> [SIMD3<Float>] {
        var positions: [SIMD3<Float>] = []
        for xi in 0...5 {
            for yi in 0...5 {
                for zi in 0...5 {
                    positions.append(SIMD3<Float>(
                        xOffset - 0.5 + Float(xi) * 0.2,
                        yBase + Float(yi) * 0.4,
                        zOffset - 0.5 + Float(zi) * 0.2
                    ))
                }
            }
        }
        return positions
    }

    private func voxelKey(angle: Float, radius: Float, y: Int32 = 0) -> RendererVoxelKey {
        RendererVoxelKey(
            x: Int32((cos(angle) * radius).rounded()),
            y: y,
            z: Int32((sin(angle) * radius).rounded())
        )
    }

    private func cameraRegion(x: Int, forwardX: Int, forwardZ: Int) -> RendererCameraRegionKey {
        RendererCameraRegionKey(
            x: x,
            y: 0,
            z: 0,
            forwardX: forwardX,
            forwardY: 0,
            forwardZ: forwardZ
        )
    }

    func testSaveFileCreatesTargetFolder() async throws {
        let folder = "save-file-\(UUID().uuidString)"
        let filename = "pointcloud.bin"
        let directory = getDocumentsDirectory().appendingPathComponent(folder, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await saveFile(data: Data("ok".utf8), filename: filename, folder: folder)

        let url = directory.appendingPathComponent(filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "ok")
    }

    func testSaveFileRejectsUnsafeFolderName() async {
        do {
            try await saveFile(data: Data(), filename: "pointcloud.bin", folder: "../escape")
            XCTFail("Expected unsafe folder name to be rejected")
        } catch LocalFileStorageError.invalidFolder {
        } catch {
            XCTFail("Expected invalidFolder, got \(error)")
        }
    }

    // MARK: - PointCloudDenoiser.statisticalOutlierRemoval

    func testSOR_ReturnsOriginalForSmallInput() {
        let empty: [RendererPointSample] = []
        XCTAssertEqual(PointCloudDenoiser.statisticalOutlierRemoval(samples: empty).count, 0)

        let one = [RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1)]
        let resultOne = PointCloudDenoiser.statisticalOutlierRemoval(samples: one)
        XCTAssertEqual(resultOne.count, 1)
        XCTAssertEqual(resultOne.first?.position, SIMD3<Float>(1, 2, 3))

        let kPlusOne: [RendererPointSample] = (0..<13).map { i in
            RendererPointSample(position: SIMD3<Float>(Float(i), 0, 0), color: SIMD3<Float>(1, 0, 0), confidence: 1)
        }
        let resultKPlusOne = PointCloudDenoiser.statisticalOutlierRemoval(samples: kPlusOne)
        XCTAssertEqual(resultKPlusOne.count, 13)
    }

    func testSOR_RemovesFarOutlierPreservesInliers() {
        var samples: [RendererPointSample] = []
        let clusterCount = 20
        for i in 0..<clusterCount {
            let offset = Float(i % 5 - 2) * 0.03
            let pos = SIMD3<Float>(offset, Float((i / 5) % 4 - 1) * 0.03, 0)
            samples.append(RendererPointSample(
                position: pos,
                color: SIMD3<Float>(Float(i) / Float(clusterCount), 0.5, 0.2),
                confidence: 0.8 + Float(i % 3) * 0.05
            ))
        }
        let outlier = RendererPointSample(
            position: SIMD3<Float>(12, 0, 0),
            color: SIMD3<Float>(0, 1, 0),
            confidence: 0.9
        )
        samples.append(outlier)

        let detailed = PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: samples,
            k: 5,
            stdMultiplier: 1.5
        )
        let result = detailed.samples

        XCTAssertEqual(result.count, clusterCount, "Outlier should be removed, inliers preserved")
        XCTAssertEqual(detailed.stats.originalCount, clusterCount + 1)
        XCTAssertEqual(detailed.stats.retainedCount, clusterCount)
        XCTAssertEqual(detailed.stats.removedCount, 1)
        XCTAssertEqual(detailed.stats.removalRatio, 1.0 / Float(clusterCount + 1), accuracy: 0.001)
        XCTAssertGreaterThan(detailed.stats.threshold, 0)

        let hasOutlier = result.contains { $0.position.x > 10 }
        XCTAssertFalse(hasOutlier, "Far outlier must be removed")

        for i in 0..<clusterCount {
            let expected = samples[i]
            let kept = result.first { $0.position == expected.position }
            XCTAssertNotNil(kept, "Inlier \(i) missing")
            XCTAssertEqual(kept?.color, expected.color, "Inlier \(i) color changed")
            XCTAssertEqual(kept?.confidence, expected.confidence, "Inlier \(i) confidence changed")
        }
    }

    // MARK: - RendererPointCloudSnapshot filtering

    func testIsExportableParticle_RejectsLowConfidence() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 5)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Confidence 5 below threshold 10 should be rejected")
    }

    func testIsExportableParticle_RejectsZeroPosition() {
        let p = ParticleUniforms(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Zero position should be rejected")
    }

    func testIsExportableParticle_RejectsNonFinitePosition() {
        let p = ParticleUniforms(position: SIMD3<Float>(.nan, 1, 1), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "NaN position should be rejected")
    }

    func testIsExportableParticle_RejectsNonFiniteColor() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(.infinity, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Infinite color component should be rejected")
    }

    func testIsExportableParticle_AcceptsValidParticle() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 100)
        XCTAssertTrue(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                      "Valid particle should be accepted")
    }

    // MARK: - Voxel-based deduplication

    func testVoxelDedupe_KeepsHigherConfidenceInSameVoxel() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            try XCTSkipIf(true, "Metal device not available")
            return
        }

        let pos = SIMD3<Float>(1.5, 2.5, 3.5)
        let particles: [ParticleUniforms] = [
            ParticleUniforms(position: pos, color: SIMD3<Float>(1, 0, 0), confidence: 30),
            ParticleUniforms(position: pos, color: SIMD3<Float>(0, 1, 0), confidence: 90),
        ]
        let buffer = MetalBuffer<ParticleUniforms>(device: device, array: particles, index: 0)

        let result = RendererPointCloudSnapshot.makeFilteredSamples(
            particlesBuffer: buffer,
            currentPointCount: 2,
            currentPointIndex: 2,
            maxPoints: 2,
            voxelSize: 1.0,
            confidenceThreshold: 10
        )

        XCTAssertEqual(result.count, 1, "Two particles in same voxel should deduplicate to one")
        XCTAssertEqual(result[0].confidence, 90, "Higher-confidence particle should be kept")
        XCTAssertEqual(result[0].color, SIMD3<Float>(0, 1, 0), "Higher-confidence particle's color should be kept")
    }

    func testFinalExportAndAnalysisUsePaperFiveMillimeterSpatialHash() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            try XCTSkipIf(true, "Metal device not available")
            return
        }

        let particles: [ParticleUniforms] = [
            ParticleUniforms(
                position: SIMD3<Float>(0.001, 0, 1),
                color: SIMD3<Float>(1, 0, 0),
                confidence: 90
            ),
            ParticleUniforms(
                position: SIMD3<Float>(0.009, 0, 1),
                color: SIMD3<Float>(0, 1, 0),
                confidence: 80
            ),
        ]
        let buffer = MetalBuffer<ParticleUniforms>(device: device, array: particles, index: 0)

        let coarseSnapshotSamples = RendererPointCloudSnapshot.makeFilteredSamples(
            particlesBuffer: buffer,
            currentPointCount: 2,
            currentPointIndex: 2,
            maxPoints: 2,
            voxelSize: 0.015,
            confidenceThreshold: 10
        )
        let analysisSamples = RendererPointCloudSnapshot.makeFilteredSamples(
            particlesBuffer: buffer,
            currentPointCount: 2,
            currentPointIndex: 2,
            maxPoints: 2,
            voxelSize: Renderer.finalPointCloudVoxelSizeMeters,
            confidenceThreshold: 10
        )

        XCTAssertEqual(Renderer.finalPointCloudVoxelSizeMeters, 0.005, accuracy: 0.0001)
        XCTAssertEqual(coarseSnapshotSamples.count, 1)
        XCTAssertEqual(analysisSamples.count, 2)
    }

    func testMetalBufferAllowsEmptyCount() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            try XCTSkipIf(true, "Metal device not available")
            return
        }

        let buffer = MetalBuffer<ParticleUniforms>(device: device, count: 0, index: 0)

        XCTAssertEqual(buffer.count, 0)
        XCTAssertNotNil(buffer.metalBuffer)
        XCTAssertGreaterThanOrEqual(buffer.metalBuffer?.length ?? 0, 1)
    }

    func testMetalBufferAllowsEmptyArray() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            try XCTSkipIf(true, "Metal device not available")
            return
        }

        let buffer = MetalBuffer<ParticleUniforms>(device: device, array: [], index: 0)
        buffer.assign(with: [])

        XCTAssertEqual(buffer.count, 0)
        XCTAssertNotNil(buffer.metalBuffer)
        XCTAssertGreaterThanOrEqual(buffer.metalBuffer?.length ?? 0, 1)
    }

    // MARK: - Color clamping

    func testClampColor_ClampsOutOfRangeRGB() {
        let below = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(-0.5, -1.0, -0.1))
        XCTAssertEqual(below, SIMD3<Float>(0, 0, 0), "Negative values should clamp to 0")

        let above = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(1.2, 2.0, 1.5))
        XCTAssertEqual(above, SIMD3<Float>(1, 1, 1), "Values above 1 should clamp to 1")

        let mixed = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(-0.2, 0.5, 1.8))
        XCTAssertEqual(mixed, SIMD3<Float>(0, 0.5, 1), "Mixed values should clamp per-channel")
    }

    func testClampColor_PreservesValidRGB() {
        let valid = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(0.0, 0.5, 1.0))
        XCTAssertEqual(valid, SIMD3<Float>(0, 0.5, 1), "In-range values should pass through unchanged")
    }

    func testMakeExportableSample_RejectsNonFiniteColorBeforeGPUAssistedExport() {
        let particle = ParticleUniforms(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(.nan, 0.5, 0.5),
            confidence: 100
        )

        let sample = RendererPointCloudSnapshot.makeExportableSample(
            from: particle,
            confidenceThreshold: 10
        )

        XCTAssertNil(sample, "GPU-assisted filtering must keep the same finite-color gate as CPU filtering")
    }

    func testMakeExportableSample_ClampsValidOutOfRangeColor() throws {
        let particle = ParticleUniforms(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(-0.1, 0.5, 1.2),
            confidence: 100
        )

        let sample = try XCTUnwrap(RendererPointCloudSnapshot.makeExportableSample(
            from: particle,
            confidenceThreshold: 10
        ))

        XCTAssertEqual(sample.color, SIMD3<Float>(0, 0.5, 1))
    }

    // MARK: - makeColoredPoints

    func testMakeColoredPoints_ConvertsCorrectly() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 0.9),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.4, 0.5, 0.6), confidence: 0.7),
        ]
        let points = RendererPointCloudSnapshot.makeColoredPoints(from: samples)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].pos, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(points[0].r, 0.1)
        XCTAssertEqual(points[0].g, 0.2)
        XCTAssertEqual(points[0].b, 0.3)
        XCTAssertEqual(points[1].pos, SIMD3<Float>(4, 5, 6))
    }

    // MARK: - makeSignature

    func testMakeSignature_ProducesDeterministicSignature() {
        let sig = RendererPointCloudSnapshot.makeSignature(
            pointCount: 1000, pointIndex: 42, voxelSize: 0.05, confidenceThreshold: 30
        )
        XCTAssertEqual(sig.pointCount, 1000)
        XCTAssertEqual(sig.pointIndex, 42)
        XCTAssertEqual(sig.voxelSize, 0.05)
        XCTAssertEqual(sig.confidenceThreshold, 30)
    }

    // MARK: - RendererScanProgress

    func testScanProgress_ResetClearsState() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)
        XCTAssertEqual(progress.voxelDiscoveryRate, 0)
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)
    }

    func testScanProgress_PauseResumeExcludesPausedDuration() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.pause(now: start.addingTimeInterval(5))
        XCTAssertEqual(progress.scanDuration, 5, accuracy: 0.001)

        progress.resume(now: start.addingTimeInterval(15))
        progress.pause(now: start.addingTimeInterval(18))

        XCTAssertEqual(progress.scanDuration, 8, accuracy: 0.001)
    }

    func testScanProgress_RecordVoxelCountRespectsInterval() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(10, now: start.addingTimeInterval(0.5))
        XCTAssertEqual(progress.voxelDiscoveryRate, 0, "0.5s interval should be ignored")

        progress.recordVoxelCount(10, now: start.addingTimeInterval(1.0))
        XCTAssertEqual(progress.voxelDiscoveryRate, 10, "1s interval should record delta (10 - 0 = 10)")
    }

    func testScanProgress_ComputesAverageDiscoveryRate() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(5, now: start.addingTimeInterval(1))   // delta 5
        progress.recordVoxelCount(10, now: start.addingTimeInterval(2))  // delta 5
        progress.recordVoxelCount(20, now: start.addingTimeInterval(3))  // delta 10
        progress.recordVoxelCount(28, now: start.addingTimeInterval(4))  // delta 8

        let expectedRate = Float(5 + 5 + 10 + 8) / 4.0
        XCTAssertEqual(progress.voxelDiscoveryRate, expectedRate)
    }

    func testScanProgress_CapsHistoryAtTen() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        for i in 1...15 {
            progress.recordVoxelCount(i * 10, now: start.addingTimeInterval(TimeInterval(i)))
        }

        let rate = progress.voxelDiscoveryRate
        let lastTenDeltas = Array(repeating: Float(10), count: 10)
        let expectedRate = lastTenDeltas.reduce(0, +) / Float(lastTenDeltas.count)
        XCTAssertEqual(rate, expectedRate, "History capped at 10, last 10 deltas should all be 10")
    }

    func testScanProgress_TrendStable() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(2, now: start.addingTimeInterval(1))
        progress.recordVoxelCount(3, now: start.addingTimeInterval(2))
        progress.recordVoxelCount(4, now: start.addingTimeInterval(3))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .stable, "Recent avg < 5 should be stable")
    }

    func testScanProgress_TrendDecreasing() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        for i in 1...7 {
            progress.recordVoxelCount(i * 30, now: start.addingTimeInterval(TimeInterval(i)))
        }
        progress.recordVoxelCount(8 * 30 + 15, now: start.addingTimeInterval(8))
        progress.recordVoxelCount(8 * 30 + 25, now: start.addingTimeInterval(9))
        progress.recordVoxelCount(8 * 30 + 30, now: start.addingTimeInterval(10))

        XCTAssertEqual(progress.voxelDiscoveryTrend, .decreasing, "Dropping recent deltas should be decreasing")
    }

    func testScanProgress_TrendIncreasing() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(20, now: start.addingTimeInterval(1))
        progress.recordVoxelCount(40, now: start.addingTimeInterval(2))
        progress.recordVoxelCount(65, now: start.addingTimeInterval(3))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .increasing)
    }

    func testScanProgress_TrendCollectingBeforeThreeRecords() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(10, now: start.addingTimeInterval(1))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)

        progress.recordVoxelCount(20, now: start.addingTimeInterval(2))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)

        progress.recordVoxelCount(30, now: start.addingTimeInterval(3))
        XCTAssertNotEqual(progress.voxelDiscoveryTrend, .collecting, "Third record should exit collecting")
    }

    // MARK: - RendererPLYDataBuilder.makeData

    func testMakeData_ProducesASCIIPLY() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 0.9),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.4, 0.5, 0.6), confidence: 0.7),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-06-05 12:00:00",
            gpsLat: 35.123456, gpsLon: 139.654321
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0], "ply")
        XCTAssertEqual(lines[1], "format ascii 1.0")
        XCTAssertTrue(lines.contains("comment tree_id T001"))
        XCTAssertTrue(lines.contains("comment scan_date 2025-06-05 12:00:00"))
        XCTAssertTrue(lines.contains("comment gps_lat 35.123456"))
        XCTAssertTrue(lines.contains("comment gps_lon 139.654321"))
        XCTAssertTrue(lines.contains("element vertex 2"))
        XCTAssertTrue(lines.contains("property float x"))
        XCTAssertTrue(lines.contains("property float y"))
        XCTAssertTrue(lines.contains("property float z"))
        XCTAssertTrue(lines.contains("property uchar red"))
        XCTAssertTrue(lines.contains("property uchar green"))
        XCTAssertTrue(lines.contains("property uchar blue"))
        XCTAssertTrue(lines.contains("element face 0"))
        XCTAssertTrue(lines.contains("property list uchar int vertex_indices"))
        XCTAssertTrue(lines.contains("end_header"))
    }

    func testMakeDataSanitizesTreeIDBeforeWritingPLYHeader() {
        let sample = RendererPointSample(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(0.1, 0.2, 0.3),
            confidence: 0.9
        )
        let data = RendererPLYDataBuilder.makeData(
            samples: [sample],
            treeID: "T001\r\nelement vertex 999\ncomment gps_lat 90",
            scanDate: "2026-06-25 10:00:00",
            gpsLat: 35,
            gpsLon: 139
        )
        let contents = String(decoding: data, as: UTF8.self)
        let lines = contents.components(separatedBy: "\r\n")

        XCTAssertTrue(lines.contains("comment tree_id T001 element vertex 999 comment gps_lat 90"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("element vertex") }, ["element vertex 1"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("comment gps_lat") }, ["comment gps_lat 35.000000"])
    }

    func testMakeData_GPSFormatSixDecimals() {
        let gpsLinePattern = try! NSRegularExpression(pattern: "comment gps_(lat|lon) \\-?\\d+\\.\\d{6}")
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-01-01",
            gpsLat: -45.987654321, gpsLon: 123.123456789
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        let gpsLines = lines.filter { $0.hasPrefix("comment gps_") }
        XCTAssertEqual(gpsLines.count, 2)
        for line in gpsLines {
            let range = NSRange(location: 0, length: line.utf16.count)
            XCTAssertNotNil(gpsLinePattern.firstMatch(in: line, options: [], range: range),
                            "GPS line should have exactly 6 decimal places: \(line)")
        }
        XCTAssertTrue(gpsLines.contains("comment gps_lat -45.987654"))
        XCTAssertTrue(gpsLines.contains("comment gps_lon 123.123457"))
    }

    func testMakeDataSanitizesInvalidGPSMetadata() {
        let samples = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 1)
        ]
        let nonFiniteData = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-01-01",
            gpsLat: .nan, gpsLon: .infinity
        )
        let outOfRangeData = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-01-01",
            gpsLat: 90.1, gpsLon: -180.1
        )

        let nonFiniteContents = String(decoding: nonFiniteData, as: UTF8.self)
        XCTAssertTrue(nonFiniteContents.contains("comment gps_lat 0.000000"))
        XCTAssertTrue(nonFiniteContents.contains("comment gps_lon 0.000000"))
        XCTAssertFalse(nonFiniteContents.lowercased().contains("nan"))
        XCTAssertFalse(nonFiniteContents.lowercased().contains("inf"))

        let outOfRangeContents = String(decoding: outOfRangeData, as: UTF8.self)
        XCTAssertTrue(outOfRangeContents.contains("comment gps_lat 0.000000"))
        XCTAssertTrue(outOfRangeContents.contains("comment gps_lon 0.000000"))
        XCTAssertFalse(outOfRangeContents.contains("90.100000"))
        XCTAssertFalse(outOfRangeContents.contains("-180.100000"))
    }

    func testMakeData_VertexCountMatchesSamples() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(1, 1, 1), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(2, 2, 2), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element vertex 3"))
    }

    func testMakeData_EmptySamplesHasZeroVertexCount() {
        let data = RendererPLYDataBuilder.makeData(
            samples: [], treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element vertex 0"))
    }

    func testMakeData_HasFaceElementZero() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element face 0"))
        XCTAssertTrue(lines.contains("property list uchar int vertex_indices"))
    }

    func testMakeData_UsesCRLFLineEndings() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertGreaterThan(lines.count, 1, "Should have multiple lines separated by CRLF")
        let rawNSString = data as NSData
        let rawBytes = rawNSString.bytes.bindMemory(to: UInt8.self, capacity: data.count)
        let rawStr = String(decoding: UnsafeBufferPointer(start: rawBytes, count: data.count), as: UTF8.self)
        let lfOnly = rawStr.replacingOccurrences(of: "\r\n", with: "")
        XCTAssertFalse(lfOnly.contains("\r"), "No bare CR without LF should exist")
        XCTAssertTrue(rawStr.contains("\r\n"), "CRLF pairs must exist in raw data")
    }

    func testMakeData_ColorFloatToUCharConversion() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.0, 0.0, 0.0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(1.0, 1.0, 1.0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(7, 8, 9), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")

        let headerEndIndex = lines.firstIndex(of: "end_header")!
        let dataLines = Array(lines[(headerEndIndex + 1)...]).filter { !$0.isEmpty }

        XCTAssertEqual(dataLines.count, 3)

        XCTAssertTrue(dataLines[0].hasSuffix(" 0 0 0"),
                      "Color (0,0,0) should produce 0 0 0, got: \(dataLines[0])")
        XCTAssertTrue(dataLines[1].hasSuffix(" 255 255 255"),
                      "Color (1,1,1) should produce 255 255 255, got: \(dataLines[1])")

        let color128Line = dataLines[2]
        let parts128 = color128Line.components(separatedBy: " ")
        XCTAssertEqual(parts128.count, 6, "Each vertex line should have 6 fields: x y z r g b")
        let r128 = Int(parts128[3])!
        let g128 = Int(parts128[4])!
        let b128 = Int(parts128[5])!
        XCTAssertTrue(r128 == 127 || r128 == 128, "0.5*255 should be 127 or 128, got \(r128)")
        XCTAssertTrue(g128 == 127 || g128 == 128, "0.5*255 should be 127 or 128, got \(g128)")
        XCTAssertTrue(b128 == 127 || b128 == 128, "0.5*255 should be 127 or 128, got \(b128)")
    }

    func testMakeData_VertexLineFormat() {
        let color = SIMD3<Float>(0.2, 0.4, 0.6)
        let expectedR = Int(color.x * 255.0)
        let expectedG = Int(color.y * 255.0)
        let expectedB = Int(color.z * 255.0)
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1.2345, -2.3456, 3.4567), color: color, confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        let headerEndIndex = lines.firstIndex(of: "end_header")!
        let dataLine = lines[headerEndIndex + 1]

        let expected = String(format: "1.2345 -2.3456 3.4567 %d %d %d", expectedR, expectedG, expectedB)
        XCTAssertEqual(dataLine, expected)

        let parts = dataLine.components(separatedBy: " ")
        XCTAssertEqual(parts.count, 6)
        let x = Float(parts[0])
        let y = Float(parts[1])
        let z = Float(parts[2])
        XCTAssertNotNil(x)
        XCTAssertNotNil(y)
        XCTAssertNotNil(z)
        XCTAssertEqual(Double(x!), 1.2345, accuracy: 0.001)
        XCTAssertEqual(Double(y!), -2.3456, accuracy: 0.001)
        XCTAssertEqual(Double(z!), 3.4567, accuracy: 0.001)
    }

    func testPLYParserReadsRendererCRLFExport() throws {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(1, 0.5, 0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.2, 0.4, 0.6), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples,
            treeID: "T001",
            scanDate: "2026-06-07 10:00:00",
            gpsLat: 35.123456,
            gpsLon: 139.654321
        )
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T001_20260607_100000_lat35.123456_lon139.654321.ply")
        try data.write(to: plyURL)

        let pointCloud = try XCTUnwrap(PLYParserHelper.parsePointCloudData(at: plyURL))
        XCTAssertEqual(pointCloud.pointCount, 2)
        XCTAssertEqual(pointCloud.vertices[0].x, 1, accuracy: 0.001)
        XCTAssertEqual(pointCloud.vertices[0].y, 2, accuracy: 0.001)
        XCTAssertEqual(pointCloud.vertices[0].z, 3, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].g, Float(Int(0.5 * 255)) / 255.0, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].b, 0, accuracy: 0.001)
    }

    func testPointCloudBoundsPreserveRealHeightAndFootprint() throws {
        let pointCloud = PointCloudData(
            id: "bounds",
            vertices: [
                SCNVector3(-1.2, 0.4, -0.5),
                SCNVector3(0.8, 3.1, 1.7),
                SCNVector3(0.2, 1.6, 0.4)
            ],
            colors: []
        )

        let bounds = try XCTUnwrap(pointCloud.bounds)
        XCTAssertEqual(bounds.heightMeters, 2.7, accuracy: 0.001)
        XCTAssertEqual(bounds.widthMeters, 2.0, accuracy: 0.001)
        XCTAssertEqual(bounds.depthMeters, 2.2, accuracy: 0.001)
        XCTAssertEqual(bounds.center.y, 1.75, accuracy: 0.001)
    }

    func testPointCloudBoundsEmptyInputReturnsNil() {
        XCTAssertNil(PointCloudBounds(vertices: []))
    }

    func testPointCloudLoadCancellationCancelsWorkerAndDiscardsResult() async {
        let workerStarted = expectation(description: "Point-cloud parser started")
        let workerObservedCancellation = expectation(description: "Point-cloud parser observed cancellation")
        let allowWorkerToFinish = DispatchSemaphore(value: 0)
        let loadedData = PointCloudData(
            id: "cancelled-load",
            vertices: [SCNVector3(1, 2, 3)],
            colors: [PointCloudColor(r: 1, g: 0, b: 0, a: 1)]
        )

        let loadTask = Task {
            await PointCloudLoadOperation.load(
                at: URL(fileURLWithPath: "/tmp/cancelled-load.ply")
            ) { _ in
                workerStarted.fulfill()
                allowWorkerToFinish.wait()
                if Task.isCancelled {
                    workerObservedCancellation.fulfill()
                }
                return loadedData
            }
        }

        await fulfillment(of: [workerStarted], timeout: 1)
        loadTask.cancel()
        allowWorkerToFinish.signal()

        let result = await loadTask.value
        await fulfillment(of: [workerObservedCancellation], timeout: 1)
        XCTAssertNil(result, "Cancelled point-cloud loads must not publish their parsed buffer")
    }

    func testPointCloudLoadReturnsParsedDataWhenNotCancelled() async throws {
        let loadedData = PointCloudData(
            id: "completed-load",
            vertices: [SCNVector3(1, 2, 3)],
            colors: [PointCloudColor(r: 1, g: 0, b: 0, a: 1)]
        )

        let result = await PointCloudLoadOperation.load(
            at: URL(fileURLWithPath: "/tmp/completed-load.ply")
        ) { _ in
            loadedData
        }

        XCTAssertEqual(try XCTUnwrap(result).id, loadedData.id)
    }

    func testPointCloudDataStoresBoundsInDisplaySnapshot() {
        let pointCloud = PointCloudData(
            id: "cached-bounds",
            vertices: [
                SCNVector3(-1, 0, -1),
                SCNVector3(1, 2, 1)
            ],
            colors: []
        )
        let storedPropertyNames = Set(
            Mirror(reflecting: pointCloud).children.compactMap(\.label)
        )

        XCTAssertTrue(
            storedPropertyNames.contains("bounds"),
            "Bounds must be stored with the immutable display snapshot instead of recalculated during view updates"
        )
    }

    // MARK: - PLYImportService reject/cleanup

    func testPLYImportRejectsCorruptPLYAndLeavesScansDirectoryClean() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
        let plyURL = tempDir.appendingPathComponent("corrupt.ply")
        try "not a valid ply file".write(to: plyURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PLYImportService.importFile(plyURL, scansDirectory: scansDir))

        let contents = try FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Failed import left artifacts: \(contents)")
    }

    func testPLYImportRejectsMissingPLYHeader() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
        let plyURL = tempDir.appendingPathComponent("noheader.ply")
        // Write a file with ply magic but no format/element lines
        try "ply\r\ncomment no format line\r\nend_header\r\n".write(to: plyURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PLYImportService.importFile(plyURL, scansDirectory: scansDir))

        let contents = try FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Invalid header import left artifacts: \(contents)")
    }

    func testPLYImportCancellationAfterCommitRemovesDestination() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
        let plyURL = tempDir.appendingPathComponent("cancelled.ply")
        try """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        1.0 2.0 3.0 128 128 128
        """.write(to: plyURL, atomically: true, encoding: .utf8)

        var checkpointCount = 0
        XCTAssertThrowsError(
            try PLYImportService.importFile(
                plyURL,
                scansDirectory: scansDir,
                cancellationCheckpoint: {
                    checkpointCount += 1
                    if checkpointCount == 4 {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(checkpointCount, 4)

        let contents = try FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Canceled import left artifacts: \(contents)")
    }

    // MARK: - PLYImportService success + duplicate import

    func testPLYImportSanitizesSourceFileNameAndImportTwiceDoesNotOverwrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)

        let plyContent = """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face 0
        property list uchar int vertex_indices
        end_header
        1.0 2.0 3.0 128 128 128
        """

        // Source filename with characters that safeFileComponent will transform
        let plyURL = tempDir.appendingPathComponent("My Tree Scan.ply")
        try plyContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let imported1 = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(imported1),
                      "Imported filename should be safe: \(imported1)")
        XCTAssertFalse(imported1.contains(" "),
                       "Imported filename should have spaces collapsed: \(imported1)")

        // Import the same file a second time — must not overwrite the first
        let imported2 = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertNotEqual(imported1, imported2,
                         "Second import should produce a distinct filename from first")

        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(imported1).path),
                      "First imported file should still exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(imported2).path),
                      "Second imported file should exist")

        let content1 = try String(contentsOf: scansDir.appendingPathComponent(imported1), encoding: .utf8)
        let content2 = try String(contentsOf: scansDir.appendingPathComponent(imported2), encoding: .utf8)
        XCTAssertTrue(content1.contains("1.0 2.0 3.0"))
        XCTAssertTrue(content2.contains("1.0 2.0 3.0"))
    }

    // MARK: - Binary PLY with malicious vertex count

    func testBinaryPLYHugeVertexCountReturnsNilWithoutCrash() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("huge_binary.ply")

        // Build a binary PLY with a header claiming a massively huge vertex count
        // but only a tiny body — the guard should reject it without overflow.
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(Int.max)
        property float x
        property float y
        property float z
        end_header

        """.data(using: .ascii)!
        let body = Data(count: 36) // 3 vertices worth of binary data, far less than claimed
        var data = Data()
        data.append(header)
        data.append(body)
        try data.write(to: plyURL)

        let result = PLYParserHelper.parsePointCloudData(at: plyURL)
        XCTAssertNil(result, "Huge vertex count with tiny body should return nil, not crash")
    }

    func testBinaryPLYZeroVertexCountReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("zero_vertex.ply")
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex 0
        property float x
        property float y
        property float z
        end_header

        """.data(using: .ascii)!
        try header.write(to: plyURL)

        let result = PLYParserHelper.parsePointCloudData(at: plyURL)
        XCTAssertNil(result, "Zero vertex count should return nil")
    }

    // MARK: - ASCII PLY property-driven parsing matrix

    func testASCIIPLYParsesReorderedXYZAndRGBWithExtraProperty() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property float z
        property float x
        property uchar red
        property float y
        property uchar green
        property uchar blue
        property float confidence
        end_header
        3.0 1.0 255 2.0 128 0 0.95
        6.0 4.0 100 5.0 200 50 0.85
        """, name: "reordered_ascii.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1, y: 2, z: 3)
        assertColor(pointCloud.colors[0], r: 1, g: 128.0 / 255.0, b: 0)
        assertVertex(pointCloud.vertices[1], x: 4, y: 5, z: 6)
        assertColor(pointCloud.colors[1], r: 100.0 / 255.0, g: 200.0 / 255.0, b: 50.0 / 255.0)
    }

    func testASCIIDoubleCoordinatesNoColorGetsDefaultGray() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property double x
        property double y
        property double z
        end_header
        1.5 -2.5 3.5
        10.0 20.0 30.0
        """, name: "double_no_color.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1.5, y: -2.5, z: 3.5)
        assertVertex(pointCloud.vertices[1], x: 10, y: 20, z: 30)
        assertColor(pointCloud.colors[0], r: 0.5, g: 0.5, b: 0.5)
        assertColor(pointCloud.colors[1], r: 0.5, g: 0.5, b: 0.5)
    }

    func testASCIIFloatColorsNormalizeUnitAndByteRangesPerPoint() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property float red
        property float green
        property float blue
        end_header
        0 0 0 0.2 0.7 1.0
        1 0 0 51.0 178.5 255.0
        """, name: "float_color_ranges.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertColor(pointCloud.colors[0], r: 0.2, g: 0.7, b: 1)
        assertColor(pointCloud.colors[1], r: 51.0 / 255.0, g: 178.5 / 255.0, b: 1)
    }

    func testASCIIPLYAboveDisplayLimitKeepsExistingRenderedPointLimit() throws {
        let displayLimit = 500_000
        let vertexCount = displayLimit + 1
        var data = Data("""
        ply
        format ascii 1.0
        element vertex \(vertexCount)
        property float x
        property float y
        property float z
        end_header

        """.utf8)
        data.reserveCapacity(data.count + vertexCount * 12)
        for index in 0..<vertexCount {
            data.append(contentsOf: "\(index) 0 0\n".utf8)
        }

        let pointCloud = try XCTUnwrap(parsePLY(data: data, name: "above_display_limit_ascii.ply"))
        XCTAssertEqual(pointCloud.pointCount, displayLimit)
        XCTAssertEqual(pointCloud.colors.count, displayLimit)
        assertVertex(pointCloud.vertices[0], x: 0, y: 0, z: 0)
        assertVertex(pointCloud.vertices[displayLimit - 1], x: Float(displayLimit - 1), y: 0, z: 0)
        assertColor(pointCloud.colors[displayLimit - 1], r: 0.5, g: 0.5, b: 0.5)
    }

    func testUTF8ChineseTreeIDHeaderCommentDoesNotBreakParsing() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        comment tree_id 三号果园·苹果树A12
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        5.0 6.0 7.0 255 128 64
        """, name: "chinese_tree.ply"))

        XCTAssertEqual(pointCloud.pointCount, 1)
        assertVertex(pointCloud.vertices[0], x: 5, y: 6, z: 7)
    }

    func testUTF8ChineseCommentImportDoesNotThrow() throws {
        let plyURL = try writeTemporaryPLY(name: "fruit_tree_chinese.ply", content: """
        ply
        format ascii 1.0
        comment tree_id 果树·桃
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        1.0 2.0 3.0 100 150 200
        """)

        let scansDir = plyURL.deletingLastPathComponent().appendingPathComponent("scans", isDirectory: true)
        let importedName = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertTrue(importedName.hasSuffix(".ply"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(importedName).path))
    }

    // MARK: - Binary PLY parsing matrix

    func testBinaryLittleEndianParsesMixedScalarTypesAndExtraProperty() throws {
        var body = Data()
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat64(2))
        body.append(Self.leInt32(3))
        body.append(contentsOf: [255, 128, 0] as [UInt8])
        body.append(Self.leFloat32(0.95))
        body.append(Self.leFloat32(10))
        body.append(Self.leFloat64(20))
        body.append(Self.leInt32(30))
        body.append(contentsOf: [0, 64, 192] as [UInt8])
        body.append(Self.leFloat32(0.3))

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property double y",
                "property int z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
                "property float confidence",
            ],
            body: body
        ), name: "mixed_le.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1, y: 2, z: 3)
        assertColor(pointCloud.colors[0], r: 1, g: 128.0 / 255.0, b: 0)
        assertVertex(pointCloud.vertices[1], x: 10, y: 20, z: 30)
        assertColor(pointCloud.colors[1], r: 0, g: 64.0 / 255.0, b: 192.0 / 255.0)
    }

    func testBinaryBigEndianParsesCoordinatesAndColors() throws {
        var body = Data()
        body.append(Self.beFloat32(1.5))
        body.append(Self.beFloat32(2.5))
        body.append(Self.beFloat32(3.5))
        body.append(contentsOf: [200, 100, 50] as [UInt8])
        body.append(Self.beFloat32(-1))
        body.append(Self.beFloat32(0))
        body.append(Self.beFloat32(5))
        body.append(contentsOf: [10, 20, 30] as [UInt8])

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_big_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
            ],
            body: body
        ), name: "be.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1.5, y: 2.5, z: 3.5)
        assertColor(pointCloud.colors[0], r: 200.0 / 255.0, g: 100.0 / 255.0, b: 50.0 / 255.0)
        assertVertex(pointCloud.vertices[1], x: -1, y: 0, z: 5)
        assertColor(pointCloud.colors[1], r: 10.0 / 255.0, g: 20.0 / 255.0, b: 30.0 / 255.0)
    }

    func testBinaryLittleEndianUShortColorNormalization() throws {
        var body = Data()
        body.append(Self.leFloat32(0))
        body.append(Self.leFloat32(0))
        body.append(Self.leFloat32(0))
        body.append(Self.leUInt16(0))
        body.append(Self.leUInt16(32_768))
        body.append(Self.leUInt16(65_535))
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(1))
        body.append(Self.leUInt16(65_535))
        body.append(Self.leUInt16(0))
        body.append(Self.leUInt16(16_384))

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property ushort red",
                "property ushort green",
                "property ushort blue",
            ],
            body: body
        ), name: "ushort_color_le.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertColor(pointCloud.colors[0], r: 0, g: 32_768.0 / 65_535.0, b: 1)
        assertColor(pointCloud.colors[1], r: 1, g: 0, b: 16_384.0 / 65_535.0)
    }

    // MARK: - Malformed-input rejection matrix

    func testMalformedASCIIPLYInputsReturnNil() throws {
        let malformedCases: [(name: String, content: String)] = [
            ("truncated_row", """
            ply
            format ascii 1.0
            element vertex 2
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            end_header
            1.0 2.0 3.0 255 128 64
            4.0 5.0 6.0
            """),
            ("extra_vertex_columns", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            1.0 2.0 3.0 4.0
            """),
            ("nan_coordinate", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            nan 1.0 2.0
            """),
            ("float32_overflow_extra_property", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            property float confidence
            end_header
            1.0 2.0 3.0 1e100
            """),
            ("inf_coordinate", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            1.0 -inf 2.0
            """),
            ("missing_xyz", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            end_header
            1.0 2.0
            """),
            ("list_property_under_vertex", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            property list uchar int vertex_indices
            end_header
            1.0 2.0 3.0 0
            """),
        ]

        for malformed in malformedCases {
            let pointCloud = try parsePLY(malformed.content, name: "\(malformed.name).ply")
            XCTAssertNil(pointCloud, malformed.name)
        }
    }

    func testTruncatedBinaryBodyReturnsNil() throws {
        var body = Data()
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(2))
        body.append(Self.leFloat32(3))
        body.append(contentsOf: [255, 128, 64] as [UInt8])

        let pointCloud = try parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 3,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
            ],
            body: body
        ), name: "truncated_binary.ply")

        XCTAssertNil(pointCloud)
    }

    // MARK: - PLY test helpers

    private func makeDepthMap(
        width: Int,
        height: Int,
        valueAt: (Int, Int) -> Float
    ) throws -> CVPixelBuffer {
        let pixelBuffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_DepthFloat32
        )
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<Float>.size
        let values = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: Float.self)
        for row in 0..<height {
            for column in 0..<width {
                values[row * stride + column] = valueAt(column, row)
            }
        }
        return pixelBuffer
    }

    private func makeConfidenceMap(
        width: Int,
        height: Int,
        value: UInt8
    ) throws -> CVPixelBuffer {
        let pixelBuffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_OneComponent8
        )
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let values = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            for column in 0..<width {
                values[row * stride + column] = value
            }
        }
        return pixelBuffer
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    private func parsePLY(_ content: String, name: String = "point_cloud.ply") throws -> PointCloudData? {
        try parsePLY(data: Data(content.utf8), name: name)
    }

    private func parsePLY(data: Data, name: String = "point_cloud.ply") throws -> PointCloudData? {
        let url = try writeTemporaryPLY(name: name, data: data)
        return PLYParserHelper.parsePointCloudData(at: url)
    }

    private func writeTemporaryPLY(name: String, content: String) throws -> URL {
        try writeTemporaryPLY(name: name, data: Data(content.utf8))
    }

    private func writeTemporaryPLY(name: String, data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeDepthMap(width: Int, height: Int, value: Float) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent32Float,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.size
        let values = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: Float.self)
        for row in 0..<height {
            for column in 0..<width {
                values[row * stride + column] = value
            }
        }
        return buffer
    }

    private func binaryPLYData(
        format: String,
        vertexCount: Int,
        properties: [String],
        body: Data
    ) -> Data {
        var data = Data("""
        ply
        format \(format) 1.0
        element vertex \(vertexCount)
        \(properties.joined(separator: "\n"))
        end_header

        """.utf8)
        data.append(body)
        return data
    }

    private func assertVertex(
        _ actual: SCNVector3,
        x: Float,
        y: Float,
        z: Float,
        accuracy: Float = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, z, accuracy: accuracy, file: file, line: line)
    }

    private func assertColor(
        _ actual: PointCloudColor,
        r: Float,
        g: Float,
        b: Float,
        accuracy: Float = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.r, r, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.g, g, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.b, b, accuracy: accuracy, file: file, line: line)
    }

    private func renderedPointCloudColors(from node: SCNNode) throws -> [PointCloudColor] {
        let source = try XCTUnwrap(node.geometry?.sources(for: .color).first)
        XCTAssertTrue(source.usesFloatComponents)
        XCTAssertEqual(source.componentsPerVector, 4)
        XCTAssertEqual(source.bytesPerComponent, MemoryLayout<Float>.size)

        return source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).map { index in
                let baseOffset = source.dataOffset + index * source.dataStride
                return PointCloudColor(
                    r: bytes.loadUnaligned(
                        fromByteOffset: baseOffset,
                        as: Float.self
                    ),
                    g: bytes.loadUnaligned(
                        fromByteOffset: baseOffset + MemoryLayout<Float>.size,
                        as: Float.self
                    ),
                    b: bytes.loadUnaligned(
                        fromByteOffset: baseOffset + MemoryLayout<Float>.size * 2,
                        as: Float.self
                    ),
                    a: bytes.loadUnaligned(
                        fromByteOffset: baseOffset + MemoryLayout<Float>.size * 3,
                        as: Float.self
                    )
                )
            }
        }
    }

    // MARK: - Binary byte-level helpers (endianness-explicit)

    private static func leFloat32(_ value: Float) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ])
    }

    private static func leFloat64(_ value: Double) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 32) & 0xFF),
            UInt8((bits >> 40) & 0xFF),
            UInt8((bits >> 48) & 0xFF),
            UInt8((bits >> 56) & 0xFF),
        ])
    }

    private static func leInt32(_ value: Int32) -> Data {
        let bits = UInt32(bitPattern: value)
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ])
    }

    private static func leUInt16(_ value: UInt16) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
        ])
    }

    private static func beFloat32(_ value: Float) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8(bits & 0xFF),
        ])
    }
}

private actor ScanGuidanceDismissDelayDriver {
    private var nextRequestID = 0
    private var queuedRequests: [Int] = []
    private var requestWaiters: [CheckedContinuation<Int, Never>] = []
    private var delayContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        let request = nextRequestID
        nextRequestID += 1

        if requestWaiters.isEmpty {
            queuedRequests.append(request)
        } else {
            requestWaiters.removeFirst().resume(returning: request)
        }

        await withCheckedContinuation { continuation in
            delayContinuations[request] = continuation
        }
    }

    func nextRequest() async -> Int {
        if !queuedRequests.isEmpty {
            return queuedRequests.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resume(request: Int) {
        guard let continuation = delayContinuations.removeValue(forKey: request) else {
            preconditionFailure("No pending guidance dismissal for request \(request)")
        }
        continuation.resume()
    }
}
