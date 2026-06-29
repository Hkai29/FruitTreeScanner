import XCTest
import Metal
import SceneKit
import simd
@testable import FruitTreeScanner

final class PointCloudProcessingTests: XCTestCase {

    func testTreeIdentifierPolicyRejectsPathAndHeaderInjectionCharacters() {
        XCTAssertTrue(TreeIdentifierPolicy.isValid("T001"))
        XCTAssertTrue(TreeIdentifierPolicy.isValid("三号地块 12-A"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid(""))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("../escape"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A/B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A\\B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A:B"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid("A\ncomment gps_lat 90"))
        XCTAssertFalse(TreeIdentifierPolicy.isValid(String(repeating: "A", count: 65)))
    }

    func testTreeIdentifierPolicyMakesBoundedSafeFileComponent() {
        let component = TreeIdentifierPolicy.safeFileComponent(
            from: " ../果园 A/B:\n" + String(repeating: "树", count: 80)
        )

        XCTAssertFalse(component.isEmpty)
        XCTAssertFalse(component.contains("/"))
        XCTAssertFalse(component.contains("\\"))
        XCTAssertFalse(component.contains(":"))
        XCTAssertFalse(component.contains("\n"))
        XCTAssertLessThanOrEqual(component.utf8.count, 80)
    }

    func testTreeFilenameIsSafeAndUniqueForSameTimestamp() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let first = makeTreeFileName(
            treeID: "../Tree/A",
            lat: 35.1,
            lon: 139.2,
            date: date,
            uniqueSuffix: "ABCDEF123456"
        )
        let second = makeTreeFileName(
            treeID: "../Tree/A",
            lat: 35.1,
            lon: 139.2,
            date: date,
            uniqueSuffix: "654321FEDCBA"
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(first))
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(second))
        XCTAssertFalse(LocalFileStorage.isSafeLeafFilename("../escape.ply"))
        XCTAssertFalse(LocalFileStorage.isSafeLeafFilename("nested/scan.ply"))
        XCTAssertTrue(first.hasSuffix("_lat35.1000_lon139.2000.ply"))
    }

    // MARK: - PointCloudDenoiser.statisticalOutlierRemoval

    func testSOR_ReturnsOriginalForSmallInput() {
        let empty: [RendererPointSample] = []
        XCTAssertEqual(PointCloudDenoiser.statisticalOutlierRemoval(samples: empty).count, 0)

        let one = [RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1)]
        let resultOne = PointCloudDenoiser.statisticalOutlierRemoval(samples: one)
        XCTAssertEqual(resultOne.count, 1)
        XCTAssertEqual(resultOne.first?.position, SIMD3<Float>(1, 2, 3))

