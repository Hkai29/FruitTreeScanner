import XCTest
import simd
@testable import FruitTreeScanner

final class CandidateCombinerTests: XCTestCase {
    func testEmptyAndSingleCandidatePreserveIdentity() throws {
        XCTAssertTrue(CandidateCombiner.mergeDetectionDepthCandidates([]).isEmpty)
        let original = candidate(x: 0, count: 10)
        let output = try XCTUnwrap(CandidateCombiner.mergeDetectionDepthCandidates([original]).first)
        XCTAssertEqual(output.id, original.id)
        XCTAssertEqual(output.points, original.points)
        XCTAssertEqual(output.depthSupportRatio, original.depthSupportRatio)
    }

    func testMergePreservesWeightedGeometryColorAndDepthSupport() throws {
        let first = FruitCandidate(position: .zero, diameter: 0.08, sphericity: 0.8,
            pointCount: 30, averageColor: SIMD3<Float>(0.8, 0.2, 0.1),
            points: [.zero, SIMD3<Float>(0.001, 0, 0)], sourceCategory: .apple, depthSupportRatio: 0.9)
        let second = FruitCandidate(position: SIMD3<Float>(0.02, 0, 0), diameter: 0.10, sphericity: 0.6,
            pointCount: 10, averageColor: SIMD3<Float>(0, 0.4, 0.6),
            points: [SIMD3<Float>(0.02, 0, 0)], sourceCategory: .apple, depthSupportRatio: 0.4)
        for input in [[first, second], [second, first]] {
            let output = CandidateCombiner.mergeDetectionDepthCandidates(input)
            XCTAssertEqual(output.count, 1)
            let merged = try XCTUnwrap(output.first)
            // Evidence weights are 30*.8=24 and 10*.6=6.
            XCTAssertEqual(merged.position.x, 0.004, accuracy: 0.000001)
            XCTAssertEqual(merged.diameter, 0.084, accuracy: 0.000001)
            XCTAssertEqual(merged.averageColor.x, 0.64, accuracy: 0.000001)
            XCTAssertEqual(merged.averageColor.y, 0.24, accuracy: 0.000001)
            XCTAssertEqual(merged.averageColor.z, 0.20, accuracy: 0.000001)
            XCTAssertEqual(try XCTUnwrap(merged.depthSupportRatio), 0.8, accuracy: 0.000001)
            XCTAssertEqual(merged.sphericity, 0.8)
            XCTAssertEqual(merged.pointCount, 40)
            XCTAssertEqual(merged.points, first.points + second.points)
            XCTAssertEqual(merged.sourceCategory, .apple)
            XCTAssertFalse(merged.hasPointCloudEvidence)
        }
    }

    func testCandidateChoosesNearestEligibleTrack() throws {
        let left = candidate(x: -0.04, count: 100, sphericity: 1)
        let right = candidate(x: 0.04, count: 90)
        let bridge = candidate(x: 0.01, count: 10)
        let output = CandidateCombiner.mergeDetectionDepthCandidates([bridge, right, left])
        XCTAssertEqual(output.count, 2)
        let first = try XCTUnwrap(output.first)
        let last = try XCTUnwrap(output.last)
        XCTAssertEqual(first.position.x, -0.04, accuracy: 0.000001)
        // The bridge is eligible for both tracks, but is closer to the right.
        // Right weight 81 and bridge weight 9 give (.04*81+.01*9)/90=.037.
        XCTAssertEqual(last.position.x, 0.037, accuracy: 0.000001)
        XCTAssertEqual(first.pointCount, 100)
        XCTAssertEqual(last.pointCount, 100)
        XCTAssertEqual(last.points, right.points + bridge.points)
    }

