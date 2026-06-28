import XCTest
import CoreML
@testable import FruitTreeScanner

final class DetectionDeduplicatorTests: XCTestCase {

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
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
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
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
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
