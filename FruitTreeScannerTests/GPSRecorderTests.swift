import CoreLocation
import XCTest
@testable import FruitTreeScanner

final class GPSRecorderTests: XCTestCase {
    private let coordinate = CLLocationCoordinate2D(latitude: 35.1234, longitude: 139.5678)

    func testLocationPolicyRejectsCachedLocation() {
        let now = Date()
        let cached = makeLocation(
            accuracy: 3,
            timestamp: now.addingTimeInterval(-(GPSLocationPolicy.maximumLocationAge + 1))
        )

        XCTAssertFalse(GPSLocationPolicy.isAcceptable(cached, at: now))
        XCTAssertNil(GPSLocationPolicy.bestLocation(from: [cached], at: now))
    }

    func testLocationPolicyRejectsInvalidAndLowAccuracyLocations() {
        let now = Date()
        let invalidAccuracy = makeLocation(accuracy: -1, timestamp: now)
        let lowAccuracy = makeLocation(
            accuracy: GPSLocationPolicy.maximumHorizontalAccuracy + 0.1,
            timestamp: now
        )
        let invalidCoordinate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 100, longitude: 139),
            altitude: 0,
            horizontalAccuracy: 3,
            verticalAccuracy: 3,
            timestamp: now
        )

        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidAccuracy, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(lowAccuracy, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidCoordinate, at: now))
    }

    func testLocationPolicySelectsMostAccurateFreshLocation() throws {
        let now = Date()
        let newest = makeLocation(accuracy: 6, timestamp: now)
        let moreAccurate = makeLocation(accuracy: 3, timestamp: now.addingTimeInterval(-2))

        let selected = try XCTUnwrap(
            GPSLocationPolicy.bestLocation(from: [newest, moreAccurate], at: now)
        )

        XCTAssertEqual(selected.horizontalAccuracy, 3)
        XCTAssertEqual(selected.timestamp, moreAccurate.timestamp)
    }

    func testLocationPolicyUsesNewestLocationWhenAccuracyMatches() throws {
        let now = Date()
        let older = makeLocation(accuracy: 4, timestamp: now.addingTimeInterval(-2))
        let newer = makeLocation(accuracy: 4, timestamp: now)

        let selected = try XCTUnwrap(
            GPSLocationPolicy.bestLocation(from: [older, newer], at: now)
        )

        XCTAssertEqual(selected.timestamp, newer.timestamp)
    }

    func testGPSStatusExplainsPrecisionAndAuthorizationFailures() {
        XCTAssertEqual(GPSRecorderStatus.ready(4.2).message, "已获取（±5 m）")
        XCTAssertEqual(GPSRecorderStatus.accuracyInsufficient(12.1).message, "定位精度不足（±13 m）")
        XCTAssertEqual(GPSRecorderStatus.preciseLocationRequired.message, "请在系统设置中开启精确位置")
        XCTAssertFalse(GPSRecorderStatus.preciseLocationRequired.isAvailable)
        XCTAssertTrue(GPSRecorderStatus.ready(5).isAvailable)
    }

    private func makeLocation(accuracy: CLLocationAccuracy, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 3,
            timestamp: timestamp
        )
    }
}
