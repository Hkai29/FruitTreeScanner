import XCTest
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
        XCTAssertEqual(point.y, 48, accuracy: 0.01)
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
}
