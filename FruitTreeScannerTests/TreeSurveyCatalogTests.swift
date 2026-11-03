import XCTest
@testable import FruitTreeScanner

@MainActor
final class TreeSurveyCatalogTests: XCTestCase {
    func testImportsTrunkPointWithoutConfusingLongitudeAndLatitude() throws {
        let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture()).first)
        XCTAssertEqual(point.treeID, "A-001")
        XCTAssertEqual(point.longitude, 121.4737)
        XCTAssertEqual(point.latitude, 31.2304)
        XCTAssertEqual(point.horizontalAccuracyMeters, 0.03)
        XCTAssertTrue(point.meetsReportedTarget)
        XCTAssertEqual(point.sourceNote, "QA fixture")
    }

    func testSmallReportedRadiusDoesNotUpgradeOrdinaryGPSOrFloatRTK() throws {
        for method in ["device_gps", "rtk_float"] {
            let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture(method: method)).first)
            XCTAssertFalse(point.meetsReportedTarget)
        }
        XCTAssertFalse(try XCTUnwrap(TreeSurveyCodec.decode(fixture(accuracy: 1.01)).first).meetsReportedTarget)
        XCTAssertTrue(try XCTUnwrap(TreeSurveyCodec.decode(fixture(accuracy: 1.0)).first).meetsReportedTarget)
    }

    func testRejectsInvalidCoordinatesUncertaintyReferenceAndMissingProvenance() {
        for replacement in [
            ("[121.4737,31.2304]", "[181,31]"),
            ("[121.4737,31.2304]", "[121,91]"),
            ("\"horizontal_accuracy_m\":0.03", "\"horizontal_accuracy_m\":0"),
            ("\"horizontal_accuracy_m\":0.03", "\"horizontal_accuracy_m\":-1"),
            ("trunk_base", "phone"), ("rtk_fixed", "unknown"),
            ("QA fixture", ""), ("2026-01-01T00:00:00Z", "invalid"),
            ("A-001", "../a")
        ] {
            let text = String(decoding: fixture(), as: UTF8.self)
                .replacingOccurrences(of: replacement.0, with: replacement.1)
            XCTAssertThrowsError(try TreeSurveyCodec.decode(Data(text.utf8)), "\(replacement)")
        }
    }

    func testRejectsMixedGeometryAndDuplicateNormalizedTreeIDsAsWholeBatch() throws {
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        let feature = try XCTUnwrap((document["features"] as? [[String: Any]])?.first)
        var duplicate = feature
        var properties = try XCTUnwrap(feature["properties"] as? [String: Any])
        properties["tree_id"] = " A-001 "
        duplicate["properties"] = properties
        document["features"] = [feature, duplicate]
        XCTAssertThrowsError(try TreeSurveyCodec.decode(JSONSerialization.data(withJSONObject: document)))
        document["features"] = [feature]
        document["crs"] = ["type": "name", "properties": ["name": "EPSG:3857"]]
        XCTAssertThrowsError(try TreeSurveyCodec.decode(JSONSerialization.data(withJSONObject: document)))
        let polygon = String(decoding: fixture(), as: UTF8.self).replacingOccurrences(of: "\"Point\"", with: "\"Polygon\"")
        XCTAssertThrowsError(try TreeSurveyCodec.decode(Data(polygon.utf8)))
    }

    func testBoundsFileSizeAndPointCount() throws {
        XCTAssertThrowsError(try TreeSurveyCodec.decode(Data(repeating: 32, count: TreeSurveyCodec.maximumFileBytes + 1)))
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        let feature = try XCTUnwrap((doc["features"] as? [[String: Any]])?.first)
        doc["features"] = Array(repeating: feature, count: TreeSurveyCodec.maximumPointCount + 1)
        XCTAssertThrowsError(try TreeSurveyCodec.decode(JSONSerialization.data(withJSONObject: doc)))
    }

    func testRoundTripRetainsSourceDatePrecisionAndTreeIdentity() throws {
        let original = try TreeSurveyCodec.decode(fixture())
        XCTAssertEqual(try TreeSurveyCodec.decode(TreeSurveyCodec.encode(original)), original)
    }

    func testExistingTreeRequiresExplicitUpdateAndSurvivesReload() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TreeSurveyCatalog(fileURL: url)
        try store.commit(try TreeSurveyCodec.decode(fixture()), replacingExisting: false)
        let changed = try TreeSurveyCodec.decode(fixture(accuracy: 0.2))
        XCTAssertThrowsError(try store.commit(changed, replacingExisting: false))
        XCTAssertEqual(store.points.first?.horizontalAccuracyMeters, 0.03)
        try store.commit(changed, replacingExisting: true)
        XCTAssertEqual(TreeSurveyCatalog(fileURL: url).points, changed)
    }

    func testFailedWriteDoesNotPublishUnpersistedPositions() throws {
        let store = TreeSurveyCatalog(fileURL: temporaryURL(), write: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertThrowsError(try store.commit(TreeSurveyCodec.decode(fixture()), replacingExisting: false))
        XCTAssertTrue(store.points.isEmpty)
    }

    func testCorruptExistingFileIsPreservedAndBlocksWrites() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        let store = TreeSurveyCatalog(fileURL: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.commit(TreeSurveyCodec.decode(fixture()), replacingExisting: true))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testRecoveryRequiresConfirmationAndRetainsExactOriginalBeforePublishing() throws {
        let url = try corruptFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let store = TreeSurveyCatalog(fileURL: url)
        let snapshot = try store.prepareRecovery()
        let points = try TreeSurveyCodec.decode(fixture())
        XCTAssertThrowsError(try store.recover(points, from: snapshot, confirmed: false))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).count, 1)
        XCTAssertThrowsError(try store.commit(points, replacingExisting: true))
        let backup = try store.recover(points, from: snapshot, confirmed: true)
        XCTAssertNotEqual(backup, url)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.points, points)
        XCTAssertEqual(TreeSurveyCatalog(fileURL: url).points, points)
        XCTAssertThrowsError(try store.recover(points, from: snapshot, confirmed: true))
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testRecoveryRejectsForeignPreviewAndChangedRepairedOrMissingOriginal() throws {
        let url = try corruptFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TreeSurveyCatalog(fileURL: url)
        let snapshot = try store.prepareRecovery()
        let points = try TreeSurveyCodec.decode(fixture())
        XCTAssertThrowsError(try TreeSurveyCatalog(fileURL: url).recover(points, from: snapshot, confirmed: true))
        for changed in [Data("another corrupt file".utf8), fixture()] {
            try changed.write(to: url, options: .atomic)
            XCTAssertThrowsError(try store.recover(points, from: snapshot, confirmed: true))
            XCTAssertEqual(try Data(contentsOf: url), changed)
            XCTAssertNotNil(store.loadError)
            XCTAssertTrue(store.points.isEmpty)
        }
        XCTAssertThrowsError(try store.prepareRecovery(), "修好的原档不能再作为损坏原档恢复")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try store.recover(points, from: snapshot, confirmed: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).isEmpty)
    }

    func testRecoveryBackupFailureOrMismatchedCopyCannotReplaceOriginal() throws {
        for mismatch in [false, true] {
            let url = try corruptFile()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let original = try Data(contentsOf: url)
            var writes = 0
            let store = TreeSurveyCatalog(fileURL: url, write: { _, _ in writes += 1 }, copyBackup: { _, backup in
                if mismatch { try Data("wrong copy".utf8).write(to: backup) }
                else { throw CocoaError(.fileWriteOutOfSpace) }
            })
            XCTAssertThrowsError(try store.recover(TreeSurveyCodec.decode(fixture()), from: store.prepareRecovery(), confirmed: true))
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNotNil(store.loadError)
            XCTAssertTrue(store.points.isEmpty)
        }
    }

    func testRecoveryAtomicWriteFailureRetainsOriginalAndVerifiedBackup() throws {
        let url = try corruptFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let store = TreeSurveyCatalog(fileURL: url, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try store.recover(TreeSurveyCodec.decode(fixture()), from: store.prepareRecovery(), confirmed: true))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.points.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0 != url }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testRecoveryRechecksActiveOriginalAfterCreatingBackup() throws {
        let url = try corruptFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let changed = Data("changed during backup".utf8)
        var writes = 0
        let store = TreeSurveyCatalog(fileURL: url, write: { _, _ in writes += 1 }, copyBackup: { source, backup in
            try FileManager.default.copyItem(at: source, to: backup)
            try changed.write(to: source, options: .atomic)
        })
        XCTAssertThrowsError(try store.recover(TreeSurveyCodec.decode(fixture()), from: store.prepareRecovery(), confirmed: true))
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(try Data(contentsOf: url), changed)
        XCTAssertNotNil(store.loadError)
        let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0 != url }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testRecoveryRejectsOversizedOriginalAndInvalidOrOversizedInputBeforeBackup() throws {
        let url = try corruptFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TreeSurveyCatalog(fileURL: url)
        let original = try Data(contentsOf: url)
        let snapshot = try store.prepareRecovery()
        let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture()).first)
        let invalid = TreeSurveyPoint(treeID: "../bad", longitude: 121, latitude: 31,
            horizontalAccuracyMeters: 0.1, method: .totalStation, measuredAt: point.measuredAt, sourceNote: "invalid ID")
        let oversized = (0..<5000).map { i in
            TreeSurveyPoint(treeID: "TREE-\(i)", longitude: 121, latitude: 31,
                horizontalAccuracyMeters: 0.1, method: .totalStation,
                measuredAt: point.measuredAt, sourceNote: String(repeating: "测", count: 160))
        }
        for input in [[], [invalid], Array(repeating: point, count: 5001), oversized] {
            XCTAssertThrowsError(try store.recover(input, from: snapshot, confirmed: true))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).count, 1)
        let oversizedOriginal = Data(repeating: 32, count: TreeSurveyCodec.maximumFileBytes + 1)
        try oversizedOriginal.write(to: url)
        XCTAssertThrowsError(try store.prepareRecovery())
        XCTAssertThrowsError(try store.recover([point], from: snapshot, confirmed: true))
        XCTAssertEqual(try Data(contentsOf: url), oversizedOriginal)
    }

    func testSurveyCoordinateOverridesPhonePositionWithoutChangingYieldOrSourceRecord() throws {
        let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture()).first)
        let record = ScanFileRecord(id: "scan", treeID: point.treeID, fileURL: URL(fileURLWithPath: "/scan.ply"),
                                    scanDate: Date(), fruitCount: 17, yieldKg: 8, gpsLat: 30, gpsLon: 120)
        let tree = try XCTUnwrap(OrchardMapData(records: [record], surveyPoints: [point]).trees.first)
        XCTAssertEqual(tree.coordinate.latitude, point.latitude)
        XCTAssertEqual(tree.coordinate.longitude, point.longitude)
        XCTAssertEqual(tree.weight, 8)
        XCTAssertEqual(tree.fruitCount, 17)
        XCTAssertEqual(record.gpsLat, 30)
        XCTAssertEqual(tree.surveyPoint, point)
    }

    func testMeasuredTreeCanBeLocatedWithoutPhoneGPSButIncompleteScanStaysExcluded() throws {
        let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture()).first)
        let record = ScanFileRecord(id: "scan", treeID: point.treeID, fileURL: URL(fileURLWithPath: "/scan.ply"), scanDate: Date())
        let data = OrchardMapData(records: [record], surveyPoints: [point])
        XCTAssertEqual(data.trees.count, 1)
        XCTAssertEqual(data.unlocatedRecordCount, 0)
        let incomplete = ScanFileRecord(id: "failed", treeID: point.treeID, fileURL: record.fileURL,
                                       scanDate: Date(), persistenceState: .incomplete)
        XCTAssertTrue(OrchardMapData(records: [incomplete], surveyPoints: [point]).trees.isEmpty)
    }

    func testUnmatchedSurveyPointDoesNotAttachToNearestTree() throws {
        let point = try XCTUnwrap(TreeSurveyCodec.decode(fixture()).first)
        let record = ScanFileRecord(id: "other", treeID: "B-002", fileURL: URL(fileURLWithPath: "/scan.ply"),
                                    scanDate: Date(), gpsLat: point.latitude, gpsLon: point.longitude)
        let tree = try XCTUnwrap(OrchardMapData(records: [record], surveyPoints: [point]).trees.first)
        XCTAssertNil(tree.surveyPoint)
        XCTAssertTrue(tree.positionDescription.contains("参考"))
    }

    func testMaximumCatalogConflictCountAndOverLimitMergePreserveOriginal() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let feature = try XCTUnwrap((JSONSerialization.jsonObject(with: fixture()) as? [String: Any])?["features"] as? [[String: Any]]).first!
        let features = (0..<TreeSurveyCodec.maximumPointCount).map { i -> [String: Any] in
            var copy = feature
            var properties = copy["properties"] as! [String: Any]
            properties["tree_id"] = "TREE-\(i)"
            copy["properties"] = properties
            return copy
        }
        let data = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
        let points = try TreeSurveyCodec.decode(data)
        let store = TreeSurveyCatalog(fileURL: url)
        try store.commit(points, replacingExisting: false)
        XCTAssertEqual(store.conflictCount(for: points), 5000)
        let persisted = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.commit(TreeSurveyCodec.decode(fixture()), replacingExisting: false))
        XCTAssertEqual(store.points.count, 5000)
        XCTAssertEqual(try Data(contentsOf: url), persisted)
    }

    func testFailedUpdateKeepsExistingMemoryAndFileBytes() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var writes = 0
        let store = TreeSurveyCatalog(fileURL: url, write: { data, destination in
            writes += 1
            if writes > 1 { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        })
        try store.commit(TreeSurveyCodec.decode(fixture()), replacingExisting: false)
        let persisted = try Data(contentsOf: url)
        let points = store.points
        XCTAssertThrowsError(try store.commit(TreeSurveyCodec.decode(fixture(accuracy: 0.9)), replacingExisting: true))
        XCTAssertEqual(store.points, points)
        XCTAssertEqual(try Data(contentsOf: url), persisted)
    }

    func testMergedFileSizeLimitRollsBackEvenWhenPointCountFits() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        func batch(_ prefix: String) -> [TreeSurveyPoint] {
            (0..<2500).map { i in
                TreeSurveyPoint(treeID: "\(prefix)-\(i)", longitude: 121, latitude: 31,
                    horizontalAccuracyMeters: 0.1, method: .totalStation,
                    measuredAt: "2026-01-01T00:00:00Z", sourceNote: String(repeating: "测", count: 160))
            }
        }
        let store = TreeSurveyCatalog(fileURL: url)
        try store.commit(batch("A"), replacingExisting: false)
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.commit(batch("B"), replacingExisting: false))
        XCTAssertEqual(store.points.count, 2500)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// 回归：导出准备失败时不能产出空文件。
    /// 修复前编码失败会被 `try?` 吞掉，导出器照样「成功」写出一个 0 字节 geojson。
    func testExportPreparationFailsInsteadOfProducingAnEmptyDocument() throws {
        let valid = TreeSurveyPoint(treeID: "A-001", longitude: 121.4737, latitude: 31.2304,
                                    horizontalAccuracyMeters: 0.03, method: .rtkFixed,
                                    measuredAt: "2026-01-01T00:00:00Z", sourceNote: "QA fixture")
        switch TreeSurveyExportPreparation.payload(for: [valid]) {
        case .success(let data):
            XCTAssertFalse(data.isEmpty)
        case .failure(let error):
            XCTFail("valid catalog should encode: \(error)")
        }

        let unencodable = TreeSurveyPoint(treeID: "A-002", longitude: .nan, latitude: 31.2304,
                                           horizontalAccuracyMeters: 0.03, method: .rtkFixed,
                                           measuredAt: "2026-01-01T00:00:00Z", sourceNote: "QA fixture")
        switch TreeSurveyExportPreparation.payload(for: [unencodable]) {
        case .success(let data):
            XCTFail("unencodable catalog must not yield a document (got \(data.count) bytes)")
        case .failure:
            break
        }
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("trees.geojson")
    }

    private func corruptFile() throws -> URL {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken tree survey".utf8).write(to: url)
        return url
    }

    private func fixture(method: String = "rtk_fixed", accuracy: Double = 0.03) -> Data {
        Data("""
        {"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[121.4737,31.2304]},"properties":{"tree_id":"A-001","position_source":"\(method)","horizontal_accuracy_m":\(accuracy),"measured_at":"2026-01-01T00:00:00Z","reference":"trunk_base","source_note":"QA fixture"}}]}
        """.utf8)
    }
}
