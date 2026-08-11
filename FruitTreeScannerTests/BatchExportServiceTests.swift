import XCTest
@testable import FruitTreeScanner

final class BatchExportServiceTests: XCTestCase {

    private func makeRecord(
        id: String = "scan_001.ply",
        treeID: String = "T-001",
        scanDate: Date = Date(timeIntervalSince1970: 1717200000),
        fruitCount: Int = 10,
        yieldKg: Float = 5.5,
        gpsLat: Double = 36.123456,
        gpsLon: Double = 139.654321,
        fruitType: String = "apple",
        fileURL: URL? = nil,
        persistenceState: ScanPersistenceState = .complete
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: fileURL ?? URL(fileURLWithPath: "/tmp/\(id)"),
            scanDate: scanDate,
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            fruitType: fruitType,
            persistenceState: persistenceState
        )
    }

    private func exportCSVContent(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions = .init()
    ) async throws -> String {
        let result = try await BatchExportService.shared.export(
            records: records,
            format: .csv,
            options: options
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        return try String(contentsOf: result.url, encoding: .utf8)
    }

    private func exportJSONPayload(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions = .init()
    ) async throws -> [String: Any] {
        let result = try await BatchExportService.shared.export(
            records: records,
            format: .json,
            options: options
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        let data = try Data(contentsOf: result.url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func exportExcelContent(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions = .init()
    ) async throws -> String {
        let result = try await BatchExportService.shared.export(
            records: records,
            format: .excel,
            options: options
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        return try String(contentsOf: result.url, encoding: .utf8)
    }

    private func makeYieldResult(
        nLidar: Int = 12,
        yieldKg: Float = 3.45
    ) -> YieldResult {
        var result = YieldResult()
        result.nLidar = nLidar
        result.yieldFinalKg = yieldKg
        result.clusterEps = 0.05
        result.clusterMinPoints = 6
        result.colorFilterDesc = "@color"
        result.occlusionK = 1.2
        result.pointCloudSize = 1234
        result.confidence = "-low"
        result.methodUsed = "\tmethod"
        result.note = "\nmanual review"
        return result
    }

    private func makeMassEstimate(
        id: UUID = UUID(),
        fruitCategory: String = "apple",
        lengthCm: Float = 8,
        widthCm: Float = 8,
        heightCm: Float = 8,
        equivalentDiameterCm: Float = 8,
        sphereVolumeCm3: Float = 268.08,
        ellipsoidVolumeCm3: Float = 268.08,
        selectedVolumeCm3: Float = 268.08,
        densityGPerCm3: Float = 0.85,
        estimatedWeightG: Float = 227.87,
        confidenceScore: Float = 0.8,
        pointCount: Int = 24,
        highConfidenceRatio: Float = 0.9,
        validDepthRatio: Float = 0.85,
        shapeModelUsed: FruitShapeModelUsed = .sphere,
        warningFlags: [FruitMassEstimateWarningFlag] = [.usingSphereBaseline],
        createdAt: Date = Date(timeIntervalSince1970: 1717200000)
    ) -> FruitMassEstimate {
        FruitMassEstimate(
            id: id,
            fruitCategory: fruitCategory,
            lengthCm: lengthCm,
            widthCm: widthCm,
            heightCm: heightCm,
            equivalentDiameterCm: equivalentDiameterCm,
            sphereVolumeCm3: sphereVolumeCm3,
            ellipsoidVolumeCm3: ellipsoidVolumeCm3,
            selectedVolumeCm3: selectedVolumeCm3,
            densityGPerCm3: densityGPerCm3,
            estimatedWeightG: estimatedWeightG,
            confidenceScore: confidenceScore,
            pointCount: pointCount,
            highConfidenceRatio: highConfidenceRatio,
            validDepthRatio: validDepthRatio,
            shapeModelUsed: shapeModelUsed,
            warningFlags: warningFlags,
            createdAt: createdAt
        )
    }

    // MARK: - Helpers for CSV content inspection

    private func stripBOM(_ csv: String) -> String {
        csv.replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private func recordRows(from csv: String) -> [String] {
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let dataLines = Array(lines.dropFirst())
        var result: [String] = []
        for line in dataLines {
            if line == "汇总" || line.hasPrefix("总计") { break }
            result.append(line)
        }
        return result
    }

    private func writeMockSingleScanMetadata(
        for plyURL: URL,
        payload: [String: Any]
    ) throws {
        let baseName = (plyURL.lastPathComponent as NSString).deletingPathExtension
        let metadataURL = plyURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - (1) Empty records throws BatchExportError.noRecords

    func testEmptyRecordsThrowsNoRecords() async {
        do {
            _ = try await BatchExportService.shared.export(
                records: [],
                format: .csv,
                options: .init()
            )
            XCTFail("Expected BatchExportError.noRecords to be thrown")
        } catch let error as BatchExportError {
            XCTAssertEqual(error, .noRecords)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExportCancellationPropagatesToBackgroundTask() async {
        let records = (0..<20_000).map { index in
            makeRecord(id: "cancel_\(index).ply", treeID: "T-\(index)")
        }

        let task = Task {
            try await BatchExportService.shared.export(
                records: records,
                format: .csv,
                options: .init()
            )
        }
        task.cancel()

        do {
            let result = try await task.value
            try? FileManager.default.removeItem(at: result.url)
            XCTFail("Expected cancellation to stop background export")
        } catch is CancellationError {
            // Expected: cancellation should reach the detached export worker.
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTemporaryStorageRemovesAbandonedSessionsAndPreservesCurrentSession() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchExportStorage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let storage = BatchExportTemporaryStorage(
            baseTemporaryDirectory: baseDirectory,
            sessionID: "current-session"
        )
        let currentDirectory = try storage.prepareDirectory()
        let currentFile = currentDirectory.appendingPathComponent("active.csv")
        try Data("active".utf8).write(to: currentFile)

        let abandonedDirectory = storage.rootDirectory
            .appendingPathComponent("abandoned-session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: abandonedDirectory,
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(
            to: abandonedDirectory.appendingPathComponent("stale.csv")
        )
        let unrelatedFile = baseDirectory.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelatedFile)

        XCTAssertEqual(try storage.prepareDirectory(), currentDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }

    func testTemporaryStorageRemovalRejectsFilesOutsideCurrentSession() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchExportStorage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let storage = BatchExportTemporaryStorage(
            baseTemporaryDirectory: baseDirectory,
            sessionID: "current-session"
        )
        let currentDirectory = try storage.prepareDirectory()
        let managedFile = currentDirectory.appendingPathComponent("managed.csv")
        try Data("managed".utf8).write(to: managedFile)
        let unrelatedFile = baseDirectory.appendingPathComponent("unrelated.csv")
        try Data("unrelated".utf8).write(to: unrelatedFile)

        XCTAssertTrue(storage.removeManagedFile(at: managedFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedFile.path))
        XCTAssertFalse(storage.removeManagedFile(at: unrelatedFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }

    func testBatchExportUsesManagedSessionDirectoryAndCleanupAPI() async throws {
        let result = try await BatchExportService.shared.export(
            records: [makeRecord()],
            format: .csv,
            options: .init()
        )
        defer { BatchExportService.removeTemporaryExport(at: result.url) }

        XCTAssertEqual(
            result.url.deletingLastPathComponent().standardizedFileURL,
            BatchExportService.temporaryStorage.sessionDirectory.standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertTrue(BatchExportService.removeTemporaryExport(at: result.url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testConcurrentBatchExportsPreserveBothCurrentSessionFiles() async throws {
        let records = [makeRecord()]
        async let csvResult = BatchExportService.shared.export(
            records: records,
            format: .csv,
            options: .init()
        )
        async let jsonResult = BatchExportService.shared.export(
            records: records,
            format: .json,
            options: .init()
        )
        let results = try await [csvResult, jsonResult]
        defer {
            results.forEach { BatchExportService.removeTemporaryExport(at: $0.url) }
        }

        XCTAssertNotEqual(results[0].url, results[1].url)
        XCTAssertTrue(results.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        XCTAssertTrue(results.allSatisfy {
            $0.url.deletingLastPathComponent().standardizedFileURL
                == BatchExportService.temporaryStorage.sessionDirectory.standardizedFileURL
        })
    }

    // MARK: - (2) CSV default options: UTF-8 BOM, Chinese headers, formatted yield/GPS/date, summary totals

    func testCSVStartsWithUTF8BOM() async throws {
        let records = [makeRecord()]
        let result = try await BatchExportService.shared.export(
            records: records, format: .csv, options: .init()
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        let data = try Data(contentsOf: result.url)
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        XCTAssertEqual(Array(data.prefix(3)), bom)
    }

    func testCSVDefaultHeadersAreChinese() async throws {
        let records = [makeRecord()]
        let csv = try await exportCSVContent(records: records)
        XCTAssertTrue(csv.contains("果树编号"))
        XCTAssertTrue(csv.contains("果实数量"))
        XCTAssertTrue(csv.contains("产量(kg)"))
        XCTAssertTrue(csv.contains("纬度"))
        XCTAssertTrue(csv.contains("经度"))
        XCTAssertTrue(csv.contains("扫描日期"))
        XCTAssertTrue(csv.contains("水果类型"))
    }

    func testCSVFormatsYieldGPSDateCorrectly() async throws {
        let record = makeRecord(
            scanDate: Date(timeIntervalSince1970: 1717200000),
            fruitCount: 42, yieldKg: 12.34,
            gpsLat: 35.123456, gpsLon: 139.789012
        )
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("42"))
        XCTAssertTrue(csv.contains("12.34"))
        XCTAssertTrue(csv.contains("35.123456"))
        XCTAssertTrue(csv.contains("139.789012"))
    }

    func testCSVIncludesSummarySectionWithTotals() async throws {
        let records = [
            makeRecord(id: "a.ply", fruitCount: 3, yieldKg: 1.5),
            makeRecord(id: "b.ply", fruitCount: 7, yieldKg: 2.5),
        ]
        let csv = try await exportCSVContent(records: records)
        XCTAssertTrue(csv.contains("汇总"))
        XCTAssertTrue(csv.contains("2 棵"))
        XCTAssertTrue(csv.contains("10 个"))
        XCTAssertTrue(csv.contains("4.00 kg"))
    }

    func testBatchResearchJSONExportsMetadataRecordsAndSidecarDiagnostics() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchResearchJSON-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("scan-A.ply")
        let secondURL = tempDir.appendingPathComponent("scan-B.ply")
        let firstRecord = makeRecord(
            id: "scan-A.ply",
            treeID: "T-A",
            scanDate: Date(timeIntervalSince1970: 1_717_200_000),
            fruitCount: 12,
            yieldKg: 3.45,
            gpsLat: 35.12,
            gpsLon: 139.65,
            fruitType: "apple",
            fileURL: firstURL
        )
        let secondRecord = makeRecord(
            id: "scan-B.ply",
            treeID: "T-B",
            scanDate: Date(timeIntervalSince1970: 1_717_203_600),
            fruitCount: 8,
            yieldKg: 2.10,
            gpsLat: 36.12,
            gpsLon: 140.65,
            fruitType: "orange",
            fileURL: secondURL
        )
        try writeMockSingleScanMetadata(
            for: firstURL,
            payload: [
                "scanID": "scan-A",
                "sourceFilename": "scan-A.ply",
                "validatedFruits": [
                    [
                        "id": "fruit-fused",
                        "category": "apple",
                        "positionX": 1,
                        "positionY": 2,
                        "positionZ": 3,
                        "confidence": 0.91,
                        "source": "fused"
                    ],
                    [
                        "id": "fruit-image",
                        "category": "apple",
                        "positionX": 4,
                        "positionY": 5,
                        "positionZ": 6,
                        "confidence": 0.72,
                        "source": "image_only"
                    ]
                ],
                "fruitMassEstimates": [
                    [
                        "id": "mass-1",
                        "fruitCategory": "apple",
                        "estimatedWeightG": 245.1,
                        "confidenceScore": 0.76
                    ]
                ],
                "recognitionDiagnostics": [
                    "metadataAvailable": true,
                    "modelLabelCompatibilityStatus": "compatible",
                    "modelLabelCompatibilityWarnings": ["mock warning"],
                    "runtimeModelLabelsAvailable": true,
                    "runtimeModelLabelCount": 26,
                    "rawDetectedLabels": ["apple", "unknown fruit"],
                    "mappedDetectedCategories": ["apple"],
                    "unmappedDetectedLabels": ["unknown fruit"],
                    "filteredBySelectedFruitTypeCount": 1,
                    "confidenceFilteredCount": 1,
                    "unmappedObservationCount": 3,
                    "mappedFruitCount": 2,
                    "rawPredictions": [
                        ["label": "apple", "confidence": 0.91]
                    ]
                ],
                "diagnostics": [
                    "validatedFruitCount": 2,
                    "fusedValidationCount": 1,
                    "trackedImageFruitCount": 0,
                    "imageOnlyFruitCount": 1,
                    "cloudOnlyFruitCount": 0,
                    "pointCloudPointCount": 1200,
                    "imageDetectionCount": 3,
                    "imageFramesProcessed": 8,
                    "imageObservationCount": 6,
                    "imageConfidenceFilteredCount": 1,
                    "imageMappedFruitCount": 2,
                    "imageModelStatus": "loaded",
                    "imageModelName": "mock-detector",
                    "imageFailureReason": "",
                    "rawPredictions": [
                        ["label": "apple", "confidence": 0.91]
                    ],
                    "filteredPredictions": [
                        ["label": "apple", "confidence": 0.91]
                    ],
                    "zeroYieldReasons": ["mock low coverage"]
                ]
            ]
        )

        let payload = try await exportJSONPayload(records: [firstRecord, secondRecord])

        let metadata = try XCTUnwrap(payload["exportMetadata"] as? [String: Any])
        XCTAssertEqual(metadata["exportVersion"] as? Int, 1)
        XCTAssertEqual(metadata["recordCount"] as? Int, 2)
        XCTAssertEqual(metadata["totalEstimatedCount"] as? Int, 20)
        XCTAssertEqual(try XCTUnwrap(metadata["totalEstimatedYieldKg"] as? NSNumber).doubleValue, 5.55, accuracy: 0.0001)
        XCTAssertNotNil(metadata["exportedAt"] as? String)

        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 2)
        let first = records[0]
        XCTAssertEqual(first["scanID"] as? String, "scan-A")
        XCTAssertEqual(first["sourceFilename"] as? String, "scan-A.ply")
        XCTAssertEqual(first["treeID"] as? String, "T-A")
        XCTAssertEqual(first["fruitType"] as? String, "apple")
        XCTAssertEqual(first["estimatedCount"] as? Int, 12)
        XCTAssertEqual(try XCTUnwrap(first["estimatedYield"] as? NSNumber).doubleValue, 3.45, accuracy: 0.0001)
        XCTAssertEqual(first["singleScanMetadataAvailable"] as? Bool, true)

        let validatedFruits = try XCTUnwrap(first["validatedFruits"] as? [[String: Any]])
        XCTAssertEqual(validatedFruits.map { $0["source"] as? String }, ["fused", "image_only"])
        let massEstimates = try XCTUnwrap(first["fruitMassEstimates"] as? [[String: Any]])
        XCTAssertEqual(try XCTUnwrap(massEstimates.first?["estimatedWeightG"] as? NSNumber).doubleValue, 245.1, accuracy: 0.0001)
        let sourceCounts = try XCTUnwrap(first["sourceCounts"] as? [String: Any])
        XCTAssertEqual(sourceCounts["fusedCount"] as? Int, 1)
        XCTAssertEqual(sourceCounts["imageOnlyCount"] as? Int, 1)
        XCTAssertEqual(sourceCounts["cloudOnlyCount"] as? Int, 0)
        XCTAssertEqual(first["zeroYieldReasons"] as? [String], ["mock low coverage"])
        let diagnostics = try XCTUnwrap(first["diagnostics"] as? [String: Any])
        XCTAssertEqual(diagnostics["pointCloudPointCount"] as? Int, 1200)
        XCTAssertNil(diagnostics["rawPredictions"])
        XCTAssertNil(diagnostics["filteredPredictions"])
        let imageDiagnostics = try XCTUnwrap(first["imageDiagnostics"] as? [String: Any])
        XCTAssertEqual(imageDiagnostics["imageFramesProcessed"] as? Int, 8)
        XCTAssertEqual(imageDiagnostics["imageModelName"] as? String, "mock-detector")
        let recognitionDiagnostics = try XCTUnwrap(first["recognitionDiagnostics"] as? [String: Any])
        XCTAssertEqual(recognitionDiagnostics["metadataAvailable"] as? Bool, true)
        XCTAssertEqual(recognitionDiagnostics["modelLabelCompatibilityStatus"] as? String, "compatible")
        XCTAssertEqual(recognitionDiagnostics["modelLabelCompatibilityWarnings"] as? [String], ["mock warning"])
        XCTAssertEqual(recognitionDiagnostics["runtimeModelLabelsAvailable"] as? Bool, true)
        XCTAssertEqual(recognitionDiagnostics["runtimeModelLabelCount"] as? Int, 26)
        XCTAssertEqual(recognitionDiagnostics["rawDetectedLabels"] as? [String], ["apple", "unknown fruit"])
        XCTAssertEqual(recognitionDiagnostics["mappedDetectedCategories"] as? [String], ["apple"])
        XCTAssertEqual(recognitionDiagnostics["unmappedDetectedLabels"] as? [String], ["unknown fruit"])
        XCTAssertEqual(recognitionDiagnostics["filteredBySelectedFruitTypeCount"] as? Int, 1)
        XCTAssertEqual(recognitionDiagnostics["confidenceFilteredCount"] as? Int, 1)
        XCTAssertEqual(recognitionDiagnostics["unmappedObservationCount"] as? Int, 3)
        XCTAssertEqual(recognitionDiagnostics["mappedFruitCount"] as? Int, 2)
        XCTAssertNil(recognitionDiagnostics["rawPredictions"])
        XCTAssertNil(recognitionDiagnostics["filteredPredictions"])

        let second = records[1]
        XCTAssertEqual(second["scanID"] as? String, "scan-B")
        XCTAssertEqual(second["sourceFilename"] as? String, "scan-B.ply")
        XCTAssertEqual(second["fruitType"] as? String, "orange")
        XCTAssertEqual(second["singleScanMetadataAvailable"] as? Bool, false)
        XCTAssertTrue((second["validatedFruits"] as? [[String: Any]])?.isEmpty == true)
        XCTAssertEqual(second["zeroYieldReasons"] as? [String], [])
        let secondRecognitionDiagnostics = try XCTUnwrap(second["recognitionDiagnostics"] as? [String: Any])
        XCTAssertEqual(secondRecognitionDiagnostics["metadataAvailable"] as? Bool, false)
        XCTAssertEqual(secondRecognitionDiagnostics["runtimeModelLabelsAvailable"] as? Bool, false)
        XCTAssertEqual(secondRecognitionDiagnostics["runtimeModelLabelCount"] as? Int, 0)
        XCTAssertEqual(secondRecognitionDiagnostics["rawDetectedLabels"] as? [String], [])
        XCTAssertTrue((second["compatibilityNote"] as? String)?.contains("sidecar unavailable") == true)
    }

    func testExportResultReturnsCorrectMetadata() async throws {
        let records = [
            makeRecord(id: "a.ply", fruitCount: 10, yieldKg: 3.0),
            makeRecord(id: "b.ply", fruitCount: 20, yieldKg: 7.0),
        ]
        let result = try await BatchExportService.shared.export(
            records: records, format: .csv, options: .init()
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        XCTAssertEqual(result.recordCount, 2)
        XCTAssertEqual(result.totalYield, 10.0, accuracy: 0.01)
        XCTAssertEqual(result.totalFruitCount, 30)
    }

    // MARK: - (3) CSV escaping: quotes, commas, newlines in text fields

    func testCSVEscapesDoubleQuotesInFields() async throws {
        let record = makeRecord(id: "x.ply", treeID: #"Tree"A""#, fruitType: "cherry")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains(#""Tree""A""""#))
    }

    func testCSVEscapesCommasInFields() async throws {
        let record = makeRecord(id: "x.ply", treeID: "Tree,A", fruitType: "apple")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains(#""Tree,A""#))
    }

    func testCSVEscapesNewlinesInFields() async throws {
        let record = makeRecord(id: "x.ply", treeID: "Line1\nLine2", fruitType: "pear")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("\"Line1\nLine2\""))
    }

    func testCSVEscapesCommaAndQuoteInSameField() async throws {
        let record = makeRecord(id: "x.ply", treeID: #"A,B""C"#, fruitType: "kiwi")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains(#""A,B""""C""#))
    }

    // MARK: - (4) Excluding GPS/yield/fruitCount/treeID/date removes headers/values, keeps fruit type

    func testExcludingAllColumnOptionsKeepsOnlyFruitType() async throws {
        var options = BatchExportService.ExportOptions()
        options.includeGPS = false
        options.includeYield = false
        options.includeFruitCount = false
        options.includeTreeID = false
        options.includeDate = false
        let records = [makeRecord(fruitType: "banana")]
        let csv = try await exportCSVContent(records: records, options: options)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let headerLine = stripBOM(lines.first ?? "")
        XCTAssertEqual(headerLine, "水果类型")
        XCTAssertFalse(headerLine.contains("果树编号"))
        XCTAssertFalse(headerLine.contains("果实数量"))
        XCTAssertFalse(headerLine.contains("产量"))
        XCTAssertFalse(headerLine.contains("纬度"))
        XCTAssertFalse(headerLine.contains("经度"))
        XCTAssertFalse(headerLine.contains("扫描日期"))
    }

    func testCSVSummaryOmitsFruitCountAndYieldWhenFieldsAreExcluded() async throws {
        var options = BatchExportService.ExportOptions()
        options.includeFruitCount = false
        options.includeYield = false

        let csv = try await exportCSVContent(
            records: [makeRecord(fruitCount: 9_876, yieldKg: 543.21)],
            options: options
        )

        XCTAssertTrue(csv.contains("1 棵"))
        XCTAssertFalse(csv.contains("9876"))
        XCTAssertFalse(csv.contains("543.21"))
    }

    func testCSVSummaryHonorsFruitCountAndYieldOptionsIndependently() async throws {
        let record = makeRecord(fruitCount: 9_876, yieldKg: 543.21)

        var countOnlyOptions = BatchExportService.ExportOptions()
        countOnlyOptions.includeFruitCount = true
        countOnlyOptions.includeYield = false
        let countOnlyCSV = try await exportCSVContent(
            records: [record],
            options: countOnlyOptions
        )
        XCTAssertTrue(countOnlyCSV.contains("9876"))
        XCTAssertFalse(countOnlyCSV.contains("543.21"))

        var yieldOnlyOptions = BatchExportService.ExportOptions()
        yieldOnlyOptions.includeFruitCount = false
        yieldOnlyOptions.includeYield = true
        let yieldOnlyCSV = try await exportCSVContent(
            records: [record],
            options: yieldOnlyOptions
        )
        XCTAssertFalse(yieldOnlyCSV.contains("9876"))
        XCTAssertTrue(yieldOnlyCSV.contains("543.21"))
    }

    func testExcludingGPSOnlyRemovesLatLngHeaders() async throws {
        var options = BatchExportService.ExportOptions()
        options.includeGPS = false
        let csv = try await exportCSVContent(records: [makeRecord()], options: options)
        XCTAssertTrue(csv.contains("果树编号"))
        XCTAssertFalse(csv.contains("纬度"))
        XCTAssertFalse(csv.contains("经度"))
    }

    // MARK: - (5) groupBy produces group column and stable expected grouping labels

    func testGroupByFruitTypeAddsGroupColumnWithLabels() async throws {
        let date = Date(timeIntervalSince1970: 1717200000)
        let records = [
            makeRecord(id: "a.ply", scanDate: date, fruitType: "apple"),
            makeRecord(id: "b.ply", scanDate: date, fruitType: "banana"),
        ]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .fruitType
        let csv = try await exportCSVContent(records: records, options: options)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(lines.first?.hasPrefix("分组") ?? false)
        XCTAssertTrue(lines.dropFirst().contains(where: { $0.hasPrefix("apple,") || $0.hasPrefix("\"apple\",") }))
        XCTAssertTrue(lines.dropFirst().contains(where: { $0.hasPrefix("banana,") || $0.hasPrefix("\"banana\",") }))
    }

    func testGroupByFruitTypeOrdersByLabelThenDateDescending() async throws {
        let early = Date(timeIntervalSince1970: 1717200000)
        let late = Date(timeIntervalSince1970: 1717800000)
        let records = [
            makeRecord(id: "a.ply", scanDate: early, fruitType: "banana"),
            makeRecord(id: "b.ply", scanDate: early, fruitType: "apple"),
            makeRecord(id: "c.ply", scanDate: late, fruitType: "apple"),
        ]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .fruitType
        let csv = try await exportCSVContent(records: records, options: options)
        let dataLines = recordRows(from: csv)
        XCTAssertEqual(dataLines.count, 3)
        let labels = dataLines.compactMap { $0.split(separator: ",").first }.map(String.init)
        XCTAssertEqual(labels, ["apple", "apple", "banana"])
    }

    func testGroupByDateProducesYYYYMMDDLabels() async throws {
        let date1 = Date(timeIntervalSince1970: 1717200000)
        let date2 = Date(timeIntervalSince1970: 1717884800)
        let records = [
            makeRecord(id: "a.ply", scanDate: date1, fruitType: "apple"),
            makeRecord(id: "b.ply", scanDate: date2, fruitType: "pear"),
        ]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .date
        let csv = try await exportCSVContent(records: records, options: options)
        XCTAssertTrue(csv.contains("2024-06-01"))
        XCTAssertTrue(csv.contains("2024-06-09"))
    }

    func testGroupByPlotProducesPlotLabels() async throws {
        let date = Date(timeIntervalSince1970: 1717200000)
        let records = [
            makeRecord(id: "a.ply", treeID: "T-001", scanDate: date, fruitType: "apple"),
            makeRecord(id: "b.ply", treeID: "T-002", scanDate: date, fruitType: "banana"),
        ]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .plot
        options.plotNameByTreeID = ["T-001": "北区", "T-002": "南区"]
        let csv = try await exportCSVContent(records: records, options: options)
        XCTAssertTrue(csv.contains("北区"))
        XCTAssertTrue(csv.contains("南区"))
    }

    func testGroupByPlotUsesFallbackForMissingTreeID() async throws {
        let date = Date(timeIntervalSince1970: 1717200000)
        let records = [makeRecord(id: "a.ply", treeID: "T-Unknown", scanDate: date, fruitType: "apple")]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .plot
        options.plotNameByTreeID = [:]
        let csv = try await exportCSVContent(records: records, options: options)
        XCTAssertTrue(csv.contains("未分配地块"))
    }

    func testGroupByFruitTypeUsesUncategorizedForEmptyType() async throws {
        let date = Date(timeIntervalSince1970: 1717200000)
        let records = [makeRecord(id: "a.ply", treeID: "T-E", scanDate: date, fruitType: "")]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .fruitType
        let csv = try await exportCSVContent(records: records, options: options)
        XCTAssertTrue(csv.contains("未分类"))
    }

    // MARK: - (6) Excel XML export escapes XML special chars and writes numeric cells

    func testExcelExportsValidXMLWithWorkbookStructure() async throws {
        let records = [makeRecord()]
        let xml = try await exportExcelContent(records: records)
        XCTAssertTrue(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<Workbook"))
        XCTAssertTrue(xml.contains("<Worksheet ss:Name=\"果园数据\">"))
        XCTAssertTrue(xml.contains("<Table>"))
        XCTAssertTrue(xml.contains("</Table>"))
        XCTAssertTrue(xml.contains("</Worksheet>"))
        XCTAssertTrue(xml.contains("</Workbook>"))
    }

    func testExcelEscapesXMLSpecialCharacters() async throws {
        let record = makeRecord(id: "x.ply", treeID: "A&B<C>\"D'E", fruitType: "test")
        let xml = try await exportExcelContent(records: [record])
        XCTAssertTrue(xml.contains("A&amp;B&lt;C&gt;&quot;D&apos;E"))
    }

    func testExcelWritesNumericCellsForCountYieldGPS() async throws {
        let record = makeRecord(id: "x.ply", fruitCount: 7, yieldKg: 3.14, gpsLat: 35.5, gpsLon: 139.9)
        let xml = try await exportExcelContent(records: [record])
        XCTAssertTrue(xml.contains("<Data ss:Type=\"Number\">7</Data>"))
        XCTAssertTrue(xml.contains("<Data ss:Type=\"Number\">3.14</Data>"))
        XCTAssertTrue(xml.contains("<Data ss:Type=\"Number\">35.500000</Data>"))
        XCTAssertTrue(xml.contains("<Data ss:Type=\"Number\">139.900000</Data>"))
    }

    func testExcelWritesStringCellsForTreeIDAndFruitType() async throws {
        let record = makeRecord(id: "x.ply", treeID: "T-001", fruitType: "grape")
        let xml = try await exportExcelContent(records: [record])
        XCTAssertTrue(xml.contains("<Data ss:Type=\"String\">T-001</Data>"))
        XCTAssertTrue(xml.contains("<Data ss:Type=\"String\">grape</Data>"))
    }

    func testExcelNeutralizesFormulaPrefixTreeIDAndFruitType() async throws {
        let record = makeRecord(id: "x.ply", treeID: "=FORMULA(1+2)", fruitType: "+SUM(A1:A10)")
        let xml = try await exportExcelContent(records: [record])
        XCTAssertTrue(xml.contains("<Data ss:Type=\"String\">&apos;=FORMULA(1+2)</Data>"))
        XCTAssertTrue(xml.contains("<Data ss:Type=\"String\">&apos;+SUM(A1:A10)</Data>"))
    }

    func testExcelNeutralizesFormulaGroupLabel() async throws {
        let record = makeRecord(id: "x.ply", treeID: "T-001", fruitType: "apple")
        var options = BatchExportService.ExportOptions()
        options.groupBy = .plot
        options.plotNameByTreeID = ["T-001": "@dangerous"]
        let xml = try await exportExcelContent(records: [record], options: options)
        XCTAssertTrue(xml.contains("<Data ss:Type=\"String\">&apos;@dangerous</Data>"))
    }

    // MARK: - SpreadsheetTextSafety direct unit tests

    func testSpreadsheetTextSafetyNeutralizesFormulaPrefixes() {
        // = + - @ tab LF CR trigger apostrophe prefix
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("=cmd"), "'=cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("+cmd"), "'+cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("-cmd"), "'-cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("@cmd"), "'@cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("\tcmd"), "'\tcmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("\ncmd"), "'\ncmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("\rcmd"), "'\rcmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula(" =cmd"), "' =cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula(" \t=cmd"), "' \t=cmd")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("  @cmd"), "'  @cmd")
    }

    func testSpreadsheetTextSafetyPreservesNormalText() {
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("apple"), "apple")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("T-001"), "T-001")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("123"), "123")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula("三号地块"), "三号地块")
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula(" orchard"), " orchard")
    }

    func testSpreadsheetTextSafetyHandlesEmptyString() {
        XCTAssertEqual(SpreadsheetTextSafety.neutralizingFormula(""), "")
    }

    // MARK: - CSV formula neutralization in export

    func testCSVNeutralizesFormulaPrefixTreeID() async throws {
        let record = makeRecord(id: "a.ply", treeID: "=FORMULA(1+2)", fruitType: "apple")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'=FORMULA(1+2)"))
    }

    func testCSVNeutralizesFormulaPrefixFruitType() async throws {
        let record = makeRecord(id: "a.ply", treeID: "T-OK", fruitType: "+SUM(A1:A10)")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'+SUM(A1:A10)"))
    }

    func testCSVNeutralizesAtPrefixInTreeID() async throws {
        let record = makeRecord(id: "a.ply", treeID: "@dangerous", fruitType: "pear")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'@dangerous"))
    }

    func testCSVNeutralizesTabAndCRInTreeID() async throws {
        let record = makeRecord(id: "a.ply", treeID: "\tTabStart", fruitType: "\rCRStart")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'\tTabStart"))
        XCTAssertTrue(csv.contains("'\rCRStart"))
    }

    func testCSVNeutralizesLFInTextFields() async throws {
        let record = makeRecord(id: "a.ply", treeID: "\nLFStart", fruitType: "apple")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'\nLFStart"))
    }

    func testCSVPreservesNegativeGPSSinceGPSSkippedNeutralization() async throws {
        let record = makeRecord(
            id: "a.ply",
            treeID: "T-Neg",
            gpsLat: -33.8688, gpsLon: 151.2093,
            fruitType: "apple"
        )
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("-33.868800"))
        XCTAssertTrue(csv.contains("151.209300"))
    }

    func testCSVNeutralizesFormulaGroupLabel() async throws {
        let date = Date(timeIntervalSince1970: 1717200000)
        let records = [makeRecord(id: "a.ply", treeID: "T-001", scanDate: date, fruitType: "apple")]
        var options = BatchExportService.ExportOptions()
        options.groupBy = .plot
        options.plotNameByTreeID = ["T-001": "=SUM(A1:A2)"]
        let csv = try await exportCSVContent(records: records, options: options)
        XCTAssertTrue(csv.contains("'=SUM(A1:A2)"))
    }

    func testCSVNeutralizesNegativePrefixInFruitType() async throws {
        let record = makeRecord(id: "a.ply", treeID: "T-OK", fruitType: "-DASH")
        let csv = try await exportCSVContent(records: [record])
        XCTAssertTrue(csv.contains("'-DASH"))
    }

    // MARK: - Single scan CSV/result export safety

    func testScanResultExportRejectsUnsafeSourceFilename() throws {
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-001",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 35.0,
            gpsLon: 139.0,
            sourceFilename: "../evil.ply",
            result: makeYieldResult(),
            includeCSV: true
        )

        XCTAssertThrowsError(try ScanResultExportService.shared.exportIfNeeded(request)) { error in
            guard case LocalFileStorageError.invalidFilename = error else {
                return XCTFail("Expected invalidFilename, got \(error)")
            }
        }
    }

    func testScanResultExportNeutralizesCSVAndWritesMetadata() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        var result = makeYieldResult()
        result.diagnostics.detectionDepthCandidateCount = 2
        result.diagnostics.detectionDepthSupportRatio = 0.75
        result.diagnostics.pointCloudColorFilteredCount = 180
        result.diagnostics.pointCloudDenoisedPointCount = 172
        result.diagnostics.pointCloudOutlierPointCount = 8
        result.diagnostics.pointCloudOutlierRatio = 8.0 / 180.0
        result.diagnostics.validatedFruitCount = 4
        result.diagnostics.fusedValidationCount = 1
        result.diagnostics.trackedImageFruitCount = 2
        result.diagnostics.imageOnlyFruitCount = 1
        result.diagnostics.cloudOnlyFruitCount = 0
        result.diagnostics.validationSourceReliability = 0.80
        result.diagnostics.localCalibrationCountFactor = 1.10
        result.diagnostics.localCalibrationYieldFactor = 0.92
        result.diagnostics.localCalibrationCountSampleCount = 3
        result.diagnostics.localCalibrationYieldSampleCount = 2
        result.treeHeightM = 3.6
        result.crownVolM3 = 3.05
        result.diagnostics.canopyPointCount = 101
        result.diagnostics.canopyPreprocessedPointCount = 93
        result.diagnostics.canopyGroundFilteredPointCount = 5
        result.diagnostics.canopyTrunkFilteredPointCount = 3
        result.diagnostics.canopyNeighborFilteredPointCount = 4
        result.diagnostics.canopyClusterCount = 2
        result.diagnostics.canopyRobustPointCount = 91
        result.diagnostics.canopyHeightM = 3.6
        result.diagnostics.canopyWidthM = 1.8
        result.diagnostics.canopyDepthM = 0.9
        result.diagnostics.canopyOuterVolumeM3 = 3.39
        result.diagnostics.canopyVolumeM3 = 3.05
        result.diagnostics.canopyEffectiveVolumeCoefficient = 0.90
        result.diagnostics.canopyProjectionXYCoefficient = 0.82
        result.diagnostics.canopyProjectionXZCoefficient = 0.90
        result.diagnostics.canopyProjectionYZCoefficient = 0.86
        result.diagnostics.canopyProjectionEffectiveCoefficient = 0.86
        result.diagnostics.canopyVoxelSizeM = 0.08
        result.diagnostics.canopyPartitionSizeM = 0.40
        result.diagnostics.canopyPartitionCount = 9
        result.diagnostics.cameraAngleCoverage = 0.50
        result.diagnostics.scanAngleCoverage = 0.50
        result.diagnostics.imageFramesProcessed = 12
        result.diagnostics.imageObservationCount = 9
        result.diagnostics.imageConfidenceFilteredCount = 2
        result.diagnostics.imageMappedFruitCount = 4
        result.diagnostics.imageModelStatus = "loaded"
        result.diagnostics.imageModelName = "mock-detector"
        result.diagnostics.imageFailureReason = "none"
        result.diagnostics.imageModelLabelCompatibilityStatus = "compatible"
        result.diagnostics.imageModelLabelCompatibilityWarnings = ["mock warning"]
        result.diagnostics.imageRuntimeModelLabels = ["apple", "orange"]
        result.diagnostics.imageRuntimeModelLabelsAvailable = true
        result.diagnostics.imageRawDetectedLabels = ["apple", "unknown fruit"]
        result.diagnostics.imageMappedCategories = ["apple"]
        result.diagnostics.imageUnmappedLabels = ["unknown fruit"]
        result.diagnostics.filteredBySelectedFruitTypeCount = 1
        result.diagnostics.zeroYieldReasons = ["mock low coverage", "mock no fused fruit"]
        result.validatedFruits = [
            ValidatedFruitData(from: ValidatedFruit(
                category: .apple,
                position: SIMD3<Float>(1, 2, 3),
                confidence: 0.91,
                source: .fused
            )),
            ValidatedFruitData(from: ValidatedFruit(
                category: .apple,
                position: SIMD3<Float>(4, 5, 6),
                confidence: 0.72,
                source: .imageOnly
            )),
            ValidatedFruitData(from: ValidatedFruit(
                category: .apple,
                position: SIMD3<Float>(7, 8, 9),
                confidence: 0.63,
                source: .cloudOnly
            ))
        ]
        let massEstimateID = UUID()
        result.fruitMassEstimates = [
            makeMassEstimate(
                id: massEstimateID,
                fruitCategory: "apple",
                lengthCm: 9.1,
                widthCm: 8.2,
                heightCm: 7.3,
                equivalentDiameterCm: 8.2,
                selectedVolumeCm3: 288.4,
                estimatedWeightG: 245.1,
                confidenceScore: 0.76,
                pointCount: 42,
                shapeModelUsed: .ellipsoid,
                warningFlags: [.usingEllipsoidBaseline]
            )
        ]
        let request = ScanResultExportService.ExportRequest(
            treeID: "=FORMULA(1+2)",
            fruitType: "+SUM(A1:A10)",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: -33.8688,
            gpsLon: 151.2093,
            sourceFilename: sourceFilename,
            result: result,
            includeCSV: true
        )

        let exported = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(request))
        let csvURL = try XCTUnwrap(exported.csvURL)
        defer {
            try? FileManager.default.removeItem(at: csvURL)
            if let metadataURL = exported.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("'=FORMULA(1+2)"))
        XCTAssertTrue(csv.contains("'+SUM(A1:A10)"))
        XCTAssertTrue(csv.contains("'@color"))
        XCTAssertTrue(csv.contains("'-low"))
        XCTAssertTrue(csv.contains("'\tmethod"))
        XCTAssertTrue(csv.contains("'\nmanual review"))
        XCTAssertTrue(csv.contains("-33.868800"))
        XCTAssertTrue(csv.contains("151.209300"))

        let metadataURL = try XCTUnwrap(exported.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["scanID"] as? String, (sourceFilename as NSString).deletingPathExtension)
        XCTAssertEqual(payload["sourceFilename"] as? String, sourceFilename)
        XCTAssertEqual(payload["treeID"] as? String, "=FORMULA(1+2)")
        XCTAssertEqual(payload["fruitCount"] as? Int, 12)
        let diagnostics = try XCTUnwrap(payload["diagnostics"] as? [String: Any])
        XCTAssertEqual(diagnostics["detectionDepthCandidateCount"] as? Int, 2)
        XCTAssertEqual(try XCTUnwrap(diagnostics["detectionDepthSupportRatio"] as? NSNumber).doubleValue, 0.75, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["pointCloudColorFilteredCount"] as? Int, 180)
        XCTAssertEqual(diagnostics["pointCloudDenoisedPointCount"] as? Int, 172)
        XCTAssertEqual(diagnostics["pointCloudOutlierPointCount"] as? Int, 8)
        XCTAssertEqual(try XCTUnwrap(diagnostics["pointCloudOutlierRatio"] as? NSNumber).doubleValue, 8.0 / 180.0, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["validatedFruitCount"] as? Int, 4)
        XCTAssertEqual(diagnostics["fusedValidationCount"] as? Int, 1)
        XCTAssertEqual(diagnostics["trackedImageFruitCount"] as? Int, 2)
        XCTAssertEqual(diagnostics["imageOnlyFruitCount"] as? Int, 1)
        XCTAssertEqual(diagnostics["cloudOnlyFruitCount"] as? Int, 0)
        XCTAssertEqual(try XCTUnwrap(diagnostics["validationSourceReliability"] as? NSNumber).doubleValue, 0.80, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["localCalibrationCountFactor"] as? NSNumber).doubleValue, 1.10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["localCalibrationYieldFactor"] as? NSNumber).doubleValue, 0.92, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["localCalibrationCountSampleCount"] as? Int, 3)
        XCTAssertEqual(diagnostics["localCalibrationYieldSampleCount"] as? Int, 2)
        XCTAssertEqual(try XCTUnwrap(payload["treeHeightM"] as? NSNumber).doubleValue, 3.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(payload["crownVolM3"] as? NSNumber).doubleValue, 3.05, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["canopyPointCount"] as? Int, 101)
        XCTAssertEqual(diagnostics["canopyPreprocessedPointCount"] as? Int, 93)
        XCTAssertEqual(diagnostics["canopyGroundFilteredPointCount"] as? Int, 5)
        XCTAssertEqual(diagnostics["canopyTrunkFilteredPointCount"] as? Int, 3)
        XCTAssertEqual(diagnostics["canopyNeighborFilteredPointCount"] as? Int, 4)
        XCTAssertEqual(diagnostics["canopyClusterCount"] as? Int, 2)
        XCTAssertEqual(diagnostics["canopyRobustPointCount"] as? Int, 91)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyHeightM"] as? NSNumber).doubleValue, 3.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyWidthM"] as? NSNumber).doubleValue, 1.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyDepthM"] as? NSNumber).doubleValue, 0.9, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyOuterVolumeM3"] as? NSNumber).doubleValue, 3.39, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyVolumeM3"] as? NSNumber).doubleValue, 3.05, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyEffectiveVolumeCoefficient"] as? NSNumber).doubleValue, 0.90, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyProjectionXYCoefficient"] as? NSNumber).doubleValue, 0.82, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyProjectionXZCoefficient"] as? NSNumber).doubleValue, 0.90, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyProjectionYZCoefficient"] as? NSNumber).doubleValue, 0.86, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyProjectionEffectiveCoefficient"] as? NSNumber).doubleValue, 0.86, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyVoxelSizeM"] as? NSNumber).doubleValue, 0.08, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["canopyPartitionSizeM"] as? NSNumber).doubleValue, 0.40, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["canopyPartitionCount"] as? Int, 9)
        XCTAssertEqual(try XCTUnwrap(diagnostics["cameraAngleCoverage"] as? NSNumber).doubleValue, 0.50, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(diagnostics["scanAngleCoverage"] as? NSNumber).doubleValue, 0.50, accuracy: 0.0001)
        XCTAssertEqual(diagnostics["imageFramesProcessed"] as? Int, 12)
        XCTAssertEqual(diagnostics["imageObservationCount"] as? Int, 9)
        XCTAssertEqual(diagnostics["imageConfidenceFilteredCount"] as? Int, 2)
        XCTAssertEqual(diagnostics["imageMappedFruitCount"] as? Int, 4)
        XCTAssertEqual(diagnostics["imageModelStatus"] as? String, "loaded")
        XCTAssertEqual(diagnostics["imageModelName"] as? String, "mock-detector")
        XCTAssertEqual(diagnostics["imageFailureReason"] as? String, "none")
        XCTAssertEqual(diagnostics["zeroYieldReasons"] as? [String], ["mock low coverage", "mock no fused fruit"])
        XCTAssertNil(diagnostics["rawPredictions"])
        XCTAssertNil(diagnostics["filteredPredictions"])

        let recognitionDiagnostics = try XCTUnwrap(payload["recognitionDiagnostics"] as? [String: Any])
        XCTAssertEqual(recognitionDiagnostics["metadataAvailable"] as? Bool, true)
        XCTAssertEqual(recognitionDiagnostics["modelLabelCompatibilityStatus"] as? String, "compatible")
        XCTAssertEqual(recognitionDiagnostics["modelLabelCompatibilityWarnings"] as? [String], ["mock warning"])
        XCTAssertEqual(recognitionDiagnostics["runtimeModelLabelsAvailable"] as? Bool, true)
        XCTAssertEqual(recognitionDiagnostics["runtimeModelLabelCount"] as? Int, 2)
        XCTAssertEqual(recognitionDiagnostics["rawDetectedLabels"] as? [String], ["apple", "unknown fruit"])
        XCTAssertEqual(recognitionDiagnostics["mappedDetectedCategories"] as? [String], ["apple"])
        XCTAssertEqual(recognitionDiagnostics["unmappedDetectedLabels"] as? [String], ["unknown fruit"])
        XCTAssertEqual(recognitionDiagnostics["filteredBySelectedFruitTypeCount"] as? Int, 1)
        XCTAssertEqual(recognitionDiagnostics["confidenceFilteredCount"] as? Int, 2)
        XCTAssertEqual(recognitionDiagnostics["unmappedObservationCount"] as? Int, 3)
        XCTAssertEqual(recognitionDiagnostics["mappedFruitCount"] as? Int, 4)
        XCTAssertNil(recognitionDiagnostics["rawPredictions"])
        XCTAssertNil(recognitionDiagnostics["filteredPredictions"])

        let validatedFruits = try XCTUnwrap(payload["validatedFruits"] as? [[String: Any]])
        XCTAssertEqual(validatedFruits.count, 3)
        XCTAssertEqual(validatedFruits.map { $0["source"] as? String }, ["fused", "image_only", "cloud_only"])
        XCTAssertEqual(validatedFruits[0]["category"] as? String, "apple")
        XCTAssertEqual(try XCTUnwrap(validatedFruits[0]["positionX"] as? NSNumber).doubleValue, 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(validatedFruits[0]["confidence"] as? NSNumber).doubleValue, 0.91, accuracy: 0.0001)

        let massEstimates = try XCTUnwrap(payload["fruitMassEstimates"] as? [[String: Any]])
        XCTAssertEqual(massEstimates.count, 1)
        let estimate = massEstimates[0]
        XCTAssertEqual(estimate["id"] as? String, massEstimateID.uuidString)
        XCTAssertEqual(estimate["fruitCategory"] as? String, "apple")
        XCTAssertEqual(try XCTUnwrap(estimate["lengthCm"] as? NSNumber).doubleValue, 9.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(estimate["selectedVolumeCm3"] as? NSNumber).doubleValue, 288.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(estimate["estimatedWeightG"] as? NSNumber).doubleValue, 245.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(estimate["confidenceScore"] as? NSNumber).doubleValue, 0.76, accuracy: 0.0001)
        XCTAssertEqual(estimate["pointCount"] as? Int, 42)
        XCTAssertEqual(estimate["shapeModelUsed"] as? String, "ellipsoid")
        XCTAssertEqual(estimate["warningFlags"] as? [String], ["usingEllipsoidBaseline"])
    }

    func testScanResultExportSanitizesNonFiniteNumericValues() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        var result = makeYieldResult()
        result.yieldFinalKg = .nan
        result.clusterEps = .infinity
        result.occlusionK = -.infinity
        result.meanDiameterCm = .nan
        result.meanVolumeCm3 = .infinity
        result.correctionK = .nan
        result.yieldBVisibleKg = .infinity
        result.yieldBCorrectedKg = -.infinity
        result.fruitMassEstimates = [
            makeMassEstimate(
                lengthCm: .nan,
                widthCm: .infinity,
                heightCm: -.infinity,
                selectedVolumeCm3: .nan,
                estimatedWeightG: .infinity,
                confidenceScore: .nan,
                pointCount: -4
            )
        ]

        let request = ScanResultExportService.ExportRequest(
            treeID: "T-clean",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: .nan,
            gpsLon: .infinity,
            sourceFilename: sourceFilename,
            result: result,
            includeCSV: true
        )

        let exported = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(request))
        let csvURL = try XCTUnwrap(exported.csvURL)
        defer {
            try? FileManager.default.removeItem(at: csvURL)
            if let metadataURL = exported.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        let csv = try String(contentsOf: csvURL, encoding: .utf8).lowercased()
        XCTAssertFalse(csv.contains("nan"))
        XCTAssertFalse(csv.contains("inf"))

        let metadataURL = try XCTUnwrap(exported.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for key in [
            "yieldKg",
            "clusterEps",
            "occlusionK",
            "meanDiameterCm",
            "meanVolumeCm3",
            "correctionK",
            "yieldBVisibleKg",
            "yieldBCorrectedKg",
            "gpsLat",
            "gpsLon"
        ] {
            let value = try XCTUnwrap(payload[key] as? NSNumber, "Missing numeric key \(key)")
            XCTAssertEqual(value.doubleValue, 0, accuracy: 0.000001, key)
        }

        let massEstimates = try XCTUnwrap(payload["fruitMassEstimates"] as? [[String: Any]])
        let estimate = try XCTUnwrap(massEstimates.first)
        for key in [
            "lengthCm",
            "widthCm",
            "heightCm",
            "selectedVolumeCm3",
            "estimatedWeightG",
            "confidenceScore"
        ] {
            let value = try XCTUnwrap(estimate[key] as? NSNumber, "Missing mass-estimate key \(key)")
            XCTAssertEqual(value.doubleValue, 0, accuracy: 0.000001, key)
        }
        XCTAssertEqual(estimate["pointCount"] as? Int, 0)
    }

    func testScanResultExportBoundsGPSCoordinates() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-bad-gps",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 90.1,
            gpsLon: -180.1,
            sourceFilename: sourceFilename,
            result: makeYieldResult(),
            includeCSV: true
        )

        let exported = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(request))
        let csvURL = try XCTUnwrap(exported.csvURL)
        defer {
            try? FileManager.default.removeItem(at: csvURL)
            if let metadataURL = exported.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains(",0.000000,0.000000,"))
        XCTAssertFalse(csv.contains("90.100000"))
        XCTAssertFalse(csv.contains("-180.100000"))

        let metadataURL = try XCTUnwrap(exported.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let gpsLat = try XCTUnwrap(payload["gpsLat"] as? NSNumber)
        let gpsLon = try XCTUnwrap(payload["gpsLon"] as? NSNumber)
        XCTAssertEqual(gpsLat.doubleValue, 0, accuracy: 0.000001)
        XCTAssertEqual(gpsLon.doubleValue, 0, accuracy: 0.000001)
    }

    func testScanResultExportRejectsNegativePrimaryTotals() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-negative",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 35.0,
            gpsLon: 139.0,
            sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: -9, yieldKg: -2.5),
            includeCSV: true
        )

        let exported = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(request))
        let csvURL = try XCTUnwrap(exported.csvURL)
        defer {
            try? FileManager.default.removeItem(at: csvURL)
            if let metadataURL = exported.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains(",0,0.00,"))
        XCTAssertFalse(csv.contains("-9"))
        XCTAssertFalse(csv.contains("-2.50"))

        let metadataURL = try XCTUnwrap(exported.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["fruitCount"] as? Int, 0)
        let yieldKg = try XCTUnwrap(payload["yieldKg"] as? NSNumber)
        XCTAssertEqual(yieldKg.doubleValue, 0, accuracy: 0.000001)
    }

    func testScanResultExportRefreshesCSVAndMetadataInTheSameRevision() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        let firstRequest = ScanResultExportService.ExportRequest(
            treeID: "T-first",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 35.0,
            gpsLon: 139.0,
            sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 7, yieldKg: 1.25),
            includeCSV: true
        )
        let secondRequest = ScanResultExportService.ExportRequest(
            treeID: "T-second",
            fruitType: "orange",
            scanDate: Date(timeIntervalSince1970: 1717203600),
            gpsLat: 36.0,
            gpsLon: 140.0,
            sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 21, yieldKg: 4.5),
            includeCSV: true
        )

        let firstExport = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(firstRequest))
        let secondExport = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(secondRequest))
        let firstCSVURL = try XCTUnwrap(firstExport.csvURL)
        let secondCSVURL = try XCTUnwrap(secondExport.csvURL)
        defer {
            try? FileManager.default.removeItem(at: firstCSVURL)
            if let metadataURL = firstExport.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
            if let manifestURL = firstExport.manifestURL {
                try? FileManager.default.removeItem(at: manifestURL)
            }
        }

        XCTAssertEqual(firstCSVURL, secondCSVURL)

        let csv = try String(contentsOf: firstCSVURL, encoding: .utf8)
        XCTAssertFalse(csv.contains("T-first"))
        XCTAssertTrue(csv.contains("T-second"))

        let metadataURL = try XCTUnwrap(secondExport.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["treeID"] as? String, "T-second")
        XCTAssertEqual(payload["fruitCount"] as? Int, 21)
        let manifestURL = try XCTUnwrap(secondExport.manifestURL)
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(payload["exportRevision"] as? String, manifest["exportRevision"] as? String)
        XCTAssertTrue(csv.contains(try XCTUnwrap(payload["exportRevision"] as? String)))
    }

    func testScanResultExportSkipsCSVWhenDisabledButWritesMetadata() throws {
        let sourceFilename = "scan-result-\(UUID().uuidString).ply"
        let baseName = (sourceFilename as NSString).deletingPathExtension
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans", isDirectory: true)
        let expectedCSVURL = scansDir.appendingPathComponent("\(baseName).csv")
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-no-csv",
            fruitType: "apple",
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 35.0,
            gpsLon: 139.0,
            sourceFilename: sourceFilename,
            result: makeYieldResult(),
            includeCSV: false
        )

        let exported = try XCTUnwrap(ScanResultExportService.shared.exportIfNeeded(request))
        defer {
            try? FileManager.default.removeItem(at: expectedCSVURL)
            if let metadataURL = exported.metadataURL {
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        XCTAssertNil(exported.csvURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedCSVURL.path))
        let metadataURL = try XCTUnwrap(exported.metadataURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    func testScanResultExportCSVStagingFailureKeepsPreviousCompleteRevisionReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFilename = "scan.ply"
        let plyURL = directory.appendingPathComponent(sourceFilename)
        try Data().write(to: plyURL)

        let original = ScanResultExportService.ExportRequest(
            treeID: "T-old", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 7, yieldKg: 1.25), includeCSV: true
        )
        let replacement = ScanResultExportService.ExportRequest(
            treeID: "T-new", fruitType: "pear", scanDate: Date(timeIntervalSince1970: 2),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 21, yieldKg: 4.5), includeCSV: true
        )
        try ScanResultExportService(scansDirectory: directory).exportIfNeeded(original)
        let failingService = ScanResultExportService(scansDirectory: directory, writeData: { data, url in
            if url.pathExtension == "csv" { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })

        XCTAssertThrowsError(try failingService.exportIfNeeded(replacement))
        let read = PLYParserHelper.readCompanionResult(for: plyURL)
        XCTAssertEqual(read.state, .complete)
        XCTAssertEqual(read.result?.fruitCount, 7)
        XCTAssertEqual(read.result?.fruitType, "apple")
    }

    func testScanResultExportMetadataStagingFailureDoesNotPublishCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-01", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: "scan.ply", result: makeYieldResult(), includeCSV: true
        )
        let service = ScanResultExportService(scansDirectory: directory, writeData: { _, url in
            if url.lastPathComponent.hasSuffix("_result.json") { throw CocoaError(.fileWriteNoPermission) }
        })

        XCTAssertThrowsError(try service.exportIfNeeded(request))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("scan_complete.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("scan_result.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("scan.csv").path))
    }

    func testScanResultExportManifestFailureKeepsPreviousCompleteRevisionReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFilename = "scan.ply"
        let plyURL = directory.appendingPathComponent(sourceFilename)
        try Data().write(to: plyURL)
        let original = ScanResultExportService.ExportRequest(
            treeID: "T-old", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 7, yieldKg: 1.25), includeCSV: true
        )
        let replacement = ScanResultExportService.ExportRequest(
            treeID: "T-new", fruitType: "pear", scanDate: Date(timeIntervalSince1970: 2),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 21, yieldKg: 4.5), includeCSV: true
        )
        try ScanResultExportService(scansDirectory: directory).exportIfNeeded(original)
        let failingService = ScanResultExportService(scansDirectory: directory, writeData: { data, url in
            if url.lastPathComponent.hasSuffix("_complete.json") { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })

        XCTAssertThrowsError(try failingService.exportIfNeeded(replacement))
        let read = PLYParserHelper.readCompanionResult(for: plyURL)
        XCTAssertEqual(read.state, .complete)
        XCTAssertEqual(read.result?.fruitCount, 7)
    }

    func testScanResultExportDoesNotExposeReplacementAsCompleteBeforeAllRequiredFilesPublish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFilename = "scan.ply"
        let plyURL = directory.appendingPathComponent(sourceFilename)
        try Data().write(to: plyURL)
        let original = ScanResultExportService.ExportRequest(
            treeID: "T-old", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 7, yieldKg: 1.25), includeCSV: true
        )
        let replacement = ScanResultExportService.ExportRequest(
            treeID: "T-new", fruitType: "pear", scanDate: Date(timeIntervalSince1970: 2),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 21, yieldKg: 4.5), includeCSV: true
        )
        try ScanResultExportService(scansDirectory: directory).exportIfNeeded(original)
        var observedState: ScanPersistenceState?
        let interruptedService = ScanResultExportService(scansDirectory: directory, publishFile: { source, destination in
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            if destination.lastPathComponent == "scan_result.json" {
                observedState = PLYParserHelper.readCompanionResult(for: plyURL).state
                throw CocoaError(.fileWriteNoPermission)
            }
        })

        XCTAssertThrowsError(try interruptedService.exportIfNeeded(replacement))
        XCTAssertEqual(observedState, .invalid)
        let restored = PLYParserHelper.readCompanionResult(for: plyURL)
        XCTAssertEqual(restored.state, .complete)
        XCTAssertEqual(restored.result?.fruitCount, 7)
        XCTAssertEqual(restored.result?.fruitType, "apple")
    }

    func testScanResultExportRemovesObsoleteCSVBeforeNoCSVRevisionBecomesComplete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFilename = "scan.ply"
        let plyURL = directory.appendingPathComponent(sourceFilename)
        let csvURL = directory.appendingPathComponent("scan.csv")
        try Data().write(to: plyURL)
        let original = ScanResultExportService.ExportRequest(
            treeID: "T-old", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 7, yieldKg: 1.25), includeCSV: true
        )
        let replacement = ScanResultExportService.ExportRequest(
            treeID: "T-new", fruitType: "pear", scanDate: Date(timeIntervalSince1970: 2),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename,
            result: makeYieldResult(nLidar: 21, yieldKg: 4.5), includeCSV: false
        )
        try ScanResultExportService(scansDirectory: directory).exportIfNeeded(original)
        var obsoleteCSVExistsWhenComplete: Bool?
        let interruptedService = ScanResultExportService(scansDirectory: directory, publishFile: { source, destination in
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            if destination.lastPathComponent == "scan_result.json" {
                let read = PLYParserHelper.readCompanionResult(for: plyURL)
                XCTAssertEqual(read.state, .complete)
                obsoleteCSVExistsWhenComplete = FileManager.default.fileExists(atPath: csvURL.path)
                throw CocoaError(.fileWriteNoPermission)
            }
        })

        XCTAssertThrowsError(try interruptedService.exportIfNeeded(replacement))
        XCTAssertEqual(obsoleteCSVExistsWhenComplete, false)
        let restored = PLYParserHelper.readCompanionResult(for: plyURL)
        XCTAssertEqual(restored.state, .complete)
        XCTAssertEqual(restored.result?.fruitCount, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: csvURL.path))
    }

    func testTransactionalReaderRejectsCSVRevisionMismatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFilename = "scan.ply"
        let plyURL = directory.appendingPathComponent(sourceFilename)
        try Data().write(to: plyURL)
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-01", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: sourceFilename, result: makeYieldResult(), includeCSV: true
        )
        let exported = try XCTUnwrap(ScanResultExportService(scansDirectory: directory).exportIfNeeded(request))
        let metadataURL = try XCTUnwrap(exported.metadataURL)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
        let revision = try XCTUnwrap(metadata["exportRevision"] as? String)
        let csvURL = try XCTUnwrap(exported.csvURL)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        try csv.replacingOccurrences(of: revision, with: "mismatched-revision").write(to: csvURL, atomically: true, encoding: .utf8)

        let read = PLYParserHelper.readCompanionResult(for: plyURL)
        XCTAssertEqual(read.state, .invalid)
        XCTAssertEqual(read.failureReason, "scanResultRevisionMismatch")
    }

    func testScanResultExportSameSnapshotIsIdempotentAndUsesOneRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = ScanResultExportService.ExportRequest(
            treeID: "T-01", fruitType: "apple", scanDate: Date(timeIntervalSince1970: 1),
            gpsLat: 0, gpsLon: 0, sourceFilename: "scan.ply", result: makeYieldResult(), includeCSV: true
        )
        let service = ScanResultExportService(scansDirectory: directory)
        let first = try XCTUnwrap(service.exportIfNeeded(request))
        let firstManifest = try XCTUnwrap(first.manifestURL)
        let firstData = try Data(contentsOf: firstManifest)
        let second = try XCTUnwrap(service.exportIfNeeded(request))

        XCTAssertEqual(first.manifestURL, second.manifestURL)
        XCTAssertEqual(try Data(contentsOf: firstManifest), firstData)
    }

    func testBatchExportExcludesIncompleteAndInvalidRecordsFromTotals() async throws {
        let complete = makeRecord(id: "complete.ply", fruitCount: 10, yieldKg: 5, persistenceState: .complete)
        let incomplete = makeRecord(id: "incomplete.ply", fruitCount: 99, yieldKg: 99, persistenceState: .incomplete)
        let invalid = makeRecord(id: "invalid.ply", fruitCount: 88, yieldKg: 88, persistenceState: .invalid)

        let exported = try await BatchExportService.shared.export(
            records: [complete, incomplete, invalid], format: .csv, options: .init()
        )
        defer { try? FileManager.default.removeItem(at: exported.url) }
        XCTAssertEqual(exported.recordCount, 1)
        XCTAssertEqual(exported.totalFruitCount, 10)
        XCTAssertEqual(exported.totalYield, 5, accuracy: 0.000_1)
        XCTAssertEqual(exported.excludedIncompleteCount, 2)
    }

    func testBatchExportSelectionPolicyKeepsOnlyCompleteRecordIDs() {
        let complete = makeRecord(id: "complete.ply", persistenceState: .complete)
        let incomplete = makeRecord(id: "incomplete.ply", persistenceState: .incomplete)
        let invalid = makeRecord(id: "invalid.ply", persistenceState: .invalid)
        let records = [complete, incomplete, invalid]
        let requestedSelection = Set(records.map(\.id))

        XCTAssertEqual(
            BatchExportSelectionPolicy.exportableRecordIDs(from: records),
            Set([complete.id])
        )
        XCTAssertEqual(
            BatchExportSelectionPolicy.normalizedSelection(requestedSelection, for: records),
            Set([complete.id])
        )
    }

    func testBatchExportSelectionPolicyReturnsEmptyForOnlyUnavailableRecords() {
        let records = [
            makeRecord(id: "incomplete.ply", persistenceState: .incomplete),
            makeRecord(id: "invalid.ply", persistenceState: .invalid),
        ]

        XCTAssertTrue(BatchExportSelectionPolicy.exportableRecordIDs(from: records).isEmpty)
        XCTAssertTrue(
            BatchExportSelectionPolicy.normalizedSelection(Set(records.map(\.id)), for: records).isEmpty
        )
    }

    func testExcelExcludedColumnsOmitCells() async throws {
        var options = BatchExportService.ExportOptions()
        options.includeGPS = false
        options.includeYield = false
        options.includeFruitCount = false
        options.includeTreeID = false
        options.includeDate = false
        let record = makeRecord(id: "x.ply", fruitType: "mango")
        let xml = try await exportExcelContent(records: [record], options: options)
        XCTAssertFalse(xml.contains("果树编号"))
        XCTAssertTrue(xml.contains("水果类型"))
    }
}