        let kPlusOne: [RendererPointSample] = (0..<13).map { i in
            RendererPointSample(position: SIMD3<Float>(Float(i), 0, 0), color: SIMD3<Float>(1, 0, 0), confidence: 1)
        }
        let resultKPlusOne = PointCloudDenoiser.statisticalOutlierRemoval(samples: kPlusOne)
        XCTAssertEqual(resultKPlusOne.count, 13)
    }

    func testSOR_RemovesFarOutlierPreservesInliers() {
        var samples: [RendererPointSample] = []
        let clusterCount = 20
        for i in 0..<clusterCount {
            let offset = Float(i % 5 - 2) * 0.03
            let pos = SIMD3<Float>(offset, Float((i / 5) % 4 - 1) * 0.03, 0)
            samples.append(RendererPointSample(
                position: pos,
                color: SIMD3<Float>(Float(i) / Float(clusterCount), 0.5, 0.2),
                confidence: 0.8 + Float(i % 3) * 0.05
            ))
        }
        let outlier = RendererPointSample(
            position: SIMD3<Float>(12, 0, 0),
            color: SIMD3<Float>(0, 1, 0),
            confidence: 0.9
        )
        samples.append(outlier)

        let result = PointCloudDenoiser.statisticalOutlierRemoval(samples: samples, k: 5, stdMultiplier: 1.5)

        XCTAssertEqual(result.count, clusterCount, "Outlier should be removed, inliers preserved")

        let hasOutlier = result.contains { $0.position.x > 10 }
        XCTAssertFalse(hasOutlier, "Far outlier must be removed")

        for i in 0..<clusterCount {
            let expected = samples[i]
            let kept = result.first { $0.position == expected.position }
            XCTAssertNotNil(kept, "Inlier \(i) missing")
            XCTAssertEqual(kept?.color, expected.color, "Inlier \(i) color changed")
            XCTAssertEqual(kept?.confidence, expected.confidence, "Inlier \(i) confidence changed")
        }
    }

    // MARK: - RendererPointCloudSnapshot filtering

    func testIsExportableParticle_RejectsLowConfidence() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 5)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Confidence 5 below threshold 10 should be rejected")
    }

    func testIsExportableParticle_RejectsZeroPosition() {
        let p = ParticleUniforms(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Zero position should be rejected")
    }

    func testIsExportableParticle_RejectsNonFinitePosition() {
        let p = ParticleUniforms(position: SIMD3<Float>(.nan, 1, 1), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "NaN position should be rejected")
    }

    func testIsExportableParticle_RejectsNonFiniteColor() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(.infinity, 0.5, 0.5), confidence: 100)
        XCTAssertFalse(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                       "Infinite color component should be rejected")
    }

    func testIsExportableParticle_AcceptsValidParticle() {
        let p = ParticleUniforms(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 100)
        XCTAssertTrue(RendererPointCloudSnapshot.isExportableParticle(p, confidenceThreshold: 10),
                      "Valid particle should be accepted")
    }

    // MARK: - Voxel-based deduplication

    func testVoxelDedupe_KeepsHigherConfidenceInSameVoxel() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            try XCTSkipIf(true, "Metal device not available")
            return
        }

        let pos = SIMD3<Float>(1.5, 2.5, 3.5)
        let particles: [ParticleUniforms] = [
            ParticleUniforms(position: pos, color: SIMD3<Float>(1, 0, 0), confidence: 30),
            ParticleUniforms(position: pos, color: SIMD3<Float>(0, 1, 0), confidence: 90),
        ]
        let buffer = MetalBuffer<ParticleUniforms>(device: device, array: particles, index: 0)

        let result = RendererPointCloudSnapshot.makeFilteredSamples(
            particlesBuffer: buffer,
            currentPointCount: 2,
            currentPointIndex: 2,
            maxPoints: 2,
            voxelSize: 1.0,
            confidenceThreshold: 10
        )

        XCTAssertEqual(result.count, 1, "Two particles in same voxel should deduplicate to one")
        XCTAssertEqual(result[0].confidence, 90, "Higher-confidence particle should be kept")
        XCTAssertEqual(result[0].color, SIMD3<Float>(0, 1, 0), "Higher-confidence particle's color should be kept")
    }

    // MARK: - Color clamping

    func testClampColor_ClampsOutOfRangeRGB() {
        let below = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(-0.5, -1.0, -0.1))
        XCTAssertEqual(below, SIMD3<Float>(0, 0, 0), "Negative values should clamp to 0")

        let above = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(1.2, 2.0, 1.5))
        XCTAssertEqual(above, SIMD3<Float>(1, 1, 1), "Values above 1 should clamp to 1")

        let mixed = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(-0.2, 0.5, 1.8))
        XCTAssertEqual(mixed, SIMD3<Float>(0, 0.5, 1), "Mixed values should clamp per-channel")
    }

    func testClampColor_PreservesValidRGB() {
        let valid = RendererPointCloudSnapshot.clampColorPublic(SIMD3<Float>(0.0, 0.5, 1.0))
        XCTAssertEqual(valid, SIMD3<Float>(0, 0.5, 1), "In-range values should pass through unchanged")
    }

    func testMakeExportableSample_RejectsNonFiniteColorBeforeGPUAssistedExport() {
        let particle = ParticleUniforms(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(.nan, 0.5, 0.5),
            confidence: 100
        )

        let sample = RendererPointCloudSnapshot.makeExportableSample(
            from: particle,
            confidenceThreshold: 10
        )

        XCTAssertNil(sample, "GPU-assisted filtering must keep the same finite-color gate as CPU filtering")
    }

    func testMakeExportableSample_ClampsValidOutOfRangeColor() throws {
        let particle = ParticleUniforms(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(-0.1, 0.5, 1.2),
            confidence: 100
        )

        let sample = try XCTUnwrap(RendererPointCloudSnapshot.makeExportableSample(
            from: particle,
            confidenceThreshold: 10
        ))

        XCTAssertEqual(sample.color, SIMD3<Float>(0, 0.5, 1))
    }

    // MARK: - makeColoredPoints

    func testMakeColoredPoints_ConvertsCorrectly() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 0.9),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.4, 0.5, 0.6), confidence: 0.7),
        ]
        let points = RendererPointCloudSnapshot.makeColoredPoints(from: samples)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].pos, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(points[0].r, 0.1)
        XCTAssertEqual(points[0].g, 0.2)
        XCTAssertEqual(points[0].b, 0.3)
        XCTAssertEqual(points[1].pos, SIMD3<Float>(4, 5, 6))
    }

    // MARK: - makeSignature

    func testMakeSignature_ProducesDeterministicSignature() {
        let sig = RendererPointCloudSnapshot.makeSignature(
            pointCount: 1000, pointIndex: 42, voxelSize: 0.05, confidenceThreshold: 30
        )
        XCTAssertEqual(sig.pointCount, 1000)
        XCTAssertEqual(sig.pointIndex, 42)
        XCTAssertEqual(sig.voxelSize, 0.05)
        XCTAssertEqual(sig.confidenceThreshold, 30)
    }

    // MARK: - RendererScanProgress

    func testScanProgress_ResetClearsState() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)
        XCTAssertEqual(progress.voxelDiscoveryRate, 0)
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)
    }

    func testScanProgress_PauseResumeExcludesPausedDuration() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.pause(now: start.addingTimeInterval(5))
        XCTAssertEqual(progress.scanDuration, 5, accuracy: 0.001)

        progress.resume(now: start.addingTimeInterval(15))
        progress.pause(now: start.addingTimeInterval(18))

        XCTAssertEqual(progress.scanDuration, 8, accuracy: 0.001)
    }

    func testScanProgress_RecordVoxelCountRespectsInterval() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(10, now: start.addingTimeInterval(0.5))
        XCTAssertEqual(progress.voxelDiscoveryRate, 0, "0.5s interval should be ignored")

        progress.recordVoxelCount(10, now: start.addingTimeInterval(1.0))
        XCTAssertEqual(progress.voxelDiscoveryRate, 10, "1s interval should record delta (10 - 0 = 10)")
    }

    func testScanProgress_ComputesAverageDiscoveryRate() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(5, now: start.addingTimeInterval(1))   // delta 5
        progress.recordVoxelCount(10, now: start.addingTimeInterval(2))  // delta 5
        progress.recordVoxelCount(20, now: start.addingTimeInterval(3))  // delta 10
        progress.recordVoxelCount(28, now: start.addingTimeInterval(4))  // delta 8

        let expectedRate = Float(5 + 5 + 10 + 8) / 4.0
        XCTAssertEqual(progress.voxelDiscoveryRate, expectedRate)
    }

    func testScanProgress_CapsHistoryAtTen() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        for i in 1...15 {
            progress.recordVoxelCount(i * 10, now: start.addingTimeInterval(TimeInterval(i)))
        }

        let rate = progress.voxelDiscoveryRate
        let lastTenDeltas = Array(repeating: Float(10), count: 10)
        let expectedRate = lastTenDeltas.reduce(0, +) / Float(lastTenDeltas.count)
        XCTAssertEqual(rate, expectedRate, "History capped at 10, last 10 deltas should all be 10")
    }

    func testScanProgress_TrendStable() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(2, now: start.addingTimeInterval(1))
        progress.recordVoxelCount(3, now: start.addingTimeInterval(2))
        progress.recordVoxelCount(4, now: start.addingTimeInterval(3))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .stable, "Recent avg < 5 should be stable")
    }

    func testScanProgress_TrendDecreasing() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        for i in 1...7 {
            progress.recordVoxelCount(i * 30, now: start.addingTimeInterval(TimeInterval(i)))
        }
        progress.recordVoxelCount(8 * 30 + 15, now: start.addingTimeInterval(8))
        progress.recordVoxelCount(8 * 30 + 25, now: start.addingTimeInterval(9))
        progress.recordVoxelCount(8 * 30 + 30, now: start.addingTimeInterval(10))

        XCTAssertEqual(progress.voxelDiscoveryTrend, .decreasing, "Dropping recent deltas should be decreasing")
    }

    func testScanProgress_TrendIncreasing() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(20, now: start.addingTimeInterval(1))
        progress.recordVoxelCount(40, now: start.addingTimeInterval(2))
        progress.recordVoxelCount(65, now: start.addingTimeInterval(3))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .increasing)
    }

    func testScanProgress_TrendCollectingBeforeThreeRecords() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = RendererScanProgress()
        progress.reset(now: start)

        progress.recordVoxelCount(10, now: start.addingTimeInterval(1))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)

        progress.recordVoxelCount(20, now: start.addingTimeInterval(2))
        XCTAssertEqual(progress.voxelDiscoveryTrend, .collecting)

        progress.recordVoxelCount(30, now: start.addingTimeInterval(3))
        XCTAssertNotEqual(progress.voxelDiscoveryTrend, .collecting, "Third record should exit collecting")
    }

    // MARK: - RendererPLYDataBuilder.makeData

    func testMakeData_ProducesASCIIPLY() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.1, 0.2, 0.3), confidence: 0.9),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.4, 0.5, 0.6), confidence: 0.7),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-06-05 12:00:00",
            gpsLat: 35.123456, gpsLon: 139.654321
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0], "ply")
        XCTAssertEqual(lines[1], "format ascii 1.0")
        XCTAssertTrue(lines.contains("comment tree_id T001"))
        XCTAssertTrue(lines.contains("comment scan_date 2025-06-05 12:00:00"))
        XCTAssertTrue(lines.contains("comment gps_lat 35.123456"))
        XCTAssertTrue(lines.contains("comment gps_lon 139.654321"))
        XCTAssertTrue(lines.contains("element vertex 2"))
        XCTAssertTrue(lines.contains("property float x"))
        XCTAssertTrue(lines.contains("property float y"))
        XCTAssertTrue(lines.contains("property float z"))
        XCTAssertTrue(lines.contains("property uchar red"))
        XCTAssertTrue(lines.contains("property uchar green"))
        XCTAssertTrue(lines.contains("property uchar blue"))
        XCTAssertTrue(lines.contains("element face 0"))
        XCTAssertTrue(lines.contains("property list uchar int vertex_indices"))
        XCTAssertTrue(lines.contains("end_header"))
    }

    func testMakeDataSanitizesTreeIDBeforeWritingPLYHeader() {
        let sample = RendererPointSample(
            position: SIMD3<Float>(1, 2, 3),
            color: SIMD3<Float>(0.1, 0.2, 0.3),
            confidence: 0.9
        )
        let data = RendererPLYDataBuilder.makeData(
            samples: [sample],
            treeID: "T001\r\nelement vertex 999\ncomment gps_lat 90",
            scanDate: "2026-06-25 10:00:00",
            gpsLat: 35,
            gpsLon: 139
        )
        let contents = String(decoding: data, as: UTF8.self)
        let lines = contents.components(separatedBy: "\r\n")

        XCTAssertTrue(lines.contains("comment tree_id T001 element vertex 999 comment gps_lat 90"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("element vertex") }, ["element vertex 1"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("comment gps_lat") }, ["comment gps_lat 35.000000"])
    }

    func testMakeData_GPSFormatSixDecimals() {
        let gpsLinePattern = try! NSRegularExpression(pattern: "comment gps_(lat|lon) \\-?\\d+\\.\\d{6}")
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "T001", scanDate: "2025-01-01",
            gpsLat: -45.987654321, gpsLon: 123.123456789
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        let gpsLines = lines.filter { $0.hasPrefix("comment gps_") }
        XCTAssertEqual(gpsLines.count, 2)
        for line in gpsLines {
            let range = NSRange(location: 0, length: line.utf16.count)
            XCTAssertNotNil(gpsLinePattern.firstMatch(in: line, options: [], range: range),
                            "GPS line should have exactly 6 decimal places: \(line)")
        }
        XCTAssertTrue(gpsLines.contains("comment gps_lat -45.987654"))
        XCTAssertTrue(gpsLines.contains("comment gps_lon 123.123457"))
    }

    func testMakeData_VertexCountMatchesSamples() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(1, 1, 1), color: SIMD3<Float>(1, 1, 1), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(2, 2, 2), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element vertex 3"))
    }

    func testMakeData_EmptySamplesHasZeroVertexCount() {
        let data = RendererPLYDataBuilder.makeData(
            samples: [], treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element vertex 0"))
    }

    func testMakeData_HasFaceElementZero() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("element face 0"))
        XCTAssertTrue(lines.contains("property list uchar int vertex_indices"))
    }

    func testMakeData_UsesCRLFLineEndings() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        XCTAssertGreaterThan(lines.count, 1, "Should have multiple lines separated by CRLF")
        let rawNSString = data as NSData
        let rawBytes = rawNSString.bytes.bindMemory(to: UInt8.self, capacity: data.count)
        let rawStr = String(decoding: UnsafeBufferPointer(start: rawBytes, count: data.count), as: UTF8.self)
        let lfOnly = rawStr.replacingOccurrences(of: "\r\n", with: "")
        XCTAssertFalse(lfOnly.contains("\r"), "No bare CR without LF should exist")
        XCTAssertTrue(rawStr.contains("\r\n"), "CRLF pairs must exist in raw data")
    }

    func testMakeData_ColorFloatToUCharConversion() {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(0.0, 0.0, 0.0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(1.0, 1.0, 1.0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(7, 8, 9), color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")

        let headerEndIndex = lines.firstIndex(of: "end_header")!
        let dataLines = Array(lines[(headerEndIndex + 1)...]).filter { !$0.isEmpty }

        XCTAssertEqual(dataLines.count, 3)

        XCTAssertTrue(dataLines[0].hasSuffix(" 0 0 0"),
                      "Color (0,0,0) should produce 0 0 0, got: \(dataLines[0])")
        XCTAssertTrue(dataLines[1].hasSuffix(" 255 255 255"),
                      "Color (1,1,1) should produce 255 255 255, got: \(dataLines[1])")

        let color128Line = dataLines[2]
        let parts128 = color128Line.components(separatedBy: " ")
        XCTAssertEqual(parts128.count, 6, "Each vertex line should have 6 fields: x y z r g b")
        let r128 = Int(parts128[3])!
        let g128 = Int(parts128[4])!
        let b128 = Int(parts128[5])!
        XCTAssertTrue(r128 == 127 || r128 == 128, "0.5*255 should be 127 or 128, got \(r128)")
        XCTAssertTrue(g128 == 127 || g128 == 128, "0.5*255 should be 127 or 128, got \(g128)")
        XCTAssertTrue(b128 == 127 || b128 == 128, "0.5*255 should be 127 or 128, got \(b128)")
    }

    func testMakeData_VertexLineFormat() {
        let color = SIMD3<Float>(0.2, 0.4, 0.6)
        let expectedR = Int(color.x * 255.0)
        let expectedG = Int(color.y * 255.0)
        let expectedB = Int(color.z * 255.0)
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1.2345, -2.3456, 3.4567), color: color, confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples, treeID: "X", scanDate: "", gpsLat: 0, gpsLon: 0
        )
        let contents = String(data: data, encoding: .utf8)!
        let lines = contents.components(separatedBy: "\r\n")
        let headerEndIndex = lines.firstIndex(of: "end_header")!
        let dataLine = lines[headerEndIndex + 1]

        let expected = String(format: "1.2345 -2.3456 3.4567 %d %d %d", expectedR, expectedG, expectedB)
        XCTAssertEqual(dataLine, expected)

        let parts = dataLine.components(separatedBy: " ")
        XCTAssertEqual(parts.count, 6)
        let x = Float(parts[0])
        let y = Float(parts[1])
        let z = Float(parts[2])
        XCTAssertNotNil(x)
        XCTAssertNotNil(y)
        XCTAssertNotNil(z)
        XCTAssertEqual(Double(x!), 1.2345, accuracy: 0.001)
        XCTAssertEqual(Double(y!), -2.3456, accuracy: 0.001)
        XCTAssertEqual(Double(z!), 3.4567, accuracy: 0.001)
    }

    func testPLYParserReadsRendererCRLFExport() throws {
        let samples: [RendererPointSample] = [
            RendererPointSample(position: SIMD3<Float>(1, 2, 3), color: SIMD3<Float>(1, 0.5, 0), confidence: 1),
            RendererPointSample(position: SIMD3<Float>(4, 5, 6), color: SIMD3<Float>(0.2, 0.4, 0.6), confidence: 1),
        ]
        let data = RendererPLYDataBuilder.makeData(
            samples: samples,
            treeID: "T001",
            scanDate: "2026-06-07 10:00:00",
            gpsLat: 35.123456,
            gpsLon: 139.654321
        )
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T001_20260607_100000_lat35.123456_lon139.654321.ply")
        try data.write(to: plyURL)

        let pointCloud = try XCTUnwrap(PLYParserHelper.parsePointCloudData(at: plyURL))
        XCTAssertEqual(pointCloud.pointCount, 2)
        XCTAssertEqual(pointCloud.vertices[0].x, 1, accuracy: 0.001)
        XCTAssertEqual(pointCloud.vertices[0].y, 2, accuracy: 0.001)
        XCTAssertEqual(pointCloud.vertices[0].z, 3, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].g, Float(Int(0.5 * 255)) / 255.0, accuracy: 0.001)
        XCTAssertEqual(pointCloud.colors[0].b, 0, accuracy: 0.001)
    }

    func testPointCloudBoundsPreserveRealHeightAndFootprint() throws {
        let pointCloud = PointCloudData(
            id: "bounds",
            vertices: [
                SCNVector3(-1.2, 0.4, -0.5),
                SCNVector3(0.8, 3.1, 1.7),
                SCNVector3(0.2, 1.6, 0.4)
            ],
            colors: []
        )

        let bounds = try XCTUnwrap(pointCloud.bounds)
        XCTAssertEqual(bounds.heightMeters, 2.7, accuracy: 0.001)
        XCTAssertEqual(bounds.widthMeters, 2.0, accuracy: 0.001)
        XCTAssertEqual(bounds.depthMeters, 2.2, accuracy: 0.001)
        XCTAssertEqual(bounds.center.y, 1.75, accuracy: 0.001)
    }

    func testPointCloudBoundsEmptyInputReturnsNil() {
        XCTAssertNil(PointCloudBounds(vertices: []))
    }

    // MARK: - PLYImportService reject/cleanup

    func testPLYImportRejectsCorruptPLYAndLeavesScansDirectoryClean() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
        let plyURL = tempDir.appendingPathComponent("corrupt.ply")
        try "not a valid ply file".write(to: plyURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PLYImportService.importFile(plyURL, scansDirectory: scansDir))

        let contents = try FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Failed import left artifacts: \(contents)")
    }

    func testPLYImportRejectsMissingPLYHeader() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
        let plyURL = tempDir.appendingPathComponent("noheader.ply")
        // Write a file with ply magic but no format/element lines
        try "ply\r\ncomment no format line\r\nend_header\r\n".write(to: plyURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PLYImportService.importFile(plyURL, scansDirectory: scansDir))

        let contents = try FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Invalid header import left artifacts: \(contents)")
    }

    // MARK: - PLYImportService success + duplicate import

    func testPLYImportSanitizesSourceFileNameAndImportTwiceDoesNotOverwrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)

        let plyContent = """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face 0
        property list uchar int vertex_indices
        end_header
        1.0 2.0 3.0 128 128 128
        """

        // Source filename with characters that safeFileComponent will transform
        let plyURL = tempDir.appendingPathComponent("My Tree Scan.ply")
        try plyContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let imported1 = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertTrue(LocalFileStorage.isSafeLeafFilename(imported1),
                      "Imported filename should be safe: \(imported1)")
        XCTAssertFalse(imported1.contains(" "),
                       "Imported filename should have spaces collapsed: \(imported1)")

        // Import the same file a second time — must not overwrite the first
        let imported2 = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertNotEqual(imported1, imported2,
                         "Second import should produce a distinct filename from first")

        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(imported1).path),
                      "First imported file should still exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(imported2).path),
                      "Second imported file should exist")

        let content1 = try String(contentsOf: scansDir.appendingPathComponent(imported1), encoding: .utf8)
        let content2 = try String(contentsOf: scansDir.appendingPathComponent(imported2), encoding: .utf8)
        XCTAssertTrue(content1.contains("1.0 2.0 3.0"))
        XCTAssertTrue(content2.contains("1.0 2.0 3.0"))
    }

    // MARK: - Binary PLY with malicious vertex count

    func testBinaryPLYHugeVertexCountReturnsNilWithoutCrash() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("huge_binary.ply")

        // Build a binary PLY with a header claiming a massively huge vertex count
        // but only a tiny body — the guard should reject it without overflow.
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(Int.max)
        property float x
        property float y
        property float z
        end_header

        """.data(using: .ascii)!
        let body = Data(count: 36) // 3 vertices worth of binary data, far less than claimed
        var data = Data()
        data.append(header)
        data.append(body)
        try data.write(to: plyURL)

        let result = PLYParserHelper.parsePointCloudData(at: plyURL)
        XCTAssertNil(result, "Huge vertex count with tiny body should return nil, not crash")
    }

    func testBinaryPLYZeroVertexCountReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("zero_vertex.ply")
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex 0
        property float x
        property float y
        property float z
        end_header

        """.data(using: .ascii)!
        try header.write(to: plyURL)

        let result = PLYParserHelper.parsePointCloudData(at: plyURL)
        XCTAssertNil(result, "Zero vertex count should return nil")
    }

    // MARK: - ASCII PLY property-driven parsing matrix

    func testASCIIPLYParsesReorderedXYZAndRGBWithExtraProperty() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property float z
        property float x
        property uchar red
        property float y
        property uchar green
        property uchar blue
        property float confidence
        end_header
        3.0 1.0 255 2.0 128 0 0.95
        6.0 4.0 100 5.0 200 50 0.85
        """, name: "reordered_ascii.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1, y: 2, z: 3)
        assertColor(pointCloud.colors[0], r: 1, g: 128.0 / 255.0, b: 0)
        assertVertex(pointCloud.vertices[1], x: 4, y: 5, z: 6)
        assertColor(pointCloud.colors[1], r: 100.0 / 255.0, g: 200.0 / 255.0, b: 50.0 / 255.0)
    }

    func testASCIIDoubleCoordinatesNoColorGetsDefaultGray() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property double x
        property double y
        property double z
        end_header
        1.5 -2.5 3.5
        10.0 20.0 30.0
        """, name: "double_no_color.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1.5, y: -2.5, z: 3.5)
        assertVertex(pointCloud.vertices[1], x: 10, y: 20, z: 30)
        assertColor(pointCloud.colors[0], r: 0.5, g: 0.5, b: 0.5)
        assertColor(pointCloud.colors[1], r: 0.5, g: 0.5, b: 0.5)
    }

    func testASCIIFloatColorsNormalizeUnitAndByteRangesPerPoint() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property float red
        property float green
        property float blue
        end_header
        0 0 0 0.2 0.7 1.0
        1 0 0 51.0 178.5 255.0
        """, name: "float_color_ranges.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertColor(pointCloud.colors[0], r: 0.2, g: 0.7, b: 1)
        assertColor(pointCloud.colors[1], r: 51.0 / 255.0, g: 178.5 / 255.0, b: 1)
    }

    func testUTF8ChineseTreeIDHeaderCommentDoesNotBreakParsing() throws {
        let pointCloud = try XCTUnwrap(parsePLY("""
        ply
        format ascii 1.0
        comment tree_id 三号果园·苹果树A12
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        5.0 6.0 7.0 255 128 64
        """, name: "chinese_tree.ply"))

        XCTAssertEqual(pointCloud.pointCount, 1)
        assertVertex(pointCloud.vertices[0], x: 5, y: 6, z: 7)
    }

    func testUTF8ChineseCommentImportDoesNotThrow() throws {
        let plyURL = try writeTemporaryPLY(name: "fruit_tree_chinese.ply", content: """
        ply
        format ascii 1.0
        comment tree_id 果树·桃
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        1.0 2.0 3.0 100 150 200
        """)

        let scansDir = plyURL.deletingLastPathComponent().appendingPathComponent("scans", isDirectory: true)
        let importedName = try PLYImportService.importFile(plyURL, scansDirectory: scansDir)
        XCTAssertTrue(importedName.hasSuffix(".ply"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scansDir.appendingPathComponent(importedName).path))
    }

    // MARK: - Binary PLY parsing matrix

    func testBinaryLittleEndianParsesMixedScalarTypesAndExtraProperty() throws {
        var body = Data()
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat64(2))
        body.append(Self.leInt32(3))
        body.append(contentsOf: [255, 128, 0] as [UInt8])
        body.append(Self.leFloat32(0.95))
        body.append(Self.leFloat32(10))
        body.append(Self.leFloat64(20))
        body.append(Self.leInt32(30))
        body.append(contentsOf: [0, 64, 192] as [UInt8])
        body.append(Self.leFloat32(0.3))

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property double y",
                "property int z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
                "property float confidence",
            ],
            body: body
        ), name: "mixed_le.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1, y: 2, z: 3)
        assertColor(pointCloud.colors[0], r: 1, g: 128.0 / 255.0, b: 0)
        assertVertex(pointCloud.vertices[1], x: 10, y: 20, z: 30)
        assertColor(pointCloud.colors[1], r: 0, g: 64.0 / 255.0, b: 192.0 / 255.0)
    }

    func testBinaryBigEndianParsesCoordinatesAndColors() throws {
        var body = Data()
        body.append(Self.beFloat32(1.5))
        body.append(Self.beFloat32(2.5))
        body.append(Self.beFloat32(3.5))
        body.append(contentsOf: [200, 100, 50] as [UInt8])
        body.append(Self.beFloat32(-1))
        body.append(Self.beFloat32(0))
        body.append(Self.beFloat32(5))
        body.append(contentsOf: [10, 20, 30] as [UInt8])

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_big_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
            ],
            body: body
        ), name: "be.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertVertex(pointCloud.vertices[0], x: 1.5, y: 2.5, z: 3.5)
        assertColor(pointCloud.colors[0], r: 200.0 / 255.0, g: 100.0 / 255.0, b: 50.0 / 255.0)
        assertVertex(pointCloud.vertices[1], x: -1, y: 0, z: 5)
        assertColor(pointCloud.colors[1], r: 10.0 / 255.0, g: 20.0 / 255.0, b: 30.0 / 255.0)
    }

    func testBinaryLittleEndianUShortColorNormalization() throws {
        var body = Data()
        body.append(Self.leFloat32(0))
        body.append(Self.leFloat32(0))
        body.append(Self.leFloat32(0))
        body.append(Self.leUInt16(0))
        body.append(Self.leUInt16(32_768))
        body.append(Self.leUInt16(65_535))
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(1))
        body.append(Self.leUInt16(65_535))
        body.append(Self.leUInt16(0))
        body.append(Self.leUInt16(16_384))

        let pointCloud = try XCTUnwrap(parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 2,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property ushort red",
                "property ushort green",
                "property ushort blue",
            ],
            body: body
        ), name: "ushort_color_le.ply"))

        XCTAssertEqual(pointCloud.pointCount, 2)
        assertColor(pointCloud.colors[0], r: 0, g: 32_768.0 / 65_535.0, b: 1)
        assertColor(pointCloud.colors[1], r: 1, g: 0, b: 16_384.0 / 65_535.0)
    }

    // MARK: - Malformed-input rejection matrix

    func testMalformedASCIIPLYInputsReturnNil() throws {
        let malformedCases: [(name: String, content: String)] = [
            ("truncated_row", """
            ply
            format ascii 1.0
            element vertex 2
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            end_header
            1.0 2.0 3.0 255 128 64
            4.0 5.0 6.0
            """),
            ("extra_vertex_columns", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            1.0 2.0 3.0 4.0
            """),
            ("nan_coordinate", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            nan 1.0 2.0
            """),
            ("float32_overflow_extra_property", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            property float confidence
            end_header
            1.0 2.0 3.0 1e100
            """),
            ("inf_coordinate", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            end_header
            1.0 -inf 2.0
            """),
            ("missing_xyz", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            end_header
            1.0 2.0
            """),
            ("list_property_under_vertex", """
            ply
            format ascii 1.0
            element vertex 1
            property float x
            property float y
            property float z
            property list uchar int vertex_indices
            end_header
            1.0 2.0 3.0 0
            """),
        ]

        for malformed in malformedCases {
            let pointCloud = try parsePLY(malformed.content, name: "\(malformed.name).ply")
            XCTAssertNil(pointCloud, malformed.name)
        }
    }

    func testTruncatedBinaryBodyReturnsNil() throws {
        var body = Data()
        body.append(Self.leFloat32(1))
        body.append(Self.leFloat32(2))
        body.append(Self.leFloat32(3))
        body.append(contentsOf: [255, 128, 64] as [UInt8])

        let pointCloud = try parsePLY(data: binaryPLYData(
            format: "binary_little_endian",
            vertexCount: 3,
            properties: [
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
            ],
            body: body
        ), name: "truncated_binary.ply")

        XCTAssertNil(pointCloud)
    }

    // MARK: - PLY test helpers

    private func parsePLY(_ content: String, name: String = "point_cloud.ply") throws -> PointCloudData? {
        try parsePLY(data: Data(content.utf8), name: name)
    }

    private func parsePLY(data: Data, name: String = "point_cloud.ply") throws -> PointCloudData? {
        let url = try writeTemporaryPLY(name: name, data: data)
        return PLYParserHelper.parsePointCloudData(at: url)
    }

    private func writeTemporaryPLY(name: String, content: String) throws -> URL {
        try writeTemporaryPLY(name: name, data: Data(content.utf8))
    }

    private func writeTemporaryPLY(name: String, data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func binaryPLYData(
        format: String,
        vertexCount: Int,
        properties: [String],
        body: Data
    ) -> Data {
        var data = Data("""
        ply
        format \(format) 1.0
        element vertex \(vertexCount)
        \(properties.joined(separator: "\n"))
        end_header

        """.utf8)
        data.append(body)
        return data
    }

    private func assertVertex(
        _ actual: SCNVector3,
        x: Float,
        y: Float,
        z: Float,
        accuracy: Float = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, z, accuracy: accuracy, file: file, line: line)
    }

    private func assertColor(
        _ actual: PointCloudColor,
        r: Float,
        g: Float,
        b: Float,
        accuracy: Float = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.r, r, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.g, g, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.b, b, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Binary byte-level helpers (endianness-explicit)

    private static func leFloat32(_ value: Float) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ])
    }

    private static func leFloat64(_ value: Double) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 32) & 0xFF),
            UInt8((bits >> 40) & 0xFF),
            UInt8((bits >> 48) & 0xFF),
            UInt8((bits >> 56) & 0xFF),
        ])
    }

    private static func leInt32(_ value: Int32) -> Data {
        let bits = UInt32(bitPattern: value)
        return Data([
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ])
    }

    private static func leUInt16(_ value: UInt16) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
        ])
    }

    private static func beFloat32(_ value: Float) -> Data {
        let bits = value.bitPattern
        return Data([
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8(bits & 0xFF),
        ])
    }
}
