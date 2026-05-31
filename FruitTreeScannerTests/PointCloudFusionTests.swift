import XCTest
@testable import FruitTreeScanner

final class PointCloudFusionTests: XCTestCase {

    func testVoxelDownsampleEmpty() {
        let fusion = PointCloudFusion()
        let result = fusion.voxelDownsample(points: [], voxelSize: 0.01)
        XCTAssertTrue(result.isEmpty, "空输入应返回空")
    }

    func testVoxelDownsampleReducesCount() {
        let fusion = PointCloudFusion()
        var points: [FusedPoint] = []
        for i in 0..<100 {
            let x = Float(i % 10) * 0.001
            let y = Float(i / 10) * 0.001
            points.append(FusedPoint(pos: SIMD3<Float>(x, y, 1.0), r: 0.5, g: 0.3, b: 0.1))
        }
        let result = fusion.voxelDownsample(points: points, voxelSize: 0.01)
        XCTAssertLessThanOrEqual(result.count, points.count, "降采样后点数应 <= 原始点数")
    }

    func testSelectHighQualityFramesEmpty() {
        let fusion = PointCloudFusion()
        let result = fusion.selectHighQualityFrames()
        XCTAssertTrue(result.isEmpty, "无帧时应返回空")
    }

    func testFuseEmpty() {
        let fusion = PointCloudFusion()
        let result = fusion.fuse()
        XCTAssertTrue(result.points.isEmpty, "无帧时融合应返回空")
        XCTAssertEqual(result.frameCount, 0)
    }

    func testStatisticalOutlierRemovalFewPoints() {
        let fusion = PointCloudFusion()
        var points: [FusedPoint] = []
        for i in 0..<5 {
            points.append(FusedPoint(pos: SIMD3<Float>(Float(i) * 0.1, 0, 1), r: 0.5, g: 0.5, b: 0.5))
        }
        let result = fusion.voxelDownsample(points: points, voxelSize: 0.001)
        XCTAssertEqual(result.count, 5, "点数少于 k 时应保留全部")
    }
}
