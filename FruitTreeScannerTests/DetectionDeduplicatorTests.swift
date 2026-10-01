import XCTest
import CoreML
import CoreVideo
@testable import FruitTreeScanner

final class DetectionDeduplicatorTests: XCTestCase {

    func testRegressionYOLOUsesActualNonSquareInputSize() throws {
        let output = try MLMultiArray(shape: [1, 30, 1], dataType: .float32)
        for i in 0..<output.count { output[i] = 0 }
        for (channel, value) in [0: 320.0, 1: 240.0, 2: 128.0, 3: 96.0, 4: 0.95] {
            output[[0, NSNumber(value: channel), 0]] = NSNumber(value: value)
        }
        let parsed = ImageDetector.parseYOLOMultiArray(
            output, timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: FruitCategory.customModelLabelOrder),
            modelInputSize: CGSize(width: 640, height: 480)
        )
        let box = try XCTUnwrap(parsed.fruits.first).boundingBox
        XCTAssertEqual(parsed.fruits.count, 1)
        XCTAssertEqual(box.minX, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.minY, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.height, 0.2, accuracy: 0.0001)
        XCTAssertNil(YOLOParserSupport.makeVisionBoundingBox(centerX: 320, centerY: 240, width: 128, height: 96, modelInputSize: .zero))
    }

    func testRegressionProductionModelInferenceSmoke() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "FruitsDetector", withExtension: "mlmodelc"))
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: config)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 320, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixels)])
        let output = try model.prediction(from: input)
        let value = try XCTUnwrap(output.featureValue(for: "var_910")?.multiArrayValue)
        XCTAssertEqual(value.shape.map(\.intValue), [1, 30, 2100])
        for anchor in 0..<2100 {
            let score = YOLOParserSupport.bestClassScore(in: value, classCount: 26, anchorIndex: anchor, channelAxis: 1).confidence
            XCTAssertTrue(score.isFinite)
        }
    }

    func testRegressionTransposedYOLOContract() throws {
        let output = try MLMultiArray(shape: [1, 2100, 30], dataType: .float32)
        for i in 0..<output.count { output[i] = 0 }
        for (channel, value) in [0: 160.0, 1: 160.0, 2: 64.0, 3: 64.0, 4: 0.95] {
            output[[0, 0, NSNumber(value: channel)]] = NSNumber(value: value)
        }
        let parsed = ImageDetector.parseYOLOMultiArray(
            output, timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: FruitCategory.customModelLabelOrder)
        )
        XCTAssertEqual(parsed.fruits.count, 1, "A transposed tensor with a valid 26-class contract must retain the apple")
    }

    private func pinholeIntrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(fx, 0, 0),
            SIMD3<Float>(0, fy, 0),
            SIMD3<Float>(cx, cy, 1)
        )
    }

    private func makeDepthMap(width: Int, height: Int, fillValue: Float) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let rowFloats = bytesPerRow / MemoryLayout<Float>.size
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            for y in 0..<height {
                for x in 0..<width {
                    floatBuffer[y * rowFloats + x] = fillValue
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func makeConfidenceMap(width: Int, height: Int, fillValue: UInt8) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                let rowPointer = baseAddress
                    .advanced(by: y * bytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    rowPointer[x] = fillValue
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func testDeduplicate2DEmpty() {
        let result = DetectionDeduplicator.deduplicate2D([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(DetectionDeduplicator.deduplicate2D(observations: []).isEmpty)
    }

    func testObservationStableEvidencePreservesFrameIdentityAndRecentWindow() {
        let detections = [10.0, 10.6, 30.0, 30.6].enumerated().map { index, time in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: index < 2 ? 0.2 : 0.6, y: 0.3, width: 0.1, height: 0.1),
                confidence: index.isMultiple(of: 2) ? 0.91 : 0.96,
                timestamp: time
            )
        }
        let observations = detections.map { $0.resolvedObservation(frameID: FrameID()) }
        let all = DetectionDeduplicator.stableEvidenceDetections(observations: observations)
        XCTAssertEqual(all.map(\.id), observations.map(\.id))
        XCTAssertEqual(all.map(\.frameID), observations.map(\.frameID))
        XCTAssertEqual(all.map(\.rejectionReasons), observations.map(\.rejectionReasons))
        XCTAssertEqual(
            DetectionDeduplicator.stableDetections(observations: observations).map(\.id),
            [observations[1].id, observations[3].id]
        )
        XCTAssertEqual(
            DetectionDeduplicator.stableEvidenceDetections(observations: observations, recentOnly: true).map(\.id),
            [observations[2].id, observations[3].id]
        )
        XCTAssertEqual(DetectionDeduplicator.stableTrackCount(observations: observations), 1)
    }

    func testObservationCompactionKeepsDurationAndDistinctFruitWithinSampleLimit() {
        // The first pair is too brief. A later visit to the same box must not
        // expand the archive; the spatially distinct fruit must remain present.
        let times = [0.0, 0.1, 0.6, 0.7, 1.2, 20.0, 20.7, 25.0, 25.7]
        let detections = times.enumerated().map { index, time in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: index < 7 ? 0.2 : 0.7, y: 0.3, width: 0.1, height: 0.1),
                confidence: 0.99 - Float(index) * 0.01,
                timestamp: time
            )
        }
        let observations = detections.map { $0.resolvedObservation() }
        let compacted = DetectionDeduplicator.compactStableEvidenceDetections(
            observations: observations, maxObservationsPerTrack: 2
        )
        let expectedIDs = [observations[1].id, observations[2].id, observations[7].id, observations[8].id]
        XCTAssertEqual(compacted.map(\.id), expectedIDs)
        XCTAssertEqual(
            DetectionDeduplicator.compactStableEvidenceDetections(detections, maxObservationsPerTrack: 2).map(\.id),
            expectedIDs
        )
        let minimumThree = DetectionDeduplicator.compactStableEvidenceDetections(
            observations: observations, minimumObservations: 3, maxObservationsPerTrack: 1
        )
        XCTAssertEqual(minimumThree.map(\.id), Array(observations.prefix(3)).map(\.id))
    }

    func testLegacySelectionRetainsOriginalBufferFacadesAndRepeatedIdentities() throws {
        let depth = try XCTUnwrap(makeDepthMap(width: 16, height: 16, fillValue: 2))
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.7,
            timestamp: 10,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: pinholeIntrinsics(fx: 16, fy: 16, cx: 8, cy: 8),
            imageSize: CGSize(width: 16, height: 16),
            depthMap: depth
        )
        let repeated = [detection, detection]
        let stable = DetectionDeduplicator.stableDetections(repeated, minimumObservations: 1, minimumConfidence: 0.6)
        let evidence = DetectionDeduplicator.stableEvidenceDetections(repeated, minimumObservations: 1, minimumConfidence: 0.6)
        let compacted = DetectionDeduplicator.compactStableEvidenceDetections(repeated, minimumObservations: 1, minimumConfidence: 0.6)
        let deduplicated = DetectionDeduplicator.deduplicate2D(repeated)
        XCTAssertEqual(stable.map(\.id), [detection.id, detection.id])
        XCTAssertEqual(evidence.map(\.id), [detection.id, detection.id])
        XCTAssertEqual(compacted.map(\.id), [detection.id])
        XCTAssertEqual(deduplicated.map(\.id), [detection.id])
        XCTAssertEqual(DetectionDeduplicator.stableTrackCount(repeated, minimumObservations: 1, minimumConfidence: 0.6), 2)

        // Changing the test-owned buffer after selection distinguishes the
        // original legacy facade from a newly sampled Observation facade.
        CVPixelBufferLockBaseAddress(depth, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(depth))
        for row in 0..<16 {
            let values = base.advanced(by: row * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)
            for column in 0..<16 { values[column] = 4 }
        }
        CVPixelBufferUnlockBaseAddress(depth, [])
        for selected in stable + evidence + compacted + deduplicated {
            XCTAssertNil(selected.observation)
            XCTAssertTrue(selected.hasAlignedDepthContext)
            let samples = selected.resolvedObservation().projectionDepthSamples
            XCTAssertFalse(samples.isEmpty)
            XCTAssertTrue(samples.allSatisfy { $0 == 4 })
        }
    }

    func testDeduplicate2DSingleDetection() {
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.9
        )
        let result = DetectionDeduplicator.deduplicate2D([detection])
        XCTAssertEqual(result.count, 1)
    }

    func testStableTrackCountIgnoresSingleHighConfidenceDetection() {
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.95,
            timestamp: 10
        )

        let count = DetectionDeduplicator.stableTrackCount([detection])

        XCTAssertEqual(count, 0, "单帧高置信度检测不能直接显示为果数")
    }

    func testStableTrackCountAcceptsRepeatedStableDetections() {
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.92,
                timestamp: 10
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.315, y: 0.305, width: 0.19, height: 0.21),
                confidence: 0.91,
                timestamp: 10.6
            )
        ]

        let count = DetectionDeduplicator.stableTrackCount(detections)

        XCTAssertEqual(count, 1, "连续帧中位置和尺寸稳定的检测才计入实时果数")
    }

    func testStableDetectionsKeepsEarlierTracksAcrossFullScan() {
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.20, y: 0.20, width: 0.18, height: 0.18),
                confidence: 0.92,
                timestamp: 10
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.21, y: 0.20, width: 0.18, height: 0.18),
                confidence: 0.91,
                timestamp: 10.7
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.62, y: 0.48, width: 0.16, height: 0.16),
                confidence: 0.93,
                timestamp: 30
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.63, y: 0.48, width: 0.16, height: 0.16),
                confidence: 0.90,
                timestamp: 30.7
            )
        ]

        let stableDetections = DetectionDeduplicator.stableDetections(detections)

        XCTAssertEqual(stableDetections.count, 2, "最终融合不能只保留扫描最后几秒的稳定果实")
    }

    func testStableEvidenceDetectionsReturnsAllObservationsInStableTrack() {
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.92,
                timestamp: 10
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.31, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.91,
                timestamp: 10.7
            )
        ]

        let evidence = DetectionDeduplicator.stableEvidenceDetections(detections)

        XCTAssertEqual(evidence.count, 2, "融合和遮挡估计需要稳定轨迹中的多帧证据")
    }

    func testStableEvidenceDetectionsDoesNotMerge3DSeparatedObservations() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.95,
                timestamp: 10,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.34, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.93,
                timestamp: 10.6,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]

        let evidence = DetectionDeduplicator.stableEvidenceDetections(detections)

        XCTAssertTrue(
            evidence.isEmpty,
            "2D 重叠但 3D 空间已分离的果实不能互相凑成稳定轨迹"
        )
        XCTAssertTrue(DetectionDeduplicator.stableEvidenceDetections(
            observations: detections.map { $0.resolvedObservation() }
        ).isEmpty)
    }

    func testStableEvidenceDetectionsAccepts3DAssociatedObservationsAcrossViewShift() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        var shiftedCameraTransform = matrix_identity_float4x4
        shiftedCameraTransform.columns.3.x = -2.304
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.95,
                timestamp: 10,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.60, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.93,
                timestamp: 10.6,
                cameraTransform: shiftedCameraTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]

        let evidence = DetectionDeduplicator.stableEvidenceDetections(detections)

        XCTAssertEqual(
            evidence.count,
            2,
            "同一世界位置的果实跨视角移动到画面不同区域时，仍应形成稳定轨迹"
        )
    }

    func testDeduplicate2DMerges3DAssociatedDetectionsAcrossViewShift() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        var shiftedCameraTransform = matrix_identity_float4x4
        shiftedCameraTransform.columns.3.x = -2.304
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.95,
            timestamp: 10,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let d2 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.60, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.93,
            timestamp: 10.6,
            cameraTransform: shiftedCameraTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        let result = DetectionDeduplicator.deduplicate2D([d1, d2])

        XCTAssertEqual(
            result.count,
            1,
            "3D 空间已确认是同一果实时，即使 2D 框相距较远也应去重"
        )
        XCTAssertEqual(
            DetectionDeduplicator.deduplicate2D(observations: [d1, d2].map { $0.resolvedObservation() }).map(\.id),
            [d1.id]
        )
    }

    func testInvalidDepthDoesNotCreate3DAssociationFromFallbackProjection() {
        let invalidDepthMap = makeDepthMap(width: 256, height: 192, fillValue: 0.0)
        XCTAssertNotNil(invalidDepthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        var shiftedCameraTransform = matrix_identity_float4x4
        shiftedCameraTransform.columns.3.x = -2.304
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.95,
                timestamp: 10,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: invalidDepthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.60, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.93,
                timestamp: 10.6,
                cameraTransform: shiftedCameraTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: invalidDepthMap
            )
        ]

        XCTAssertTrue(
            DetectionDeduplicator.stableEvidenceDetections(detections).isEmpty,
            "无有效 ROI 深度时不能借默认投影确认稳定果实"
        )
        XCTAssertEqual(
            DetectionDeduplicator.deduplicate2D(detections).count,
            2,
            "无有效 ROI 深度时不能借默认投影把远距离 2D 观测合并"
        )
        let observations = detections.map { $0.resolvedObservation() }
        XCTAssertTrue(DetectionDeduplicator.stableEvidenceDetections(observations: observations).isEmpty)
        XCTAssertEqual(DetectionDeduplicator.deduplicate2D(observations: observations).map(\.id), detections.map(\.id))
    }

    func testLowConfidenceDepthDoesNotCreate3DAssociation() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let confidenceMap = makeConfidenceMap(width: 256, height: 192, fillValue: 0)
        XCTAssertNotNil(depthMap)
        XCTAssertNotNil(confidenceMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        var shiftedCameraTransform = matrix_identity_float4x4
        shiftedCameraTransform.columns.3.x = -2.304
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.95,
                timestamp: 10,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap,
                depthConfidenceMap: confidenceMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.60, y: 0.30, width: 0.20, height: 0.20),
                confidence: 0.93,
                timestamp: 10.6,
                cameraTransform: shiftedCameraTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap,
                depthConfidenceMap: confidenceMap
            )
        ]

        XCTAssertTrue(
            DetectionDeduplicator.stableEvidenceDetections(detections).isEmpty,
            "低置信度 ROI 深度不能确认跨视角稳定轨迹"
        )
        XCTAssertEqual(
            DetectionDeduplicator.deduplicate2D(detections).count,
            2,
            "低置信度 ROI 深度不能把远距离 2D 观测合并"
        )
        let observations = detections.map { $0.resolvedObservation() }
        XCTAssertTrue(DetectionDeduplicator.stableEvidenceDetections(observations: observations).isEmpty)
        XCTAssertEqual(DetectionDeduplicator.deduplicate2D(observations: observations).map(\.id), detections.map(\.id))
    }

    func testDeduplicate2DOverlapping() {
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.9
        )
        let d2 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.32, y: 0.32, width: 0.2, height: 0.2),
            confidence: 0.7
        )
        let result = DetectionDeduplicator.deduplicate2D([d1, d2])
        XCTAssertEqual(result.count, 1, "重叠检测应去重为1个")
        XCTAssertEqual(result.first?.confidence, 0.9, "应保留高置信度")
    }

    func testDeduplicate2DDoesNotMergeOverlappingBoxesFromDistantFrames() {
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.9,
            timestamp: 10
        )
        let d2 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.7,
            timestamp: 13
        )

        XCTAssertEqual(
            DetectionDeduplicator.deduplicate2D([d1, d2]).count,
            2,
            "跨视角的远时刻检测不能只凭相同 2D 框合并"
        )
    }

    func testDeduplicate2DKeepsOverlappingAlignedDetectionsWhen3DSeparated() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let d2 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.34, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.7,
            timestamp: 10.5,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        let result = DetectionDeduplicator.deduplicate2D([d1, d2])

        XCTAssertEqual(result.count, 2, "有对齐深度时，3D 分离的重叠 2D 框不应互相抑制")
    }

    func testDeduplicate2DMergesOverlappingAlignedDetectionsWhen3DClose() {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let d2 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.305, y: 0.30, width: 0.20, height: 0.20),
            confidence: 0.7,
            timestamp: 10.5,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        let result = DetectionDeduplicator.deduplicate2D([d1, d2])

        XCTAssertEqual(result.count, 1, "3D 位置接近时仍应去重重复观测")
    }

    func testDeduplicate2DDifferentCategories() {
        let d1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.9
        )
        let d2 = DetectedFruit(
            category: .orange,
            boundingBox: CGRect(x: 0.32, y: 0.32, width: 0.2, height: 0.2),
            confidence: 0.7
        )
        let result = DetectionDeduplicator.deduplicate2D([d1, d2])
        XCTAssertEqual(result.count, 2, "不同类别不应去重")
    }

    func testRetentionPolicyKeepsAllDetectionsFromRecentFrames() {
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
                confidence: 0.9,
                timestamp: 1
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.1, height: 0.1),
                confidence: 0.8,
                timestamp: 2
            ),
            DetectedFruit(
                category: .pear,
                boundingBox: CGRect(x: 0.3, y: 0.1, width: 0.1, height: 0.1),
                confidence: 0.7,
                timestamp: 2
            ),
            DetectedFruit(
                category: .orange,
                boundingBox: CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.1),
                confidence: 0.6,
                timestamp: 3
            ),
        ]

        let retained = DetectionRetentionPolicy.trimmedByFrameLimit(detections, maxFrameCount: 2)

        XCTAssertEqual(retained.count, 3)
        XCTAssertFalse(retained.contains { $0.timestamp == 1 })
        XCTAssertEqual(retained.filter { $0.timestamp == 2 }.count, 2)
        XCTAssertEqual(retained.filter { $0.timestamp == 3 }.count, 1)
        let observations = detections.map { $0.resolvedObservation() }
        let native = DetectionRetentionPolicy.trimmedByFrameLimit(observations: observations, maxFrameCount: 2)
        XCTAssertEqual(native.map(\.id), Array(observations.suffix(3)).map(\.id))
        XCTAssertEqual(native.map(\.frameID), Array(observations.suffix(3)).map(\.frameID))
        XCTAssertTrue(DetectionRetentionPolicy.trimmedByFrameLimit(observations: observations, maxFrameCount: 0).isEmpty)
    }

    func testRetentionPolicyDropsAllWhenFrameLimitIsZero() {
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
                confidence: 0.9,
                timestamp: 1
            )
        ]

        XCTAssertTrue(DetectionRetentionPolicy.trimmedByFrameLimit(detections, maxFrameCount: 0).isEmpty)
    }

    func testComputeIoUNoOverlap() {
        let a = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let b = CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)
        let iou = DetectionDeduplicator.computeIoU(a, b)
        XCTAssertEqual(iou, 0, "不重叠时 IoU 应为 0")
    }

    func testComputeIoUFullOverlap() {
        let a = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let iou = DetectionDeduplicator.computeIoU(a, a)
        XCTAssertEqual(iou, 1.0, accuracy: 0.01, "完全重叠时 IoU 应为 1.0")
    }

    func testDepthSamplePointMapsNormalizedCoordinates() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0.5, y: 0.25),
            imageSize: CGSize(width: 1920, height: 1080),
            depthSize: CGSize(width: 256, height: 192)
        )

        XCTAssertEqual(point.x, 128, accuracy: 0.01)
        XCTAssertEqual(point.y, 144, accuracy: 0.01)
    }

    func testDeduplicate3DMergesNearbyTracks() {
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.8, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.02, 0, 1), confidence: 0.7, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.4, 0, 1), confidence: 0.9, source: .imageOnly),
        ]

        let deduplicated = ValidatedFruit.deduplicate3D(fruits, distanceThreshold: 0.05)

        XCTAssertEqual(deduplicated.count, 2, "近距离 3D 观测应合并为同一果实轨迹")
    }

    func testDeduplicate3DPrefersFusedRepresentative() {
        let imageOnly = ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.95, source: .imageOnly)
        let fused = ValidatedFruit(category: .apple, position: SIMD3<Float>(0.01, 0, 1), confidence: 0.7, source: .fused)

        let deduplicated = ValidatedFruit.deduplicate3D([imageOnly, fused], distanceThreshold: 0.05)

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated.first?.source, .fused, "融合验证结果应优先作为轨迹代表")
    }

    func testDeduplicate3DPromotesRepeatedImageOnlyTrack() throws {
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.72, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.015, 0.004, 1), confidence: 0.68, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.025, -0.003, 1), confidence: 0.64, source: .imageOnly),
        ]

        let deduplicated = ValidatedFruit.deduplicate3D(fruits, distanceThreshold: 0.05)

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated.first?.source, .trackedImage, "多帧稳定图像轨迹应比单帧 imageOnly 更可靠")
        XCTAssertEqual(try XCTUnwrap(deduplicated.first?.source).countWeight, 0.75, accuracy: 0.001)
    }

    func testDeduplicate3DKeepsSingleImageOnlySource() {
        let fruit = ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 1),
            confidence: 0.8,
            source: .imageOnly
        )

        let deduplicated = ValidatedFruit.deduplicate3D([fruit], distanceThreshold: 0.05)

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated.first?.source, .imageOnly)
    }

    func testDeduplicate3DUsesAdaptiveThresholdForImageProjectionDrift() {
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.75, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.065, 0, 1), confidence: 0.68, source: .imageOnly),
        ]

        let deduplicated = ValidatedFruit.deduplicate3D(fruits)

        XCTAssertEqual(deduplicated.count, 1, "跨视角 imageOnly 深度投影有小幅漂移时应归为同一轨迹")
        XCTAssertEqual(deduplicated.first?.source, .trackedImage)
    }

    func testDeduplicate3DDoesNotMergeNearbyDistinctImageTracks() {
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.9, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.095, 0, 1), confidence: 0.85, source: .imageOnly),
        ]

        let deduplicated = ValidatedFruit.deduplicate3D(fruits)

        XCTAssertEqual(deduplicated.count, 2, "自适应漂移阈值不能把相邻果实合并")
    }

    func testDeduplicate3DKeepsFusedTracksStrictlySeparated() {
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 1), confidence: 0.8, source: .fused),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.065, 0, 1), confidence: 0.78, source: .fused),
        ]

        let deduplicated = ValidatedFruit.deduplicate3D(fruits)

        XCTAssertEqual(deduplicated.count, 2, "fused 轨迹位置更可信，应保持原来的保守 3D 合并阈值")
    }

    func testParseYOLOMultiArrayProducesFruitDetectionAndAppliesNMS() throws {
        let output = try MLMultiArray(shape: [1, 30, 2], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 160,
            centerY: 160,
            width: 64,
            height: 64,
            classIndex: 0,
            confidence: 0.92
        )
        setYOLOPrediction(
            output,
            anchor: 1,
            centerX: 162,
            centerY: 162,
            width: 64,
            height: 64,
            classIndex: 0,
            confidence: 0.70
        )

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(
                forRuntimeLabels: FruitCategory.customModelLabelOrder
            )
        )

        XCTAssertEqual(parsed.modelCandidateCount, 2)
        XCTAssertEqual(parsed.confidenceFilteredCount, 0)
        XCTAssertEqual(parsed.unmappedObservationCount, 0)
        XCTAssertEqual(parsed.fruits.count, 1, "Overlapping YOLO boxes should be reduced by NMS")
        XCTAssertEqual(parsed.fruits[0].category, .apple)
        XCTAssertEqual(parsed.fruits[0].confidence, 0.92, accuracy: 0.001)
        XCTAssertEqual(parsed.fruits[0].boundingBox.origin.x, 0.4, accuracy: 0.001)
        XCTAssertEqual(parsed.fruits[0].boundingBox.origin.y, 0.4, accuracy: 0.001)
        XCTAssertEqual(parsed.fruits[0].boundingBox.width, 0.2, accuracy: 0.001)
        XCTAssertEqual(parsed.fruits[0].boundingBox.height, 0.2, accuracy: 0.001)
    }

    func testParseYOLOMultiArrayUsesRuntimeLabelsForWrongOrderModel() throws {
        let output = try MLMultiArray(shape: [1, 30, 2], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 160,
            centerY: 160,
            width: 64,
            height: 64,
            classIndex: 0,
            confidence: 0.92
        )
        setYOLOPrediction(
            output,
            anchor: 1,
            centerX: 224,
            centerY: 224,
            width: 48,
            height: 48,
            classIndex: 1,
            confidence: 0.88
        )
        var runtimeLabels = FruitCategory.customModelLabelOrder
        runtimeLabels.swapAt(0, 1)

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(
                forRuntimeLabels: runtimeLabels
            )
        )

        XCTAssertEqual(parsed.modelCandidateCount, 2)
        XCTAssertEqual(parsed.thresholdPassedCount, 2)
        XCTAssertEqual(parsed.fruits.map(\.category), [.orange, .apple])
        XCTAssertEqual(parsed.mappedCategories, ["orange", "apple"])
        XCTAssertEqual(parsed.unmappedObservationCount, 0)
        XCTAssertTrue(parsed.unmappedLabels.isEmpty)
        XCTAssertEqual(parsed.rawPredictions.map(\.label), ["orange", "apple"])
        XCTAssertEqual(parsed.filteredPredictions.map(\.label), ["orange", "apple"])
        XCTAssertNil(parsed.labelMappingFailureReason)
    }

    func testParseYOLOMultiArrayMapsSixClassRuntimeLabelSubset() throws {
        let output = try MLMultiArray(shape: [1, 10, 6], dataType: .float32)
        for classIndex in 0..<6 {
            setYOLOPrediction(
                output,
                anchor: classIndex,
                centerX: Float(32 + classIndex * 48),
                centerY: 160,
                width: 24,
                height: 24,
                classIndex: classIndex,
                confidence: 0.92
            )
        }
        let labels = ["apple", "orange", "pear", "persimmon", "grape", "strawberry"]
        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "subset")
        XCTAssertEqual(parsed.fruits.map(\.category), [.apple, .orange, .pear, .persimmon, .grape, .strawberry])
        XCTAssertEqual(parsed.mappedCategories, labels)
        XCTAssertEqual(parsed.unmappedObservationCount, 0)
    }

    func testParseYOLOMultiArrayMapsReorderedSixClassRuntimeLabels() throws {
        let labels = ["grape", "apple", "strawberry", "pear", "orange", "persimmon"]
        let output = try MLMultiArray(shape: [1, 10, 6], dataType: .float32)
        for classIndex in 0..<6 {
            setYOLOPrediction(output, anchor: classIndex, centerX: Float(32 + classIndex * 48), centerY: 160, width: 24, height: 24, classIndex: classIndex, confidence: 0.92)
        }

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)
        )

        XCTAssertEqual(parsed.fruits.map(\.category), [.grape, .apple, .strawberry, .pear, .orange, .persimmon])
        XCTAssertNil(parsed.labelMappingFailureReason)
    }

    func testParseYOLOMultiArrayFailsClosedWithoutSixClassRuntimeLabels() throws {
        let output = try MLMultiArray(shape: [1, 10, 1], dataType: .float32)
        setYOLOPrediction(output, anchor: 0, centerX: 160, centerY: 160, width: 64, height: 64, classIndex: 2, confidence: 0.92)

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: .unavailable
        )

        XCTAssertTrue(parsed.fruits.isEmpty)
        XCTAssertFalse(try XCTUnwrap(parsed.labelMappingFailureReason).isEmpty)
    }

    func testParseYOLOMultiArrayRecordsUnknownRuntimeLabelAsUnmapped() throws {
        let output = try MLMultiArray(shape: [1, 6, 2], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 96,
            centerY: 96,
            width: 48,
            height: 48,
            classIndex: 0,
            confidence: 0.92
        )
        setYOLOPrediction(
            output,
            anchor: 1,
            centerX: 224,
            centerY: 224,
            width: 48,
            height: 48,
            classIndex: 1,
            confidence: 0.88
        )

        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(
            forRuntimeLabels: ["banana", "unknown_fruit"]
        )
        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "runtimeMapped")
        XCTAssertTrue(diagnostics.modelLabelCompatibilityWarnings.contains {
            $0.contains("Unsupported runtime labels")
        })
        XCTAssertTrue(parsed.fruits.isEmpty)
        XCTAssertTrue(parsed.mappedCategories.isEmpty)
        XCTAssertEqual(parsed.unmappedObservationCount, 2)
        XCTAssertEqual(parsed.unmappedLabels, ["banana", "unknown_fruit"])
    }

    func testParseYOLOMultiArrayRejectsRuntimeLabelCountMismatch() throws {
        let output = try MLMultiArray(shape: [1, 6, 1], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 160,
            centerY: 160,
            width: 64,
            height: 64,
            classIndex: 1,
            confidence: 0.92
        )

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: ["apple"])
        )

        XCTAssertTrue(parsed.fruits.isEmpty)
        XCTAssertEqual(parsed.unmappedObservationCount, 0)
        XCTAssertTrue(parsed.unmappedLabels.isEmpty)
        XCTAssertTrue(try XCTUnwrap(parsed.labelMappingFailureReason).contains("does not match output class count"))
    }

    func testParseYOLOMultiArrayUsesLegacyFixedOrderOnlyWhenRuntimeLabelsUnavailable() throws {
        let output = try MLMultiArray(shape: [1, 30, 1], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 160,
            centerY: 160,
            width: 64,
            height: 64,
            classIndex: 1,
            confidence: 0.92
        )

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: .confirmedLegacy26ClassContract
        )

        XCTAssertEqual(parsed.fruits.map(\.category), [.orange])
        XCTAssertEqual(parsed.rawPredictions.map(\.label), [FruitCategory.orange.displayName])
    }

    func testParseYOLOMultiArrayReportsConfidenceFilteredCandidates() throws {
        let output = try MLMultiArray(shape: [1, 30, 1], dataType: .float32)
        setYOLOPrediction(
            output,
            anchor: 0,
            centerX: 160,
            centerY: 160,
            width: 64,
            height: 64,
            classIndex: 0,
            confidence: 0.30
        )

        let parsed = ImageDetector.parseYOLOMultiArray(
            output,
            timestamp: 10,
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5),
            labelDiagnostics: .confirmedLegacy26ClassContract
        )

        XCTAssertEqual(parsed.modelCandidateCount, 1)
        XCTAssertEqual(parsed.confidenceFilteredCount, 1)
        XCTAssertTrue(parsed.fruits.isEmpty)
    }

    private func setYOLOPrediction(
        _ output: MLMultiArray,
        anchor: Int,
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
        classIndex: Int,
        confidence: Float
    ) {
        output[[NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: anchor)]] = NSNumber(value: centerX)
        output[[NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: anchor)]] = NSNumber(value: centerY)
        output[[NSNumber(value: 0), NSNumber(value: 2), NSNumber(value: anchor)]] = NSNumber(value: width)
        output[[NSNumber(value: 0), NSNumber(value: 3), NSNumber(value: anchor)]] = NSNumber(value: height)
        output[[NSNumber(value: 0), NSNumber(value: classIndex + 4), NSNumber(value: anchor)]] = NSNumber(value: confidence)
    }
}
