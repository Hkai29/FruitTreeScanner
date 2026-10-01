import XCTest
import CoreVideo
import simd
@testable import FruitTreeScanner

/// Synthetic, bounded replay from copied frame evidence through real persistence.
/// It does not represent a measured tree or validate physical LiDAR accuracy.
final class ScanObservationReplayTests: XCTestCase {
    private enum Evidence {
        case reliable, mixedCloud, lowConfidence, confidenceCopyFailed, imageOnly, cloudOnly
    }

    func testReliableDepthReplayPreservesGeometryYieldAndArchiveAcrossInputOrder() async throws {
        let forward = try await replay(.reliable)
        let reverse = try await replay(.reliable, reverseObservations: true)
        XCTAssertEqual(forward, reverse, "Only generated output IDs and mass timestamps are excluded")
    }

    func testMixedCloudReplayKeepsMeasuredGeometryThroughArchiveAndExport() async throws {
        let forward = try await replay(.mixedCloud)
        let reverse = try await replay(.mixedCloud, reverseObservations: true)
        XCTAssertEqual(forward, reverse, "Mixed geometry must survive input order and persistence")
    }

    func testRequiredCandidateReassignmentSurvivesArchiveAndExport() async throws {
        for reverse in [false, true] {
            try await replayRequiredReassignment(reverseObservations: reverse)
        }
    }

