import XCTest
import CoreML
import CoreVideo
@testable import FruitTreeScanner

final class DetectionDeduplicatorTests: XCTestCase {

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
