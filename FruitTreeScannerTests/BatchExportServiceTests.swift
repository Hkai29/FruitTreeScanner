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
        fruitType: String = "apple"
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/\(id)"),
            scanDate: scanDate,
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            fruitType: fruitType
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

    func testScanResultExportPreservesExistingCSVAndRefreshesMetadata() throws {
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
        }

        XCTAssertEqual(firstCSVURL, secondCSVURL)

        let csv = try String(contentsOf: firstCSVURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("T-first"))
        XCTAssertFalse(csv.contains("T-second"))

        let metadataURL = try XCTUnwrap(secondExport.metadataURL)
        let data = try Data(contentsOf: metadataURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["treeID"] as? String, "T-second")
        XCTAssertEqual(payload["fruitCount"] as? Int, 21)
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
