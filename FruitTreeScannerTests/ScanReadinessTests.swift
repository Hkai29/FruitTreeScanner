import XCTest
@testable import FruitTreeScanner

final class ScanReadinessTests: XCTestCase {
    func testOnlyReadyDoesNotBlockScanning() {
        XCTAssertFalse(ScanReadiness.ready.blocksScanning)
        XCTAssertTrue(ScanReadiness.checking.blocksScanning)
        XCTAssertTrue(ScanReadiness.arUnsupported.blocksScanning)
        XCTAssertTrue(ScanReadiness.metalUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.lidarUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraDenied.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraRestricted.blocksScanning)
    }

    func testCameraDeniedTextStaysStable() {
        XCTAssertEqual(ScanReadiness.cameraDenied.title, "相机权限未开启")
        XCTAssertEqual(
            ScanReadiness.cameraDenied.message,
            "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。"
        )
    }

    func testMetalUnavailableTextStaysStable() {
        XCTAssertEqual(ScanReadiness.metalUnavailable.title, "图形渲染不可用")
        XCTAssertEqual(
            ScanReadiness.metalUnavailable.message,
            "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。"
        )
    }

    func testLidarUnavailableTextStaysStable() {
        XCTAssertEqual(ScanReadiness.lidarUnavailable.title, "当前设备没有 LiDAR 深度")
        XCTAssertEqual(
            ScanReadiness.lidarUnavailable.message,
            "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。"
        )
    }

    func testReadyHasNoBlockingText() {
        XCTAssertEqual(ScanReadiness.ready.title, "")
        XCTAssertEqual(ScanReadiness.ready.message, "")
    }
}