    private func replayRequiredReassignment(reverseObservations: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScanRepository(scansDirectory: directory)
        let source = try repository.pointCloudDestination(filename: "assignment-replay.ply")
        let leftPoints = makePoints(fruitColored: true)
        let points = leftPoints + leftPoints.map {
            ColoredPoint(pos: $0.pos + SIMD3<Float>(0.16, 0, 0), r: $0.r, g: $0.g, b: $0.b)
        }
        let context = ScanContext(scanID: fixedID(1), planID: fixedID(2))
        let signature = RendererSnapshotSignature(pointCount: points.count, pointIndex: points.count,
                                                  voxelSize: 0.005, confidenceThreshold: 1, pointBufferRevision: 1)
        let draft = try repository.stagePointCloud(to: source, captureIdentity: .init(context: context, pointCloud: signature)) {
            try PLYPointCloudWriter.write(points: points, treeID: "assignment-tree",
                                          scanDate: "2026-09-30 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        }
        // World x=.04 can match candidates at 0 and .16 (distances .04/.12).
        // World x=-.06 can only match 0 (.06/.22). The first-to-left edge has
        // the lowest score, so retaining both fruits requires reassigning it.
        var observations = projectionOnlyObservations(centerX: 0.52, confidence: 0.9, idOffset: 0)
        observations += projectionOnlyObservations(centerX: 0.47, confidence: 0.85, idOffset: 100)
        if reverseObservations { observations.reverse() }
        var cluster = ClusterConfig.default
        cluster.baseEps = 0.06
        var experiment = FruitScanExperimentConfig.default
        experiment.pointCloud.denoisingMinPointFloor = 1000
        var diagnostics = ImageDetectionDiagnostics()
        diagnostics.modelStatus = "CoreML"
        diagnostics.modelName = "synthetic-replay-no-inference"
        diagnostics.processedFrameCount = 2
        diagnostics.observationCount = 4
        diagnostics.mappedFruitCount = 4
        var params = FruitVarietyParams(category: .apple)
        params.density = 0.85
        let input = ScanFusionYieldBuilder.Input(
            points: points, observations: observations, imageDiagnostics: diagnostics,
            fruitType: "apple", fruitCategory: .apple, paramsSnapshot: ["apple": params], defaultParams: params,
            clusterConfig: cluster, fusionConfig: .default, colorFilter: nil, finalPointCloudIdentity: signature,
            experimentConfiguration: experiment,
            calibrationIdentity: .init(algorithmRevision: "replay-fixture-v1", context: "synthetic-assignment-context")
        )
        let snapshot = ScanYieldEstimationController.Snapshot(context: context, input: input)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: draft, repository: repository)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        XCTAssertEqual(estimate.evidenceIdentity, frozen.identity)
        let result = estimate.result
        XCTAssertEqual(result.diagnostics.pointCloudClusterCandidateCount, 2)
        XCTAssertEqual(result.diagnostics.detectionDepthCandidateCount, 0, "Line-shaped ROI support cannot form a fruit")
        XCTAssertEqual(result.diagnostics.fusedFruitCount, 2)
        XCTAssertTrue(result.diagnostics.zeroYieldReasons.isEmpty)
        let fruits = result.validatedFruits.sorted { $0.positionX < $1.positionX }
        XCTAssertEqual(fruits.count, 2)
        for (fruit, expected) in zip(fruits, [(Float(0), Float(0.85)), (0.16, 0.9)]) {
            XCTAssertEqual(fruit.positionX, expected.0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionY, 0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionZ, -2, accuracy: 0.00001)
            XCTAssertEqual(fruit.confidence, expected.1, accuracy: 0.00001)
            XCTAssertEqual(fruit.source, "fused")
            XCTAssertEqual(fruit.category, "apple")
        }
        // Symmetric radii .022...030 m fit diameter 5.230679 cm; the established
        // apple prior clamps to 6 cm. pi/6 * 6^3 * .85 = 96.1327352 g per fruit.
        XCTAssertEqual(result.fruitMassEstimates.count, 2)
        for mass in result.fruitMassEstimates {
            XCTAssertEqual(mass.equivalentDiameterCm, 6, accuracy: 0.0001)
            XCTAssertEqual(mass.estimatedWeightG, 96.1327352, accuracy: 0.01)
            XCTAssertEqual(mass.pointCount, 30)
            XCTAssertEqual(mass.shapeModelUsed, .sphere)
        }
        XCTAssertEqual(result.yieldBVisibleKg, 0.168232287, accuracy: 0.00001)

        let committed = try repository.commit(ScanAssessment(receipt: frozen.receipt, estimate: estimate,
            treeID: "assignment-tree", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1_790_726_400),
            gpsLat: 0, gpsLon: 0, includeCSV: true))
        let verified = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(verified.summary.persistenceState, .complete)
        XCTAssertEqual(verified.summary.fruitCount, result.nLidar)
        XCTAssertEqual(verified.summary.yieldKg, result.yieldFinalKg)
        XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: source), draft.sourceSHA256)
        let metadata = try json(at: committed.metadataURL)
        let exported = try await BatchExportService.shared.export(records: [verified.summary], format: .json, options: .init())
        defer { BatchExportService.removeTemporaryExport(at: exported.url) }
        let payload = try json(at: exported.url)
        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["estimatedCount"] as? Int, result.nLidar)
        XCTAssertEqual(try number(record, "estimatedYieldKg"), result.yieldFinalKg)
        XCTAssertEqual(record["zeroYieldReasons"] as? [String], [])
        XCTAssertEqual(record["sourceCounts"] as? [String: Int],
                       ["validatedFruitCount": 2, "fusedCount": 2, "trackedImageCount": 0,
                        "imageOnlyCount": 0, "cloudOnlyCount": 0])
        for key in ["validatedFruits", "fruitMassEstimates"] {
            let rows = try XCTUnwrap(record[key] as? [[String: Any]])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys),
                           try JSONSerialization.data(withJSONObject: XCTUnwrap(metadata[key]), options: .sortedKeys))
            let expectedIDs = key == "validatedFruits" ? result.validatedFruits.map(\.id) : result.fruitMassEstimates.map { $0.id.uuidString }
            XCTAssertEqual(rows.compactMap { $0["id"] as? String }, expectedIDs)
        }
    }

    private func projectionOnlyObservations(centerX: Float, confidence: Float, idOffset: Int) -> [Observation] {
        // A copied frame may have only one reliable depth row. It still gives a
        // valid projection median, but does not pass the ROI fruit-shape gate.
        let samples = (0..<9).map { column in
            ObservationDepthSample(normalizedImageX: centerX - 0.006 + 0.012 * (Float(column) + 0.5) / 9,
                                   normalizedImageY: 0.5, depthMeters: 2, row: 4, column: column)
        }
        return (0..<2).map { index in
            Observation(id: fixedID(10 + index + idOffset), frameID: FrameID(rawValue: fixedID(20 + index)),
                category: .apple, boundingBox: CGRect(x: CGFloat(centerX) - 0.006, y: 0.494, width: 0.012, height: 0.012),
                confidence: confidence, timestamp: 10 + Double(index) * 0.1,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: simd_float3x3(SIMD3<Float>(1000, 0, 0), SIMD3<Float>(0, 1000, 0), SIMD3<Float>(500, 500, 1)),
                imageSize: CGSize(width: 1000, height: 1000), coordinateConvention: .visionNormalizedLowerLeft,
                depthConfidenceProvenance: .available, hasDepthMap: true, roiDepthSamples: samples,
                projectionDepthSamples: Array(repeating: 2, count: 9), rejectionReasons: [])
        }
    }

    func testLowConfidenceDepthReplayCannotPromoteMatchingCloudToReliableYield() async throws {
        _ = try await replay(.lowConfidence)
    }

    func testConfidenceCopyFailureReplayPreservesRejectionThroughResearchExport() async throws {
        _ = try await replay(.confidenceCopyFailed)
    }

    func testImageOnlyReplayCannotPromoteMatchingCloudToReliableYield() async throws {
        _ = try await replay(.imageOnly)
    }

    func testCloudOnlyReplayRemainsZeroThroughResearchExport() async throws {
        _ = try await replay(.cloudOnly)
    }

    func testDifferentSizeFruitsKeepTheirMassAndConfidenceAcrossReplayOrder() async throws {
        for reverse in [false, true] {
            try await replayMultipleFruits(includeOtherCategory: false, reverseObservations: reverse)
        }
    }

    func testOverlappingOtherCategoryCannotChangeTargetMassThroughResearchExport() async throws {
        for reverse in [false, true] {
            try await replayMultipleFruits(includeOtherCategory: true, reverseObservations: reverse)
        }
    }

    private func replayMultipleFruits(includeOtherCategory: Bool, reverseObservations: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScanRepository(scansDirectory: directory)
        let source = try repository.pointCloudDestination(filename: "multiple-fruits.ply")
        // Green cloud supplies the archive geometry, while two disjoint RGB/depth
        // ROIs supply fruit geometry. Centers are 11 cm apart: both assignment
        // cross-edges pass the 15 cm center gate, but the correct edges cost less.
        let points = makePoints(fruitColored: false)
        let context = ScanContext(scanID: fixedID(1), planID: fixedID(2))
        let signature = RendererSnapshotSignature(pointCount: points.count, pointIndex: points.count,
                                                  voxelSize: 0.005, confidenceThreshold: 1,
                                                  pointBufferRevision: 1)
        let draft = try repository.stagePointCloud(to: source, captureIdentity: .init(context: context, pointCloud: signature)) {
            try PLYPointCloudWriter.write(points: points, treeID: "two-apples",
                                          scanDate: "2026-09-30 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        }
        var observations = try makeObservations(.reliable, centerX: 0.4725, width: 0.020, confidence: 0.95)
        observations += try makeObservations(.reliable, centerX: 0.5275, width: 0.030, idOffset: 100)
        if includeOtherCategory {
            // The larger, more confident pear overlaps the small apple exactly.
            // It must remain diagnostic evidence, not steal its mass or count.
            observations += try makeObservations(.reliable, category: .pear, centerX: 0.4725,
                                                  width: 0.030, confidence: 0.99, idOffset: 200)
        }
        if reverseObservations { observations.reverse() }
        var diagnostics = ImageDetectionDiagnostics()
        diagnostics.modelStatus = "CoreML"
        diagnostics.modelName = "synthetic-replay-no-inference"
        diagnostics.processedFrameCount = 2
        diagnostics.observationCount = observations.count
        diagnostics.mappedFruitCount = observations.count
        var params = FruitVarietyParams(category: .apple)
        params.density = 0.85
        let input = ScanFusionYieldBuilder.Input(
            points: points, observations: observations, imageDiagnostics: diagnostics,
            fruitType: "apple", fruitCategory: .apple, paramsSnapshot: ["apple": params],
            defaultParams: params, clusterConfig: .default, fusionConfig: .default, colorFilter: nil,
            finalPointCloudIdentity: signature,
            calibrationIdentity: .init(algorithmRevision: "replay-fixture-v1", context: "synthetic-fixed-context")
        )
        let snapshot = ScanYieldEstimationController.Snapshot(context: context, input: input)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: draft, repository: repository)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        XCTAssertEqual(estimate.evidenceIdentity, frozen.identity)
        let result = estimate.result

        // Independently calculated pinhole/grid diameters:
        // d(cm) = 100 * (.75 * 2 * boxWidth * 8/9 * sqrt(2) * 1.25 + .25 * .08).
        // Sphere masses use pi/6*d^3*.85; confidence weights are .95*.9 and .9*.9.
        // Weighted visible count 1.665, rounded input 2, coverage .25 => K=2.999.
        XCTAssertEqual(result.nLidar, 5)
        XCTAssertEqual(result.yieldBVisibleKg, 0.384246988, accuracy: 0.00001)
        XCTAssertEqual(result.yieldFinalKg, 1.152356717, accuracy: 0.00003)
        XCTAssertEqual(result.meanDiameterCm, 7.860704853, accuracy: 0.0001)
        XCTAssertEqual(result.meanVolumeCm3, 271.5046727, accuracy: 0.01)
        XCTAssertEqual(result.occlusionK, 2.999, accuracy: 0.00001)
        XCTAssertTrue(result.diagnostics.zeroYieldReasons.isEmpty)
        XCTAssertFalse(result.diagnostics.cloudOnlyConservativeMode)
        XCTAssertEqual(result.diagnostics.pointCloudClusterCandidateCount, 0)
        XCTAssertEqual(result.diagnostics.detectionDepthCandidateCount, includeOtherCategory ? 3 : 2)
        XCTAssertEqual(result.diagnostics.filteredBySelectedFruitTypeCount, includeOtherCategory ? 2 : 0)
        XCTAssertEqual(result.diagnostics.fusedFruitCount, 2)
        let fruits = result.validatedFruits.sorted { $0.positionX < $1.positionX }
        XCTAssertEqual(fruits.count, 2)
        for (fruit, expected) in zip(fruits, [(Float(-0.055), Float(0.855)), (0.055, 0.81)]) {
            XCTAssertEqual(fruit.category, "apple")
            XCTAssertEqual(fruit.source, "fused")
            XCTAssertEqual(fruit.positionX, expected.0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionY, 0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionZ, -2, accuracy: 0.00001)
            XCTAssertEqual(fruit.confidence, expected.1, accuracy: 0.00001)
        }
        let masses = result.fruitMassEstimates.sorted { $0.equivalentDiameterCm < $1.equivalentDiameterCm }
        XCTAssertEqual(masses.count, 2)
        let expectedMasses: [(Float, Float, Float)] = [(6.714045208, 134.7008485, 0.855), (9.071067812, 332.1947685, 0.81)]
        for (mass, expected) in zip(masses, expectedMasses) {
            XCTAssertEqual(mass.fruitCategory, "apple")
            XCTAssertEqual(mass.shapeModelUsed, .sphere)
            XCTAssertEqual(mass.equivalentDiameterCm, expected.0, accuracy: 0.0001)
            XCTAssertEqual(mass.estimatedWeightG, expected.1, accuracy: 0.01)
            XCTAssertEqual(mass.highConfidenceRatio, expected.2, accuracy: 0.00001,
                           "Each size must retain its own assigned fruit's confidence")
            XCTAssertEqual(mass.pointCount, 162)
            XCTAssertEqual(mass.validDepthRatio, 1)
        }

        let assessment = ScanAssessment(receipt: frozen.receipt, estimate: estimate,
                                        treeID: "two-apples", fruitType: "apple",
                                        scanDate: Date(timeIntervalSince1970: 1_790_726_400),
                                        gpsLat: 0, gpsLon: 0, includeCSV: true)
        let committed = try repository.commit(assessment)
        let verified = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(verified.summary.persistenceState, .complete)
        XCTAssertEqual(verified.summary.fruitCount, 5)
        XCTAssertEqual(verified.summary.yieldKg, 1.152356717, accuracy: 0.00003)
        XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: source), draft.sourceSHA256)
        let metadata = try json(at: committed.metadataURL)
        let storedDiagnostics = try XCTUnwrap(metadata["recognitionDiagnostics"] as? [String: Any])
        XCTAssertEqual(storedDiagnostics["filteredBySelectedFruitTypeCount"] as? Int, includeOtherCategory ? 2 : 0)
        let exported = try await BatchExportService.shared.export(records: [verified.summary], format: .json, options: .init())
        defer { BatchExportService.removeTemporaryExport(at: exported.url) }
        let payload = try json(at: exported.url)
        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["estimatedCount"] as? Int, 5)
        XCTAssertEqual(try number(record, "estimatedYieldKg"), 1.152356717, accuracy: 0.00003)
        XCTAssertEqual(record["zeroYieldReasons"] as? [String], [])
        let exportedRecognition = try XCTUnwrap(record["recognitionDiagnostics"] as? [String: Any])
        XCTAssertEqual(exportedRecognition["filteredBySelectedFruitTypeCount"] as? Int, includeOtherCategory ? 2 : 0)
        XCTAssertEqual(record["sourceCounts"] as? [String: Int],
                       ["validatedFruitCount": 2, "fusedCount": 2, "trackedImageCount": 0,
                        "imageOnlyCount": 0, "cloudOnlyCount": 0])
        for (key, expectedRows) in [("validatedFruits", try JSONEncoder().encode(result.validatedFruits)),
                                    ("fruitMassEstimates", try JSONEncoder().encode(result.fruitMassEstimates))] {
            let rows = try XCTUnwrap(record[key] as? [[String: Any]])
            XCTAssertEqual(rows.count, 2)
            let storedRows = try JSONSerialization.data(withJSONObject: XCTUnwrap(metadata[key]), options: .sortedKeys)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys), storedRows)
            // The archive's JSONSerialization expands Float decimals. Decode to
            // the source types before comparing to JSONEncoder's short decimals.
            let rowData = try JSONSerialization.data(withJSONObject: rows)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let roundTripData: Data
            if key == "validatedFruits" {
                roundTripData = try JSONEncoder().encode(decoder.decode([ValidatedFruitData].self, from: rowData))
            } else {
                let restored = try decoder.decode([FruitMassEstimate].self, from: rowData)
                for (actual, original) in zip(restored, result.fruitMassEstimates) {
                    XCTAssertEqual(actual.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 1)
                }
                roundTripData = try JSONEncoder().encode(restored)
            }
            let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: roundTripData) as? [[String: Any]])
            let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedRows) as? [[String: Any]])
            func withoutDate(_ rows: [[String: Any]]) throws -> Data {
                try JSONSerialization.data(withJSONObject: rows.map { row in
                    var value = row
                    value.removeValue(forKey: "createdAt")
                    return value
                }, options: .sortedKeys)
            }
            XCTAssertEqual(try withoutDate(roundTrip), try withoutDate(expected))
        }
    }

    private func replay(_ evidence: Evidence, reverseObservations: Bool = false) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScanRepository(scansDirectory: directory)
        let source = try repository.pointCloudDestination(filename: "synthetic-replay.ply")
        let points = makePoints(fruitColored: evidence != .reliable)
        let context = ScanContext(scanID: fixedID(1), planID: fixedID(2))
        let signature = RendererSnapshotSignature(pointCount: points.count, pointIndex: points.count,
                                                  voxelSize: 0.005, confidenceThreshold: 1,
                                                  pointBufferRevision: 1)
        let draft = try repository.stagePointCloud(to: source, captureIdentity: .init(context: context, pointCloud: signature)) {
            try PLYPointCloudWriter.write(points: points, treeID: "synthetic-tree",
                                          scanDate: "2026-09-29 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        }
        var observations = try makeObservations(evidence)
        if reverseObservations { observations.reverse() }
        var imageDiagnostics = ImageDetectionDiagnostics()
        imageDiagnostics.modelStatus = "CoreML"
        imageDiagnostics.modelName = "synthetic-replay-no-inference"
        imageDiagnostics.processedFrameCount = observations.count
        imageDiagnostics.observationCount = observations.count
        imageDiagnostics.mappedFruitCount = observations.count
        var params = FruitVarietyParams(category: .apple)
        params.density = 0.85
        let input = ScanFusionYieldBuilder.Input(
            points: points, observations: observations, imageDiagnostics: imageDiagnostics,
            fruitType: "apple", fruitCategory: .apple, paramsSnapshot: ["apple": params],
            defaultParams: params, clusterConfig: .default, fusionConfig: .default, colorFilter: nil,
            finalPointCloudIdentity: signature,
            calibrationIdentity: .init(algorithmRevision: "replay-fixture-v1", context: "synthetic-fixed-context")
        )
        let snapshot = ScanYieldEstimationController.Snapshot(context: context, input: input)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: draft, repository: repository)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        XCTAssertEqual(estimate.evidenceIdentity, frozen.identity)
        XCTAssertEqual(estimate.evidenceIdentity.capture.context, context)
        XCTAssertEqual(estimate.evidenceIdentity.snapshotID, snapshot.id)
        let result = estimate.result
        let mixedCloud = evidence == .mixedCloud
        let reliable = evidence == .reliable || mixedCloud
        let expectedCount = mixedCloud ? 3 : (reliable ? 2 : 0)
        let expectedYield: Float = mixedCloud ? 0.131231352 : (reliable ? 0.48540313 : 0)
        let expectedReasons: [String]
        switch evidence {
        case .reliable, .mixedCloud:
            expectedReasons = []
        case .lowConfidence:
            expectedReasons = [L10n.Diagnostics.fusionFailed, L10n.Diagnostics.cloudOnlyRejected]
        case .confidenceCopyFailed:
            expectedReasons = [L10n.Diagnostics.depthUnavailable, DepthConfidenceProvenance.copyFailureReason,
                               L10n.Diagnostics.fusionFailed, L10n.Diagnostics.cloudOnlyRejected]
        case .imageOnly:
            expectedReasons = [L10n.Diagnostics.depthUnavailable, L10n.Diagnostics.fusionFailed,
                               L10n.Diagnostics.cloudOnlyRejected]
        case .cloudOnly:
            expectedReasons = [L10n.Diagnostics.depthUnavailable, L10n.Diagnostics.noImageFrames,
                               L10n.Diagnostics.noDetections]
        }
        XCTAssertEqual(result.nLidar, expectedCount)
        XCTAssertEqual(result.yieldFinalKg, expectedYield, accuracy: 0.00001)
        XCTAssertEqual(result.diagnostics.zeroYieldReasons, expectedReasons)
        XCTAssertEqual(result.diagnostics.pointCloudClusterCandidateCount, evidence == .reliable ? 0 : 1)
        XCTAssertEqual(result.diagnostics.detectionDepthCandidateCount, reliable ? 1 : 0)
        XCTAssertEqual(result.diagnostics.fusedFruitCount, reliable ? 1 : 0)
        XCTAssertEqual(result.diagnostics.cloudOnlyConservativeMode, !reliable)
        XCTAssertEqual(result.validatedFruits.count, reliable ? 1 : 0)
        XCTAssertEqual(result.fruitMassEstimates.count, reliable ? 1 : 0)
        if reliable {
            // Independent hand calculation: pinhole width = 2 m * .024 = .048 m.
            // Grid diagonal = .048 * 8/9 * sqrt(2). Established size prior blends
            // 75% of diagonal * 1.25 with 25% of .08 m: diameter 7.65685425 cm.
            // Sphere volume = pi/6 * diameter^3; density .85 g/cm3. The established
            // fusion weight is .9 image confidence * .9 shape * 1 depth support = .81.
            // Visible yield = 199.7876731 g * .81 / 1000; K = 2.9995;
            // corrected count = round(.81 * K) = 2, while reliable fruit count is 1.
            // Mixed cloud adds 30 symmetric axis points at radii .022...030 m
            // to the 162 ROI samples. The 5/95% x/y span is 4.266666667 cm;
            // z's central span is zero, so its raw span is 6 cm. The least-squares
            // sphere diameter is 4.1321907 cm, below the apple prior's 4.8 cm floor.
            // Thus the measured ellipsoid uses pi/6*4.266666667^2*6 = 57.190948929
            // cm3, yielding 48.61230659 g. Cloud sphericity 1 gives weight .9;
            // corrected count round(.9*K)=3. Reusing the ROI sphere would be wrong.
            XCTAssertEqual(result.algorithmRevision, "replay-fixture-v1")
            XCTAssertEqual(result.calibrationContext, "synthetic-fixed-context")
            XCTAssertEqual(result.meanDiameterCm, mixedCloud ? 4.844444444 : 7.65685425, accuracy: 0.0001)
            XCTAssertEqual(result.meanVolumeCm3, mixedCloud ? 57.190948929 : 235.0443213, accuracy: 0.01)
            XCTAssertEqual(result.yieldBVisibleKg, mixedCloud ? 0.043751076 : 0.16182802, accuracy: 0.00001)
            XCTAssertEqual(result.occlusionK, 2.9995, accuracy: 0.00001)
            let fruit = try XCTUnwrap(result.validatedFruits.first)
            XCTAssertEqual(fruit.source, "fused")
            XCTAssertEqual(fruit.category, "apple")
            XCTAssertEqual(fruit.confidence, mixedCloud ? 0.9 : 0.81, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionX, 0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionY, 0, accuracy: 0.00001)
            XCTAssertEqual(fruit.positionZ, -2, accuracy: 0.00001)
            let mass = try XCTUnwrap(result.fruitMassEstimates.first)
            XCTAssertEqual(mass.shapeModelUsed, mixedCloud ? .ellipsoid : .sphere)
            XCTAssertEqual(mass.estimatedWeightG, mixedCloud ? 48.61230659 : 199.7876731, accuracy: 0.01)
            XCTAssertEqual(mass.pointCount, mixedCloud ? 192 : 162)
            XCTAssertEqual(mass.validDepthRatio, 1)
            if mixedCloud {
                XCTAssertEqual(mass.lengthCm, 4.266666667, accuracy: 0.0001)
                XCTAssertEqual(mass.widthCm, 4.266666667, accuracy: 0.0001)
                XCTAssertEqual(mass.heightCm, 6, accuracy: 0.0001)
                XCTAssertTrue(mass.warningFlags.contains(.usingEllipsoidBaseline))
                XCTAssertFalse(mass.warningFlags.contains(.usingSphereBaseline))
            }
        }

        let assessment = ScanAssessment(receipt: frozen.receipt, estimate: estimate,
                                        treeID: "synthetic-tree", fruitType: "apple",
                                        scanDate: Date(timeIntervalSince1970: 1_790_640_000),
                                        gpsLat: 0, gpsLon: 0, includeCSV: true)
        let committed = try repository.commit(assessment)
        let verified = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(verified.manifest?.scanID, "synthetic-replay")
        XCTAssertEqual(verified.summary.persistenceState, .complete)
        XCTAssertEqual(verified.summary.fruitCount, expectedCount)
        XCTAssertEqual(verified.summary.yieldKg, expectedYield, accuracy: 0.00001)
        XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: source), draft.sourceSHA256)
        let metadata = try json(at: committed.metadataURL)
        let storedDiagnostics = try XCTUnwrap(metadata["diagnostics"] as? [String: Any])
        XCTAssertEqual(storedDiagnostics["zeroYieldReasons"] as? [String], expectedReasons)

        let exported = try await BatchExportService.shared.export(records: [verified.summary], format: .json, options: .init())
        defer { BatchExportService.removeTemporaryExport(at: exported.url) }
        let payload = try json(at: exported.url)
        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        var record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["estimatedCount"] as? Int, expectedCount)
        XCTAssertEqual(try number(record, "estimatedYieldKg"), expectedYield, accuracy: 0.00001)
        XCTAssertEqual(record["zeroYieldReasons"] as? [String], expectedReasons)
        let sources = try XCTUnwrap(record["sourceCounts"] as? [String: Int])
        XCTAssertEqual(sources, ["validatedFruitCount": reliable ? 1 : 0, "fusedCount": reliable ? 1 : 0,
                                 "trackedImageCount": 0, "imageOnlyCount": 0, "cloudOnlyCount": 0])
        for key in ["validatedFruits", "fruitMassEstimates"] {
            let rows = try XCTUnwrap(record[key] as? [[String: Any]])
            XCTAssertEqual(rows.count, reliable ? 1 : 0)
            // Verify the actual exported rows first, then normalize only nondeterministic metadata.
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys),
                           try JSONSerialization.data(withJSONObject: XCTUnwrap(metadata[key]), options: .sortedKeys))
            record[key] = rows.map { row in
                var normalized = row
                normalized.removeValue(forKey: "id")
                if key == "fruitMassEstimates" { normalized.removeValue(forKey: "createdAt") }
                return normalized
            }
        }
        return try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
    }

    private func makeObservations(_ evidence: Evidence, category: FruitCategory = .apple,
                                  centerX: CGFloat = 0.5, width: CGFloat = 0.024,
                                  confidence imageConfidence: Float = 0.9, idOffset: Int = 0) throws -> [Observation] {
        guard evidence != .cloudOnly else { return [] }
        let depth = try buffer(format: kCVPixelFormatType_DepthFloat32) { base, stride in
            for row in 0..<32 {
                let values = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
                for column in 0..<32 { values[column] = 2 }
            }
        }
        let confidence = try buffer(format: kCVPixelFormatType_OneComponent8) { base, stride in
            for row in 0..<32 {
                let values = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
                for column in 0..<32 { values[column] = evidence == .lowConfidence ? 0 : 2 }
            }
        }
        return (0..<2).map { index in
            let observation = Observation.capture(
                id: fixedID(10 + index + idOffset), frameID: FrameID(rawValue: fixedID(20 + index)),
                category: category, boundingBox: CGRect(x: centerX - width / 2, y: 0.5 - width / 2, width: width, height: width),
                confidence: imageConfidence, timestamp: 10 + Double(index) * 0.1,
                cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: simd_float3x3(SIMD3<Float>(1000, 0, 0), SIMD3<Float>(0, 1000, 0), SIMD3<Float>(500, 500, 1)),
                imageSize: CGSize(width: 1000, height: 1000),
                depthMap: evidence == .imageOnly ? nil : depth,
                depthConfidenceMap: evidence == .confidenceCopyFailed ? nil : confidence,
                depthConfidenceProvenance: evidence == .confidenceCopyFailed ? .copyFailed : .available
            )
            switch evidence {
            case .reliable, .mixedCloud:
                XCTAssertEqual(observation.roiDepthSamples.count, 81)
                XCTAssertEqual(observation.projectionDepthSamples.count, 81)
                XCTAssertTrue(observation.rejectionReasons.isEmpty)
            case .lowConfidence:
                XCTAssertTrue(observation.roiDepthSamples.isEmpty)
                XCTAssertTrue(observation.projectionDepthSamples.isEmpty)
                XCTAssertEqual(observation.rejectionReasons, [.noReliableDepthSamples])
            case .confidenceCopyFailed:
                XCTAssertEqual(observation.rejectionReasons, [.confidenceCopyFailed])
            case .imageOnly:
                XCTAssertEqual(observation.rejectionReasons, [.missingDepthMap])
            case .cloudOnly:
                break
            }
            return observation
        }
    }

    private func makePoints(fruitColored: Bool) -> [ColoredPoint] {
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
                                    SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
        return (0..<5).flatMap { index in
            axes.map { axis in
                ColoredPoint(pos: SIMD3<Float>(0, 0, -2) + axis * (0.022 + Float(index) * 0.002),
                             r: fruitColored ? 0.7 : 0.32, g: fruitColored ? 0.25 : 0.45,
                             b: fruitColored ? 0.15 : 0.18)
            }
        }
    }

    private func buffer(format: OSType, fill: (UnsafeMutableRawPointer, Int) -> Void) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, format, nil, &output), kCVReturnSuccess)
        let buffer = try XCTUnwrap(output)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        fill(try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)), CVPixelBufferGetBytesPerRow(buffer))
        return buffer
    }

    private func fixedID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func json(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func number(_ object: [String: Any], _ key: String) throws -> Float {
        try XCTUnwrap(object[key] as? NSNumber).floatValue
    }
}
