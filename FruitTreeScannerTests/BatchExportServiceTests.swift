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
