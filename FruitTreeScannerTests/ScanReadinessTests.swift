import XCTest
@testable import FruitTreeScanner

final class ScanReadinessTests: XCTestCase {
    func testOnlyReadyDoesNotBlockScanning() {
        XCTAssertFalse(ScanReadiness.ready.blocksScanning)
        XCTAssertTrue(ScanReadiness.checking.blocksScanning)
        XCTAssertTrue(ScanReadiness.arUnsupported.blocksScanning)
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

    func testReadyHasNoBlockingText() {
        XCTAssertEqual(ScanReadiness.ready.title, "")
        XCTAssertEqual(ScanReadiness.ready.message, "")
    }
}
