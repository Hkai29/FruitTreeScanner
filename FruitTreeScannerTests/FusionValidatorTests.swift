import XCTest
import CoreVideo
@testable import FruitTreeScanner

final class FusionValidatorTests: XCTestCase {

    // MARK: - Helpers

    private let identityTransform = matrix_identity_float4x4

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
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowFloats = bytesPerRow / MemoryLayout<Float>.size
            for y in 0 ..< height {
                for x in 0 ..< width {
                    floatBuffer[y * rowFloats + x] = fillValue
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func setDepth(_ depthMap: CVPixelBuffer, x: Int, y: Int, value: Float) {
        CVPixelBufferLockBaseAddress(depthMap, [])
        defer { CVPixelBufferUnlockBaseAddress(depthMap, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let rowFloats = bytesPerRow / MemoryLayout<Float>.size
        floatBuffer[clampedY * rowFloats + clampedX] = value
    }

    private func setDepthAtDetectionGrid(
        _ depthMap: CVPixelBuffer,
        detection: DetectedFruit,
        row: Int,
        col: Int,
        sampleGrid: Int = 9,
        imageSize: CGSize,
        value: Float
    ) {
        let normalizedPoint = CGPoint(
            x: detection.boundingBox.origin.x
                + detection.boundingBox.width * (CGFloat(col) + 0.5) / CGFloat(sampleGrid),
            y: detection.boundingBox.origin.y
                + detection.boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(sampleGrid)
        )
        let depthPoint = FusionValidator.depthSamplePoint(
            normalizedPoint: normalizedPoint,
            imageSize: imageSize,
            depthSize: CGSize(
                width: CVPixelBufferGetWidth(depthMap),
                height: CVPixelBufferGetHeight(depthMap)
            )
        )
        setDepth(depthMap, x: Int(depthPoint.x), y: Int(depthPoint.y), value: value)
    }

    private func appleCandidate(at position: SIMD3<Float>) -> FruitCandidate {
        FruitCandidate(
            position: position,
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )
    }

    private func appleDetection(confidence: Float = 0.9) -> DetectedFruit {
        DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: confidence
        )
    }

    // MARK: - B.1 nil depthMap → imageOnly

    func testValidateNilDepthMapReturnsImageOnly() {
        let validator = FusionValidator(config: .default)
        let detections = [appleDetection()]
        let candidates: [FruitCandidate] = []

        let result = validator.validate(
            detections: detections,
            candidates: candidates,
            depthMap: nil,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            cameraTransform: identityTransform,
            imageSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(result.count, 1, "应返回 1 个验证结果")
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly, "nil depthMap 且无候选时应为 imageOnly")
    }

    func testValidateNilDepthMapWithNoMatchReturnsImageOnly() {
        let validator = FusionValidator(config: .default)
        let detections = [appleDetection()]
        let farCandidate = appleCandidate(at: SIMD3<Float>(100, 100, 100))

        let result = validator.validate(
            detections: detections,
            candidates: [farCandidate],
            depthMap: nil,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            cameraTransform: identityTransform,
            imageSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly, "候选距离太远应退化为 imageOnly")
    }

    // MARK: - B.2 fused match (candidate at projected position)

    func testValidateFusedWhenCandidateWithinTolerance() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap, "应能创建合成深度图")

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let projectedPosition = SIMD3<Float>(0, 0, 2)
        let candidate = FruitCandidate(
            position: projectedPosition,
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )

        let detector = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let result = validator.validate(
            detections: [detector],
            candidates: [candidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.fused, "候选在投影位置且有效应被融合")
        XCTAssertEqual(result.first?.position, candidate.position, "融合结果应使用候选位置")
        XCTAssertEqual(result.first?.category, FruitCategory.apple)
    }

    func testValidateDownWeightsLowDepthSupportROICandidateConfidence() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap, "应能创建合成深度图")

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )
        let lowSupportCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.9,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18),
            sourceCategory: .apple,
            depthSupportRatio: 0.2
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [lowSupportCandidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .fused)
        XCTAssertLessThan(result.first?.confidence ?? 1, 0.65, "低 ROI 深度支持率应降低融合置信度")
        XCTAssertGreaterThan(result.first?.confidence ?? 0, 0.45, "低支持 ROI 仍保留为 fused，但质量更低")
    }

    func testProjectDetectionUsesForegroundDepthClusterInsideBox() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 100, height: 100, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 100, height: 100)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            confidence: 0.9
        )

        for row in 3...5 {
            for col in 3...5 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 1.4
                )
            }
        }

        let projected = validator.projectDetectionTo3D(
            detection: detection,
            depthMap: depthMap,
            cameraIntrinsics: pinholeIntrinsics(fx: 50, fy: 50, cx: 50, cy: 50),
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(projected.z, 1.4, accuracy: 0.001, "检测框内近景果面簇应优先于背景深度")
    }

    func testProjectDetectionTreatsDepthAsCameraZForOffCenterDetection() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 100, height: 100, fillValue: 2.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 100, height: 100)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.70, y: 0.45, width: 0.10, height: 0.10),
            confidence: 0.9
        )

        let projected = validator.projectDetectionTo3D(
            detection: detection,
            depthMap: depthMap,
            cameraIntrinsics: pinholeIntrinsics(fx: 50, fy: 50, cx: 50, cy: 50),
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(projected.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(projected.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(projected.z, 2.0, accuracy: 0.001, "深度图读数应作为相机 z 深度，而不是射线长度")
    }

    func testDetectionDepthCandidateUsesDominant3DClusterInsideROI() throws {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 900, height: 900)
        let intrinsics = pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        for row in 3...5 {
            for col in 3...5 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
            for col in 7...8 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let candidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            )
        )

        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.pointCount, 9, "应只保留中心主簇，而不是把侧边深度团一起平均")
        XCTAssertLessThan(abs(candidate.position.x), 0.03, "候选中心应靠近检测框主簇中心")
        XCTAssertEqual(candidate.depthSupportRatio ?? 0, 9.0 / 81.0, accuracy: 0.001)
    }

    func testDetectionDepthCandidatePrefersCenteredFruitClusterOverLargerEdgeCluster() throws {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 900, height: 900)
        let intrinsics = pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        for row in 3...5 {
            for col in 3...5 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }
        for row in 0...1 {
            for col in 0...4 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let candidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            )
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.pointCount, 9, "边缘深度团点数更多时，也不应抢走检测框中心的果实主簇")
        XCTAssertLessThan(abs(candidate.position.x), 0.03)
        XCTAssertLessThan(abs(candidate.position.y), 0.03)
    }

    func testDetectionDepthCandidateRejectsElongatedDepthStripe() {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 900, height: 900)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450),
            imageSize: imageSize,
            depthMap: depthMap
        )

        for col in 1...7 {
            setDepthAtDetectionGrid(
                depthMap,
                detection: detection,
                row: 4,
                col: col,
                imageSize: imageSize,
                value: 2.0
            )
        }

        let candidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            )
        )

        XCTAssertTrue(candidates.isEmpty, "细长深度条更像枝叶或边缘，不应生成 ROI 果实候选")
    }

    func testDetectionDepthCandidateDiameterUsesPriorWhenBoundingBoxIsOccludedSmall() throws {
        let depthMap = makeDepthMap(width: 180, height: 180, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 1800, height: 1800)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.491, y: 0.491, width: 0.018, height: 0.018),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 2000, fy: 2000, cx: 900, cy: 900),
            imageSize: imageSize,
            depthMap: depthMap
        )

        for row in 3...5 {
            for col in 3...5 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let candidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            )
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertGreaterThan(candidate.diameter, 0.055, "遮挡小框不应把苹果直径压到明显低于品类先验")
        XCTAssertLessThan(candidate.diameter, 0.085)
    }

    func testDetectionDepthCandidateDiameterCapsOversizedBoundingBox() throws {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        guard let depthMap else {
            XCTFail("应能创建合成深度图")
            return
        }
        let imageSize = CGSize(width: 900, height: 900)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450),
            imageSize: imageSize,
            depthMap: depthMap
        )

        for row in 3...5 {
            for col in 3...5 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detection,
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let candidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            )
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertLessThanOrEqual(candidate.diameter, 0.12, "异常大框应被品类先验和 ROI 主簇证据约束")
        XCTAssertGreaterThan(candidate.diameter, 0.075)
    }

    func testValidateFusesCandidateInsideDetectionFrustumBeyondCenterTolerance() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let frustumCandidate = FruitCandidate(
            position: SIMD3<Float>(0.22, 0, 2),
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [frustumCandidate]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .fused, "候选中心略偏但仍在检测框视锥内时应融合")
        XCTAssertEqual(result.first?.position, frustumCandidate.position)
    }

    func testValidateUsesOnlyDepthAlignedDetectionFrames() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let candidate = appleCandidate(at: SIMD3<Float>(0, 0, 2))

        let aligned = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let missingDepth = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.8,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let result = validator.validate(
            detections: [aligned, missingDepth],
            candidates: [candidate]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .fused)
    }

    // MARK: - B.3 candidate beyond distance threshold → imageOnly

    func testValidateImageOnlyWhenCandidateTooFar() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let farCandidate = appleCandidate(at: SIMD3<Float>(5, 0, 0))

        let result = validator.validate(
            detections: [detection],
            candidates: [farCandidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly, "候选超出 0.15m 距离阈值应不融合")
    }

    // MARK: - B.4 candidate fails isValidFruit → no fusion

    func testValidateImageOnlyWhenCandidateFailsIsValidFruit() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let lowSphericityCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.3,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [lowSphericityCandidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly, "sphericity 不足应阻挡融合")
    }

    func testValidateImageOnlyWhenCandidateInsufficientPoints() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let fewPointsCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 2,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [fewPointsCandidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly, "点数不足应阻挡融合")
    }

    func testValidateAllowsSparseDetectionDepthCandidateForOccludedFruit() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )

        let sparseROIDepthCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 3,
            averageColor: SIMD3<Float>(0.75, 0.18, 0.12),
            sourceCategory: .apple,
            depthSupportRatio: 3.0 / 81.0
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [sparseROIDepthCandidate]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .fused, "紧凑 ROI 深度候选即使只有 3 个点，也应允许遮挡果面参与融合")
    }

    func testValidateRejectsROICandidateFromDifferentSourceCategory() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )
        let orangeROICandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.95, 0.48, 0.10),
            sourceCategory: .orange
        )

        let result = validator.validate(
            detections: [detection],
            candidates: [orangeROICandidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, ValidationSource.imageOnly)
    }

    // MARK: - B.5 multi-detection/candidate matching

    func testValidateMatchesDetectionsToNearestCandidate() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let det1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let det2 = DetectedFruit(
            category: .orange,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.8,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let candidateA = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.85,
            pointCount: 20,
            averageColor: SIMD3<Float>(0.6, 0.25, 0.18)
        )

        let candidateB = FruitCandidate(
            position: SIMD3<Float>(0.04, 0, 2),
            diameter: 0.09,
            sphericity: 0.8,
            pointCount: 15,
            averageColor: SIMD3<Float>(0.9, 0.4, 0.1)
        )

        let result = validator.validate(
            detections: [det1, det2],
            candidates: [candidateA, candidateB],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 2, "每个检测应产生一个验证结果")
        let fusedCount = result.filter { $0.source == ValidationSource.fused }.count
        XCTAssertEqual(fusedCount, 2, "两个检测都应匹配到候选")
        XCTAssertEqual(result[0].category, FruitCategory.apple)
        XCTAssertEqual(result[1].category, FruitCategory.orange)
    }

    func testValidateMixedResultsSomeFusedSomeImageOnly() {
        let validator = FusionValidator(config: .default)
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)

        let det1 = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let det2 = DetectedFruit(
            category: .pear,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.8,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize
        )

        let candidate = appleCandidate(at: SIMD3<Float>(0, 0, 2))

        let result = validator.validate(
            detections: [det1, det2],
            candidates: [candidate],
            depthMap: depthMap,
            cameraIntrinsics: intrinsics,
            cameraTransform: identityTransform,
            imageSize: imageSize
        )

        XCTAssertEqual(result.count, 2)
        let fusedCount = result.filter { $0.source == ValidationSource.fused }.count
        let imageOnlyCount = result.filter { $0.source == ValidationSource.imageOnly }.count
        XCTAssertEqual(fusedCount, 1, "apple 检测应融合")
        XCTAssertEqual(imageOnlyCount, 1, "pear 检测无对应候选应为 imageOnly")
    }

    // MARK: - B.6 depthSamplePoint

    func testDepthSamplePointNormal() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0.5, y: 0.25),
            imageSize: CGSize(width: 1920, height: 1080),
            depthSize: CGSize(width: 256, height: 192)
        )
        XCTAssertEqual(point.x, 128, accuracy: 0.01)
        let expectedY = (1 - 0.25) * 1080 * 192 / 1080
        XCTAssertEqual(point.y, expectedY, accuracy: 0.01)
    }

    func testDepthSamplePointZeroWidthReturnsZero() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5),
            imageSize: .zero,
            depthSize: CGSize(width: 256, height: 192)
        )
        XCTAssertEqual(point, .zero, "零宽度输入应返回 .zero")
    }

    func testDepthSamplePointZeroHeightReturnsZero() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5),
            imageSize: CGSize(width: 1920, height: 0),
            depthSize: CGSize(width: 256, height: 192)
        )
        XCTAssertEqual(point, .zero, "零高度输入应返回 .zero")
    }

    func testDepthSamplePointZeroDepthSizeReturnsZero() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5),
            imageSize: CGSize(width: 1920, height: 1080),
            depthSize: .zero
        )
        XCTAssertEqual(point, .zero, "零深度尺寸应返回 .zero")
    }

    func testDepthSamplePointOriginYFlip() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 0, y: 0),
            imageSize: CGSize(width: 100, height: 100),
            depthSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(point.x, 0, accuracy: 0.01)
        XCTAssertEqual(point.y, 100, accuracy: 0.01, "y=0 应翻转到底部")
    }

    func testDepthSamplePointTopRight() {
        let point = FusionValidator.depthSamplePoint(
            normalizedPoint: CGPoint(x: 1, y: 1),
            imageSize: CGSize(width: 200, height: 100),
            depthSize: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(point.x, 100, accuracy: 0.01)
        XCTAssertEqual(point.y, 0, accuracy: 0.01, "y=1 应翻转到顶部")
    }
}