    func testEqualDistancePreservesFirstTrackOrder() throws {
        let left = candidate(x: -0.04, count: 100, sphericity: 1)
        let right = candidate(x: 0.04, count: 90)
        let bridge = candidate(x: 0, count: 10)
        let output = CandidateCombiner.mergeDetectionDepthCandidates([right, bridge, left])
        XCTAssertEqual(output.count, 2)
        let first = try XCTUnwrap(output.first)
        let last = try XCTUnwrap(output.last)
        XCTAssertEqual(first.position.x, -0.0366972477, accuracy: 0.000001)
        XCTAssertEqual(first.pointCount, 110)
        XCTAssertEqual(first.points, left.points + bridge.points)
        XCTAssertEqual(last.position.x, 0.04, accuracy: 0.000001)
        XCTAssertEqual(last.pointCount, 90)
    }

    func testCloudTrackAdoptsOneCategoryAndDoesNotAbsorbOtherFruit() throws {
        let cloud = candidate(x: 0, count: 50, category: nil, depthSupport: nil)
        let pear = candidate(x: 0.01, count: 40, category: .pear)
        let apple = candidate(x: 0.01, count: 30)
        let output = CandidateCombiner.combine(pointCloudCandidates: [cloud], detectionDepthCandidates: [apple, pear])
        XCTAssertEqual(output.count, 2)
        let mixed = try XCTUnwrap(output.first)
        let separate = try XCTUnwrap(output.last)
        XCTAssertEqual(mixed.sourceCategory, .pear)
        XCTAssertEqual(mixed.pointCount, 90)
        XCTAssertTrue(mixed.hasPointCloudEvidence)
        XCTAssertNil(mixed.depthSupportRatio)
        XCTAssertEqual(separate.sourceCategory, .apple)
        XCTAssertEqual(separate.pointCount, 30)
        XCTAssertFalse(separate.hasPointCloudEvidence)
        XCTAssertEqual(separate.depthSupportRatio, 1)
    }

    func testSampleLimitPreservesTotalEvidenceAndPrefixOrder() throws {
        let firstPoints = (0..<200).map { SIMD3<Float>(Float($0) * 0.00001, 0, 0) }
        let secondPoints = (0..<200).map { SIMD3<Float>(0.01, Float($0) * 0.00001, 0) }
        let first = FruitCandidate(position: .zero, diameter: 0.08, sphericity: 1,
            pointCount: 200, averageColor: .zero, points: firstPoints, sourceCategory: .apple, depthSupportRatio: 1)
        let second = FruitCandidate(position: SIMD3<Float>(0.01, 0, 0), diameter: 0.08, sphericity: 1,
            pointCount: 150, averageColor: .zero, points: secondPoints, sourceCategory: .apple, depthSupportRatio: 1)
        for requestedLimit in [1000, -1] {
            var config = CandidateMergeExperimentConfig.default
            config.maxPointSamples = requestedLimit
            let output = CandidateCombiner.mergeDetectionDepthCandidates([second, first], configuration: config)
            XCTAssertEqual(output.count, 1)
            let merged = try XCTUnwrap(output.first)
            XCTAssertEqual(merged.pointCount, 350)
            // Weight uses max(reported count, actual membership): both weigh 200.
            XCTAssertEqual(merged.position.x, 0.005, accuracy: 0.000001)
            XCTAssertEqual(merged.depthSupportRatio, 1)
            let expected = requestedLimit > 0 ? firstPoints + Array(secondPoints.prefix(56)) : []
            XCTAssertEqual(merged.points, expected)
        }
    }

    private func candidate(x: Float, count: Int, sphericity: Float = 0.9,
                           category: FruitCategory? = .apple, depthSupport: Float? = 1) -> FruitCandidate {
        FruitCandidate(position: SIMD3<Float>(x, 0, 0), diameter: 0.08, sphericity: sphericity,
            pointCount: count, averageColor: SIMD3<Float>(0.7, 0.2, 0.1),
            points: [SIMD3<Float>(x, 0, 0)], sourceCategory: category, depthSupportRatio: depthSupport)
    }
}
