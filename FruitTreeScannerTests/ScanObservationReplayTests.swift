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

    func testArchivedReplayRejectsOverflowingClusterConfiguration() async throws {
        var cluster = ClusterConfig.default
        cluster.minPoints = .max
        let record = try archivedReplay(cluster: cluster)
        XCTAssertEqual(record.input.clusterConfig.minPoints, .max, "Archiving must not repair the original input")
        do {
            _ = try await ScanObservationReplay.run(record)
            XCTFail("Unsafe decoded configuration must be rejected before algorithm execution")
        } catch ScanReplayError.invalidArchive { }
    }

    func testArchivedReplayRejectsOverflowingNeighborConfiguration() async throws {
        var experiment = FruitScanExperimentConfig.default
        experiment.pointCloud.denoisingNeighborCount = .max
        let record = try archivedReplay(experiment: experiment)
        XCTAssertEqual(record.input.experimentConfiguration.pointCloud.denoisingNeighborCount, .max)
        try await assertReplayRejected(record)
    }

    func testArchivedReplayRejectsExtremeFinitePoints() async throws {
        let large = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        let points = (0..<50).flatMap { _ in
            [ColoredPoint(pos: large, r: 0.7, g: 0.2, b: 0.1), ColoredPoint(pos: -large, r: 0.7, g: 0.2, b: 0.1)]
        } + [ColoredPoint(pos: .zero, r: 0.7, g: 0.2, b: 0.1)]
        let record = try archivedReplay(points: points, observations: [])
        XCTAssertEqual(record.input.points.first?.pos.x.bitPattern, Float.greatestFiniteMagnitude.bitPattern)
        try await assertReplayRejected(record)
    }

    func testArchivedReplayRejectsUnsafeCalibrationFactors() async throws {
        for factor in [Float.nan, .infinity, .greatestFiniteMagnitude] {
            let correction = YieldCalibrationCorrection(countFactor: factor, yieldFactor: 1,
                                                        countSampleCount: 1, yieldSampleCount: 0)
            let record = try archivedReplay(calibration: correction)
            if factor.isNaN { XCTAssertTrue(record.input.calibrationCorrection.countFactor.isNaN) }
            else { XCTAssertEqual(record.input.calibrationCorrection.countFactor.bitPattern, factor.bitPattern) }
            try await assertReplayRejected(record)
        }
    }

    func testArchivedReplayRejectsExtremeROIGridIndices() async throws {
        let original = try XCTUnwrap(makeObservations(.reliable).first)
        let samples = original.roiDepthSamples.enumerated().map { index, sample in
            ObservationDepthSample(normalizedImageX: sample.normalizedImageX, normalizedImageY: sample.normalizedImageY,
                depthMeters: sample.depthMeters, row: index == 0 ? Int.min : Int.max, column: sample.column)
        }
        let observation = Observation(id: original.id, frameID: original.frameID, category: original.category,
            boundingBox: original.boundingBox, confidence: original.confidence, timestamp: original.timestamp,
            cameraTransform: original.cameraTransform, cameraIntrinsics: original.cameraIntrinsics, imageSize: original.imageSize,
            coordinateConvention: original.coordinateConvention, depthConfidenceProvenance: original.depthConfidenceProvenance,
            hasDepthMap: original.hasDepthMap, roiDepthSamples: samples,
            projectionDepthSamples: original.projectionDepthSamples, rejectionReasons: original.rejectionReasons)
        let record = try archivedReplay(observations: [observation])
        XCTAssertEqual(record.input.observations.first?.roiDepthSamples.first?.row, Int.min)
        try await assertReplayRejected(record)
    }

    func testArchivedReplayPreservesExactPointBits() throws {
        let points = [ColoredPoint(pos: .init(1.1234567, -0.0000123, -2.7654321), r: -0.0, g: 0.7654321, b: 0.5),
                      ColoredPoint(pos: .init(-0.0, 0.0, -2), r: 0.1234567, g: 0.2, b: 1)]
        let record = try archivedReplay(points: points, observations: [])
        XCTAssertEqual(record.input.points.count, points.count)
        for (original, restored) in zip(points, record.input.points) {
            XCTAssertEqual([original.pos.x, original.pos.y, original.pos.z, original.r, original.g, original.b].map(\.bitPattern),
                           [restored.pos.x, restored.pos.y, restored.pos.z, restored.r, restored.g, restored.b].map(\.bitPattern))
        }
    }

    func testArchivedReplayKeepsHealthyAndRejectedDepthSemantics() async throws {
        let healthy = try archivedReplay()
        let healthyReport = try await ScanObservationReplay.run(healthy)
        XCTAssertGreaterThan(healthyReport.result.nLidar, 0)
        XCTAssertFalse(healthyReport.result.validatedFruits.isEmpty)
        XCTAssertTrue(healthyReport.result.validatedFruits.allSatisfy { $0.source == "fused" })
        let rejectedObservations = try makeObservations(.confidenceCopyFailed)
        let rejected = try archivedReplay(observations: rejectedObservations)
        XCTAssertEqual(rejected.input.observations.map(\.rejectionReasons), rejectedObservations.map(\.rejectionReasons))
        XCTAssertTrue(rejected.input.observations.allSatisfy { $0.depthConfidenceProvenance == .copyFailed })
        let rejectedReport = try await ScanObservationReplay.run(rejected)
        XCTAssertEqual(rejectedReport.result.nLidar, 0)
        XCTAssertEqual(rejectedReport.result.yieldFinalKg, 0)
        XCTAssertTrue(rejectedReport.result.diagnostics.zeroYieldReasons.contains(DepthConfidenceProvenance.copyFailureReason))
    }

    private func assertReplayRejected(_ record: ScanObservationReplayRecord, file: StaticString = #filePath, line: UInt = #line) async throws {
        do {
            _ = try await ScanObservationReplay.run(record)
            XCTFail("Unsafe restored input must be rejected before execution", file: file, line: line)
        } catch ScanReplayError.invalidArchive { }
    }

    /// Exercises the real bounded files and reader before executing the input.
    private func archivedReplay(
        cluster: ClusterConfig = .default,
        experiment: FruitScanExperimentConfig = .default,
        calibration: YieldCalibrationCorrection = .neutral,
        points suppliedPoints: [ColoredPoint]? = nil,
        observations suppliedObservations: [Observation]? = nil
    ) throws -> ScanObservationReplayRecord {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory, cluster: cluster, experiment: experiment,
            calibration: calibration, points: suppliedPoints, observations: suppliedObservations)
        let prepared = try ScanReplayArchive.prepare(input: fixture.input, identity: fixture.identity,
                                                     plan: fixture.plan, draft: fixture.draft)
        let pending = try XCTUnwrap(prepared.directory)
        let (dto, restored) = try ScanReplayArchive.read(inputURL: pending.appendingPathComponent("input.json"),
            pointsURL: pending.appendingPathComponent("points.f32"), descriptor: prepared.descriptor)
        return ScanObservationReplayRecord(identity: dto.identity, producer: dto.producer, input: restored,
            goldenData: Data("{}".utf8), exportRevision: "synthetic-not-a-committed-record")
    }

    private struct ReplayFixture {
        let repository: ScanRepository
        let draft: DraftScan
        let plan: ScanPlan
        let input: ScanFusionYieldBuilder.Input
        let identity: ScanEvidenceIdentity
    }

    private func replayFixture(at directory: URL, cluster: ClusterConfig = .default,
        experiment: FruitScanExperimentConfig = .default, calibration: YieldCalibrationCorrection = .neutral,
        points suppliedPoints: [ColoredPoint]? = nil, observations suppliedObservations: [Observation]? = nil) throws -> ReplayFixture {
        let repository = ScanRepository(scansDirectory: directory)
        let source = try repository.pointCloudDestination(filename: "PRIVATE_FILENAME-\(UUID()).ply")
        let points = suppliedPoints ?? makePoints(fruitColored: true)
        let observations = try suppliedObservations ?? makeObservations(.reliable)
        let context = ScanContext(scanID: fixedID(1), planID: fixedID(2))
        let signature = RendererSnapshotSignature(pointCount: points.count, pointIndex: points.count,
                                                  voxelSize: 0.005, confidenceThreshold: 1, pointBufferRevision: 1)
        let draft = try repository.stagePointCloud(to: source, captureIdentity: .init(context: context, pointCloud: signature)) {
            try PLYPointCloudWriter.write(points: points, treeID: "PRIVATE_TREE_SENTINEL",
                                          scanDate: "2023-11-14 22:13:20", gpsLat: 12.345678, gpsLon: 67.891234, to: source)
        }
        var params = FruitVarietyParams(category: .apple)
        params.density = 0.85
        let input = ScanFusionYieldBuilder.Input(points: points, observations: observations,
            imageDiagnostics: .init(), fruitType: "apple", fruitCategory: .apple,
            paramsSnapshot: ["apple": params], defaultParams: params, clusterConfig: cluster,
            fusionConfig: .default, colorFilter: nil, calibrationCorrection: calibration,
            finalPointCloudIdentity: signature, experimentConfiguration: experiment)
        let fruit = ScanFruitConfiguration(selectedCategory: .apple, parametersSnapshot: input.paramsSnapshot,
            defaultParams: params, clusterConfig: cluster, fusionConfig: .default, colorFilter: FruitCategory.apple.colorFilter,
            calibrationCorrection: calibration, calibrationWarning: nil, calibrationContext: nil, modelIdentity: .modelMissing)
        let renderer = RendererScanSettings(maxPoints: 120_000, rgbRadius: 1.5, minDepth: 0.1, maxDepth: 10,
            confidenceThreshold: 1, depthEdgeThreshold: 0.1, minimumStableDepthNeighborCount: 1,
            snapshotVoxelSize: 0.005, depthConfiguration: experiment.depth)
        let plan = ScanPlan(id: context.planID, treeID: "synthetic-tree", season: .mature, fruitConfiguration: fruit,
            rendererSettings: renderer, resourceBudget: .default, requestedCameraResolution: "1080p",
            requestedCameraFrameRate: "60fps", autoExportCSV: true, modelIdentity: .modelMissing,
            experimentConfiguration: experiment,
            classification: .init(plot: .init(id: fixedID(40), name: "PRIVATE_PLOT_SENTINEL"),
                                  tags: [.init(id: fixedID(41), name: "PRIVATE_TAG_SENTINEL")]))
        let identity = ScanEvidenceIdentity(capture: try XCTUnwrap(draft.captureIdentity), snapshotID: fixedID(3),
            sourceOwnershipID: draft.ownershipID, sourceSHA256: draft.sourceSHA256)
        return ReplayFixture(repository: repository, draft: draft, plan: plan, input: input, identity: identity)
    }

    private func assessment(_ fixture: ReplayFixture) async throws -> ScanAssessment {
        let snapshot = ScanYieldEstimationController.Snapshot(context: fixture.identity.capture.context, input: fixture.input)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: fixture.draft,
            repository: fixture.repository, plan: fixture.plan)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        return ScanAssessment(receipt: frozen.receipt, estimate: estimate, treeID: "PRIVATE_TREE_SENTINEL",
            fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1_700_000_000),
            gpsLat: 12.345678, gpsLon: 67.891234, includeCSV: true, classification: fixture.plan.classification)
    }

    func testReplayBundleReaderRemainsFailedAfterTrailingDataError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        _ = try fixture.repository.commit(await assessment(fixture))
        let record = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        let destination = directory.appendingPathComponent("replay.ftsreplay")
        try ScanReplayBundle.write(records: [record], repository: fixture.repository, to: destination)
        let handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        let reader = try ScanReplayBundle.Reader(at: destination)
        XCTAssertThrowsError(try reader.next())
        XCTAssertThrowsError(try reader.next(), "A failed reader must not subsequently report normal completion")
    }

    private final class ReplayRestoreFailureFileManager: FileManager {
        override func copyItem(at source: URL, to destination: URL) throws {
            if source.lastPathComponent.hasPrefix("backup-"), source.pathExtension == "f32" {
                throw NSError(domain: "ReplayRestoreFailure", code: 1)
            }
            try super.copyItem(at: source, to: destination)
        }
    }

    func testReplayRollbackFailureKeepsBackupAndSourceAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let original = try await assessment(fixture)
        _ = try fixture.repository.commit(original)
        let selected = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        let replayURLs = ScanReplayArchive.artifactURLs(for: fixture.draft.sourceURL)
        let originalPointDigest = try ScanCompanionIntegrity.digestFile(at: replayURLs.points)
        var changed = original.exportRequest.result
        changed.yieldFinalKg += 1
        let request = ScanResultExportService.ExportRequest(treeID: original.exportRequest.treeID,
            fruitType: "apple", scanDate: original.exportRequest.scanDate, gpsLat: 12.345678, gpsLon: 67.891234,
            sourceFilename: fixture.draft.sourceFilename, result: changed)
        let manager = ReplayRestoreFailureFileManager()
        let service = ScanResultExportService(fileManager: manager, scansDirectory: directory, publishFile: { from, to in
            if to.lastPathComponent.hasSuffix("_complete.json") { throw NSError(domain: "ReplayPublishFailure", code: 1) }
            if manager.fileExists(atPath: to.path) { try manager.removeItem(at: to) }
            try manager.moveItem(at: from, to: to)
        })
        XCTAssertThrowsError(try service.exportIfNeeded(request)) {
            XCTAssertTrue($0 is ScanResultExportService.RecoveryRequiredError)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.draft.sourceURL.path))
        let residues = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let recovery = try XCTUnwrap(residues.first { $0.lastPathComponent.hasSuffix(".staging") },
            "A failed rollback must retain recovery material")
        let backup = recovery.appendingPathComponent("backup-\(fixture.draft.sourceURL.deletingPathExtension().lastPathComponent)_replay.f32")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: backup), originalPointDigest)
        XCTAssertThrowsError(try ScanResultExportService(scansDirectory: directory).exportIfNeeded(request))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "Retry must not erase unresolved backups")
        let failedDeletion = fixture.repository.delete(selected, removeItem: { url in
            if url == recovery { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        XCTAssertFalse(failedDeletion.isComplete, "Permanent deletion must include recovery material")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.draft.sourceURL.path), "Keep the history anchor after incomplete deletion")
        let deletion = fixture.repository.delete(selected)
        XCTAssertTrue(deletion.isComplete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.draft.sourceURL.path))
    }

    func testLocalReplayBundlePreservesSixEvidenceCasesAndGoldenResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [Evidence] = [.reliable, .mixedCloud, .lowConfidence, .confidenceCopyFailed, .imageOnly, .cloudOnly]
        var records: [ScanFileRecord] = []
        var expected: [ScanObservationReplayRecord] = []
        var originalHashes: [URL: String] = [:]
        for evidence in cases {
            let fixture = try replayFixture(at: directory, points: makePoints(fruitColored: evidence != .reliable),
                                            observations: makeObservations(evidence))
            let committed = try fixture.repository.commit(await assessment(fixture))
            let record = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
            let replay = try fixture.repository.observationReplay(for: record)
            // Compare every encoded input field, including observations, pose,
            // configurations and producer settings, independently of the builder.
            let originalDTO = try ScanReplayInputDTO(input: fixture.input, identity: replay.identity, plan: fixture.plan)
            let restoredDTO = try ScanReplayInputDTO(input: replay.input, identity: replay.identity, plan: fixture.plan)
            XCTAssertEqual(try ScanReplayArchive.encoder().encode(originalDTO), try ScanReplayArchive.encoder().encode(restoredDTO))
            XCTAssertEqual(replay.producer.rendererSettings, fixture.plan.rendererSettings)
            let report = try await ScanObservationReplay.run(replay)
            XCTAssertTrue(report.matchesGolden, "\(evidence): \(report.differences)")
            XCTAssertEqual(report.result.nLidar, evidence == .mixedCloud ? 3 : (evidence == .reliable ? 2 : 0))
            XCTAssertEqual(report.result.yieldFinalKg,
                evidence == .mixedCloud ? 0.131231352 : (evidence == .reliable ? 0.48540313 : 0), accuracy: 0.00001)
            XCTAssertTrue(report.result.validatedFruits.allSatisfy { $0.source == "fused" })
            if evidence != .reliable && evidence != .mixedCloud { XCTAssertFalse(report.result.diagnostics.zeroYieldReasons.isEmpty) }
            records.append(record)
            expected.append(replay)
            let artifacts = ScanReplayArchive.artifactURLs(for: fixture.draft.sourceURL)
            for url in [fixture.draft.sourceURL, committed.metadataURL, committed.manifestURL, artifacts.input, artifacts.points,
                        fixture.draft.sourceURL.deletingPathExtension().appendingPathExtension("csv")] {
                originalHashes[url] = try ScanCompanionIntegrity.digestFile(at: url)
            }
            if evidence == .reliable, let token = try nativeReplayToken66("FRUIT_REPLAY_UI_CAPTURE_TOKEN") {
                let urls = [fixture.draft.sourceURL, committed.metadataURL, committed.manifestURL,
                            artifacts.input, artifacts.points,
                            fixture.draft.sourceURL.deletingPathExtension().appendingPathExtension("csv")]
                var manifest: [[String: Any]] = []
                for (index, url) in urls.enumerated() {
                    let bytes = try Data(contentsOf: url)
                    let name = "ReplayUI-\(token)-file-\(index)"
                    let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.data")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    manifest.append(["name": url.lastPathComponent, "attachment": name,
                                     "sha256": try ScanCompanionIntegrity.digestFile(at: url), "bytes": bytes.count])
                }
                let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: manifest),
                                               uniformTypeIdentifier: "public.json")
                attachment.name = "ReplayUI-\(token)-manifest"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let exported = try await BatchExportService.shared.export(records: records, format: .replay, options: .init())
        defer { BatchExportService.removeTemporaryExport(at: exported.url) }
        let bytes = try Data(contentsOf: exported.url)
        for privateValue in ["PRIVATE_FILENAME", "PRIVATE_TREE_SENTINEL", "PRIVATE_PLOT_SENTINEL", "PRIVATE_TAG_SENTINEL",
                             "2023-11-14", "12.345678", "67.891234", "gpsLat", "gpsLon", "scanClassification"] {
            XCTAssertNil(bytes.range(of: Data(privateValue.utf8)), privateValue)
        }
        let reader = try ScanReplayBundle.Reader(at: exported.url)
        XCTAssertEqual(reader.remainingRecords, cases.count)
        // Batch export preserves its frozen record order.
        for original in expected {
            let restored = try XCTUnwrap(reader.next())
            XCTAssertEqual(restored.identity, original.identity)
            XCTAssertEqual(restored.goldenData, original.goldenData)
            XCTAssertEqual(restored.exportRevision, original.exportRevision)
            XCTAssertEqual(restored.input.observations.map(\.rejectionReasons), original.input.observations.map(\.rejectionReasons))
            let report = try await ScanObservationReplay.run(restored)
            XCTAssertTrue(report.matchesGolden, "\(report.differences)")
        }
        XCTAssertNil(try reader.next())
        XCTAssertNil(try reader.next())
        for (url, digest) in originalHashes { XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: url), digest) }
        if let token = try nativeReplayToken66("FRUIT_REPLAY_UI_VERIFY_TOKEN") {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReplayUIVerification/\(token)", isDirectory: true)
            let sources = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "ply" }
            XCTAssertEqual(sources.count, 1)
            let repository = ScanRepository(scansDirectory: directory)
            let summary = try XCTUnwrap(repository.summary(at: XCTUnwrap(sources.first)))
            let original = try repository.observationReplay(for: summary)
            let reader = try ScanReplayBundle.Reader(at: directory.appendingPathComponent("export.ftsreplay"))
            XCTAssertEqual(reader.remainingRecords, 1)
            let restored = try XCTUnwrap(reader.next())
            XCTAssertEqual(restored.identity, original.identity)
            XCTAssertEqual(restored.goldenData, original.goldenData)
            XCTAssertEqual(restored.exportRevision, original.exportRevision)
            let report = try await ScanObservationReplay.run(restored)
            XCTAssertTrue(report.matchesGolden, "Native export: \(report.differences)")
            XCTAssertEqual(report.result.nLidar, 2)
            XCTAssertEqual(report.result.diagnostics.fusedFruitCount, 1)
            XCTAssertEqual(report.result.validatedFruits.count, 1)
            XCTAssertEqual(report.result.yieldFinalKg, 0.48540313, accuracy: 0.00001)
            XCTAssertTrue(report.result.validatedFruits.allSatisfy { $0.source == "fused" })
            XCTAssertNil(try reader.next())
            let attachment = XCTAttachment(string: "Native export matches original identity/revision/golden; correctedCount=2; fusedEvidence=1; 0.48540313 kg")
            attachment.name = "NativeReplay66-GoldenVerified-\(token)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func nativeReplayToken66(_ key: String) throws -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment[key] else { return nil }
        guard UUID(uuidString: token) != nil,
              environment["FRUIT_NATIVE_UI_SIMULATOR_ID"] == environment["SIMULATOR_UDID"],
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "NativeReplayFixture66", code: 1)
        }
        return token
    }

    func testReplayBundleCollisionCancellationAndCorruptionPreserveOriginalFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        _ = try fixture.repository.commit(await assessment(fixture))
        let record = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        let destination = directory.appendingPathComponent("replay.ftsreplay")
        try ScanReplayBundle.write(records: [record], repository: fixture.repository, to: destination)
        let original = try Data(contentsOf: destination)
        XCTAssertThrowsError(try ScanReplayBundle.write(records: [record], repository: fixture.repository, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        let cancelledDestination = directory.appendingPathComponent("cancelled.ftsreplay")
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try ScanReplayBundle.write(records: [record], repository: fixture.repository, to: cancelledDestination)
        }
        do { try await worker.value; XCTFail("Cancelled export must fail") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledDestination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".replay-") })
        for corrupt in [Data(original.dropLast()), original.prefix(16), Data("INVALID!".utf8) + original.dropFirst(8)] {
            let url = directory.appendingPathComponent("corrupt.ftsreplay")
            try corrupt.write(to: url)
            do {
                let reader = try ScanReplayBundle.Reader(at: url)
                XCTAssertThrowsError(try reader.next())
                XCTAssertThrowsError(try reader.next())
            } catch { /* Invalid container header is rejected by init. */ }
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertNotNil(try fixture.repository.readVerifiedRecord(at: fixture.draft.sourceURL))
    }

    func testRecoveryDirectoryMatchingDoesNotClaimDottedSiblingSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let original = try await assessment(fixture)
        _ = try fixture.repository.commit(original)
        let base = fixture.draft.sourceURL.deletingPathExtension().lastPathComponent
        let sibling = directory.appendingPathComponent(".\(base).b.v1-\(String(repeating: "a", count: 16)).staging", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let backup = sibling.appendingPathComponent("backup-sibling")
        try Data("unrelated recovery".utf8).write(to: backup)
        var changed = original.exportRequest.result
        changed.yieldFinalKg += 1
        let request = ScanResultExportService.ExportRequest(treeID: original.exportRequest.treeID,
            fruitType: "apple", scanDate: original.exportRequest.scanDate, gpsLat: 12.345678, gpsLon: 67.891234,
            sourceFilename: fixture.draft.sourceFilename, result: changed)
        _ = try ScanResultExportService(scansDirectory: directory).exportIfNeeded(request)
        let selected = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        XCTAssertTrue(fixture.repository.delete(selected).isComplete)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "unrelated recovery")
    }

    func testReplayArchiveRoundTripsNondefaultAndOptionalInputFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var cluster = ClusterConfig.default
        cluster.minPoints = 7
        cluster.baseEps = 0.1234567
        var experiment = FruitScanExperimentConfig.default
        experiment.fusion.nearestCandidateDistance = 0.17
        experiment.pointCloud.denoisingNeighborCount = 7
        experiment.depth.projectionSampleGrid = 7
        experiment.occlusion.lidarPenetrationMeters = 0.31
        experiment.candidateMerge.maxPointSamples = 123
        let correction = YieldCalibrationCorrection(countFactor: 1.2, yieldFactor: 0.9, countSampleCount: 5, yieldSampleCount: 6)
        let fixture = try replayFixture(at: directory, cluster: cluster, experiment: experiment, calibration: correction)
        var params = fixture.input.defaultParams
        params.density = 0.8765432
        params.isCustomized = true
        var filter = ColorFilter(rMin: 0.1234567, gMin: 0.2345678, bMax: 0.7654321,
                                 labFilter: .init(lMin: 12, lMax: 88, aMin: -31, aMax: 72, bMin: -17, bMax: 63))
        filter.hsvFilter = .init(hMin: 350, hMax: 21, sMin: 0.24, vMin: 0.13)
        var fusion = FruitScanConfig.default
        fusion.minConfidence = 0.67
        fusion.minimumStableDetectionsForYield = 3
        fusion.stableDetectionTimeWindow = 2.123456789
        var diagnostics = ImageDetectionDiagnostics()
        diagnostics.modelStatus = "CoreML"
        diagnostics.modelName = "synthetic-nondefault-model"
        diagnostics.processedFrameCount = 7
        let incomplete = Observation(id: fixedID(50), frameID: .init(rawValue: fixedID(51)), category: .pear,
            boundingBox: CGRect(x: 0.123456789, y: 0.234567891, width: 0.345678912, height: 0.456789123),
            confidence: 0.8765432, timestamp: 12.123456789, cameraTransform: nil, cameraIntrinsics: nil, imageSize: nil,
            coordinateConvention: .visionNormalizedLowerLeft, depthConfidenceProvenance: .unavailable,
            hasDepthMap: false, roiDepthSamples: [], projectionDepthSamples: [], rejectionReasons: [.missingDepthMap])
        let verification = FruitCategoryVerificationSummary(selectedCategory: .apple, detectedCategoryCounts: ["pear": 3],
            nonTargetDetectionCount: 3, dominantNonTargetCategory: .pear, categoryMismatchDetected: true,
            automaticSuggestion: .init(category: .pear, confidence: 0.87, supportingFrameCount: 3, competingCategory: .apple))
        let input = ScanFusionYieldBuilder.Input(points: fixture.input.points,
            observations: fixture.input.observations + [incomplete], imageDiagnostics: diagnostics,
            fruitType: "apple", fruitCategory: .apple, paramsSnapshot: ["apple": params, "pear": .init(category: .pear)],
            defaultParams: params, clusterConfig: cluster, fusionConfig: fusion, colorFilter: filter, season: .off,
            calibrationCorrection: correction, categoryVerification: verification,
            finalPointCloudIdentity: fixture.input.finalPointCloudIdentity, experimentConfiguration: experiment,
            calibrationIdentity: .init(algorithmRevision: "fixture-calibration-v3", context: "fixture-context"))
        let plan = ScanPlan(id: fixture.plan.id, treeID: "PRIVATE_TREE_SENTINEL", season: .off,
            fruitConfiguration: fixture.plan.fruitConfiguration, rendererSettings: fixture.plan.rendererSettings,
            resourceBudget: .init(liveSnapshotSampleLimit: 12_345, analysisInputSampleLimit: 12_000, retainedDetectionFrameLimit: 123),
            requestedCameraResolution: "4K", requestedCameraFrameRate: "30fps", autoExportCSV: false,
            modelIdentity: .verified(String(repeating: "b", count: 64)), experimentConfiguration: experiment)
        let original = try ScanReplayInputDTO(input: input, identity: fixture.identity, plan: plan)
        let prepared = try ScanReplayArchive.prepare(input: input, identity: fixture.identity, plan: plan, draft: fixture.draft)
        let pending = try XCTUnwrap(prepared.directory)
        let (decoded, restored) = try ScanReplayArchive.read(inputURL: pending.appendingPathComponent("input.json"),
            pointsURL: pending.appendingPathComponent("points.f32"), descriptor: prepared.descriptor)
        XCTAssertEqual(try ScanReplayArchive.encoder().encode(decoded), try ScanReplayArchive.encoder().encode(original))
        XCTAssertEqual(try ScanReplayArchive.encoder().encode(ScanReplayInputDTO(input: restored, identity: fixture.identity, plan: plan)),
                       try ScanReplayArchive.encoder().encode(original))
        XCTAssertEqual(decoded.producer.modelState, "verified")
        XCTAssertEqual(decoded.producer.modelFingerprint, String(repeating: "b", count: 64))
        XCTAssertEqual(decoded.producer.analysisInputSampleLimit, 12_000)
        XCTAssertEqual(restored.categoryVerification, verification)
        XCTAssertNil(restored.observations.last?.cameraTransform)
        XCTAssertEqual(restored.observations.last?.timestamp.bitPattern, incomplete.timestamp.bitPattern)
    }

    func testReplayArchiveRejectsRehashedSchemaIdentityAndBudgetMutations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let prepared = try ScanReplayArchive.prepare(input: fixture.input, identity: fixture.identity, plan: fixture.plan, draft: fixture.draft)
        let pending = try XCTUnwrap(prepared.directory)
        let inputURL = pending.appendingPathComponent("input.json")
        let pointsURL = pending.appendingPathComponent("points.f32")
        let original = try json(at: inputURL)
        let mutations: [([String: Any]) throws -> [String: Any]] = [
            { var v = $0; v["schemaVersion"] = 99; return v },
            { var v = $0; v.removeValue(forKey: "experimentConfiguration"); return v },
            { var v = $0; v["pointCount"] = 1; return v },
            { var v = $0; var id = try XCTUnwrap(v["identity"] as? [String: Any]); id["sourceSHA256"] = String(repeating: "0", count: 64); v["identity"] = id; return v },
            { var v = $0; var p = try XCTUnwrap(v["producer"] as? [String: Any]); p["inputContractRevision"] = "unknown-v99"; v["producer"] = p; return v },
            { var v = $0; var p = try XCTUnwrap(v["producer"] as? [String: Any]); p["analysisInputSampleLimit"] = 120_001; v["producer"] = p; return v },
            { var v = $0; var p = try XCTUnwrap(v["producer"] as? [String: Any]); p["modelState"] = "verified"; v["producer"] = p; return v },
            { var v = $0; var rows = try XCTUnwrap(v["observations"] as? [[String: Any]]); rows[0]["cameraTransform"] = Array(repeating: 0, count: 17); v["observations"] = rows; return v },
        ]
        for (index, mutate) in mutations.enumerated() {
            let bytes = try JSONSerialization.data(withJSONObject: mutate(original), options: [.sortedKeys])
            try bytes.write(to: inputURL)
            let descriptor = ScanReplayDescriptor(status: "complete", reason: nil, identity: prepared.descriptor.identity,
                inputByteCount: bytes.count, inputSHA256: ScanCompanionIntegrity.digest(bytes), pointCount: prepared.descriptor.pointCount,
                pointsByteCount: prepared.descriptor.pointsByteCount, pointsSHA256: prepared.descriptor.pointsSHA256,
                observationCount: prepared.descriptor.observationCount)
            XCTAssertThrowsError(try ScanReplayArchive.read(inputURL: inputURL, pointsURL: pointsURL, descriptor: descriptor), "mutation \(index)")
        }
    }

    func testReplayBuildIdentityMismatchRejectsExecution() async throws {
        let original = try archivedReplay()
        var producer = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.producer)) as? [String: Any])
        producer["sourcesSHA256"] = String(repeating: "0", count: 64)
        let altered = try JSONDecoder().decode(ReplayProducerDTO.self, from: JSONSerialization.data(withJSONObject: producer))
        let record = ScanObservationReplayRecord(identity: original.identity, producer: altered, input: original.input,
            goldenData: original.goldenData, exportRevision: original.exportRevision)
        do { _ = try await ScanObservationReplay.run(record); XCTFail("Different production sources cannot claim an exact golden replay") }
        catch ScanReplayError.algorithmMismatch { }
    }

    func testReplayPreparationFailureAndPublicationRetryKeepTheFrozenInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let pending = ScanReplayArchive.preparedDirectory(for: fixture.draft)
        try Data("obstacle".utf8).write(to: pending)
        let snapshot = ScanYieldEstimationController.Snapshot(context: fixture.identity.capture.context, input: fixture.input)
        do {
            _ = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: fixture.draft, repository: fixture.repository, plan: fixture.plan)
            XCTFail("Preparation IO failure must fail before binding the evidence")
        } catch ScanReplayError.invalidArchive { }
        try FileManager.default.removeItem(at: pending)
        let frozen = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: fixture.draft,
                                                          repository: fixture.repository, plan: fixture.plan)
        XCTAssertEqual(frozen.identity.snapshotID, snapshot.id)
        let estimate = try await ScanYieldEstimationController.estimate(frozen)
        let assessment = ScanAssessment(receipt: frozen.receipt, estimate: estimate, treeID: "PRIVATE_TREE_SENTINEL",
            fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1_700_000_000), gpsLat: 12.345678, gpsLon: 67.891234,
            includeCSV: true, classification: fixture.plan.classification)
        let failed = ScanResultExportService(scansDirectory: directory, publishFile: { from, to in
            if to.lastPathComponent.hasSuffix("_complete.json") { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.moveItem(at: from, to: to)
        })
        XCTAssertThrowsError(try fixture.repository.commit(assessment, using: failed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: fixture.draft.sourceURL), fixture.draft.sourceSHA256)
        XCTAssertNotEqual(try fixture.repository.summary(at: fixture.draft.sourceURL)?.persistenceState, .complete)
        let committed = try fixture.repository.commit(assessment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        let retry = try fixture.repository.commit(assessment)
        XCTAssertEqual(retry.exportRevision, committed.exportRevision)
        let selected = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        let report = try await ScanObservationReplay.run(fixture.repository.observationReplay(for: selected))
        XCTAssertTrue(report.matchesGolden, "\(report.differences)")
        XCTAssertEqual(fixture.repository.settleCancelledDraft(fixture.draft), .preservedCommitted)
        let orphan = directory.appendingPathComponent(".\(fixture.draft.sourceURL.deletingPathExtension().lastPathComponent).replay-\(UUID()).pending")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
        try Data("orphan".utf8).write(to: orphan.appendingPathComponent("input.json"))
        XCTAssertTrue(fixture.repository.delete(selected).isComplete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testReplayReplacementFailureRestoresEveryOriginalArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let assessment = try await assessment(fixture)
        let committed = try fixture.repository.commit(assessment)
        let selected = try XCTUnwrap(fixture.repository.summary(at: fixture.draft.sourceURL))
        let replayURLs = ScanReplayArchive.artifactURLs(for: fixture.draft.sourceURL)
        var hashes: [URL: String] = [:]
        for url in [fixture.draft.sourceURL, committed.metadataURL, committed.manifestURL, replayURLs.input, replayURLs.points,
                    fixture.draft.sourceURL.deletingPathExtension().appendingPathExtension("csv")] {
            hashes[url] = try ScanCompanionIntegrity.digestFile(at: url)
        }
        var changed = assessment.exportRequest.result
        changed.yieldFinalKg += 1
        let request = ScanResultExportService.ExportRequest(treeID: assessment.exportRequest.treeID, fruitType: "apple",
            scanDate: assessment.exportRequest.scanDate, gpsLat: 12.345678, gpsLon: 67.891234,
            sourceFilename: fixture.draft.sourceFilename, result: changed)
        let failed = ScanResultExportService(scansDirectory: directory, publishFile: { from, to in
            if to.lastPathComponent.hasSuffix("_complete.json") { throw CocoaError(.fileWriteUnknown) }
            if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
            try FileManager.default.moveItem(at: from, to: to)
        })
        XCTAssertThrowsError(try failed.exportIfNeeded(request))
        for (url, digest) in hashes { XCTAssertEqual(try ScanCompanionIntegrity.digestFile(at: url), digest) }
        XCTAssertTrue(try ScanResultExportService.stagingDirectories(for: fixture.draft.sourceURL).isEmpty)
        let report = try await ScanObservationReplay.run(fixture.repository.observationReplay(for: selected))
        XCTAssertTrue(report.matchesGolden, "\(report.differences)")
    }

    func testReplayCancellationCleansOwnedPreparationAndBudgetDoesNotTruncate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try replayFixture(at: directory)
        let snapshot = ScanYieldEstimationController.Snapshot(context: fixture.identity.capture.context, input: fixture.input)
        _ = try await ScanEvidenceSnapshot.freeze(snapshot: snapshot, draft: fixture.draft, repository: fixture.repository, plan: fixture.plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScanReplayArchive.preparedDirectory(for: fixture.draft).path))
        XCTAssertEqual(fixture.repository.settleCancelledDraft(fixture.draft), .discarded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.draft.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScanReplayArchive.preparedDirectory(for: fixture.draft).path))
        let observations = Array(repeating: try XCTUnwrap(makeObservations(.imageOnly).first), count: ScanReplayLimits.maximumObservations + 1)
        let oversized = try replayFixture(at: directory, observations: observations)
        let prepared = try ScanReplayArchive.prepare(input: oversized.input, identity: oversized.identity, plan: oversized.plan, draft: oversized.draft)
        XCTAssertEqual(prepared.descriptor.status, "unavailable")
        XCTAssertEqual(prepared.descriptor.reason, "inputExceedsReplayBudget")
        XCTAssertNil(prepared.directory)
        XCTAssertEqual(oversized.input.observations.count, ScanReplayLimits.maximumObservations + 1)
        XCTAssertEqual(oversized.repository.settleCancelledDraft(oversized.draft), .discarded)
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
