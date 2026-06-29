import XCTest
@testable import FruitTreeScanner

final class FruitModelsTests: XCTestCase {

    func testAllCategoriesHaveSizeRange() {
        for category in FruitCategory.allCases {
            XCTAssertGreaterThan(category.sizeRange.lowerBound, 0,
                                 "\(category.displayName) sizeRange.lowerBound 应 > 0")
            XCTAssertGreaterThan(category.sizeRange.upperBound, category.sizeRange.lowerBound,
                                 "\(category.displayName) sizeRange 应为有效区间")
        }
    }

    func testAllCategoriesHaveDensity() {
        for category in FruitCategory.allCases {
            XCTAssertGreaterThan(category.density, 0,
                                 "\(category.displayName) density 应 > 0")
            XCTAssertLessThanOrEqual(category.density, 1.5,
                                     "\(category.displayName) density 应合理")
        }
    }

    func testAllCategoriesHaveAverageWeight() {
        for category in FruitCategory.allCases {
            XCTAssertGreaterThan(category.averageWeightG, 0,
                                 "\(category.displayName) averageWeightG 应 > 0")
        }
    }

    func testColorFilterMatches() {
        let filter = ColorFilter(rMin: 0.5, gMax: 0.4, bMax: 0.3)
        XCTAssertTrue(filter.matches(r: 0.6, g: 0.3, b: 0.2), "应匹配")
        XCTAssertFalse(filter.matches(r: 0.3, g: 0.3, b: 0.2), "r 太低不应匹配")
        XCTAssertFalse(filter.matches(r: 0.6, g: 0.5, b: 0.2), "g 太高不应匹配")
    }

    func testIsFruitColor() {
        let redApple = SIMD3<Float>(0.85, 0.2, 0.1)
        XCTAssertTrue(FruitCategory.isFruitColor(redApple), "红色应被识别为果实颜色")

        let gray = SIMD3<Float>(0.5, 0.5, 0.5)
        XCTAssertFalse(FruitCategory.isFruitColor(gray), "灰色不应被识别为果实颜色")

        let darkColor = SIMD3<Float>(0.05, 0.05, 0.05)
        XCTAssertFalse(FruitCategory.isFruitColor(darkColor), "极暗色不应被识别为果实颜色")
    }

    func testCOCOMapping() {
        XCTAssertEqual(FruitCategory.fromCOCO(77), .apple, "COCO 77 应映射为 apple")
        XCTAssertEqual(FruitCategory.fromCOCO(78), .orange, "COCO 78 应映射为 orange")
        XCTAssertNil(FruitCategory.fromCOCO(999), "不存在的 COCO ID 应返回 nil")
    }

    func testWeightedFruitCountUsesRoundedCategoryTotals() {
        let counter = FruitCounter()
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 0), confidence: 0.9, source: .imageOnly),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.1, 0, 0), confidence: 0.8, source: .imageOnly),
        ]

        let result = counter.count(fruits)

        XCTAssertEqual(result.fruitCounts["apple"], 1, "两个 imageOnly 应按权重折算为 1 个")
        XCTAssertEqual(result.totalCount, 1, "totalCount 应与加权后的分类总数一致")
        XCTAssertEqual(counter.weightedTotal(fruits), 1.0, accuracy: 0.001)
    }

    func testPLYParserHeaderMetadataFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("no_pattern.ply")
        let headerContent = """
        ply
        format ascii 1.0
        comment tree_id Tree_Header_42
        comment scan_date 2025-01-15T10:30:00Z
        comment gps_lat 39.9042
        comment gps_lon 116.4074
        end_header
        0 0 0 128 128 128
        """
        try headerContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.treeID, "Tree_Header_42")
        XCTAssertEqual(parsed.gpsLat, 39.9042, accuracy: 0.0001)
        XCTAssertEqual(parsed.gpsLon, 116.4074, accuracy: 0.0001)
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
        XCTAssertEqual(parsed.fruitType, "apple")
    }

    func testPLYParserReadsCRLFHeaderMetadataFromRendererStyleExport() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("renderer_crlf_header.ply")
        let headerContent = [
            "ply",
            "format ascii 1.0",
            "comment tree_id Renderer_CRLF_42",
            "comment scan_date 2025-01-15T10:30:00Z",
            "comment gps_lat 39.9042",
            "comment gps_lon 116.4074",
            "element vertex 0",
            "end_header"
        ].joined(separator: "\r\n") + "\r\n"
        try headerContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.treeID, "Renderer_CRLF_42")
        XCTAssertEqual(parsed.gpsLat, 39.9042, accuracy: 0.0001)
        XCTAssertEqual(parsed.gpsLon, 116.4074, accuracy: 0.0001)
    }

    func testPLYParserPrefersHeaderIdentityOverSanitizedFilename() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent(
            "Tree-a1b2c3d4_20260625_101500_lat35.1000_lon139.2000.ply"
        )
        let headerContent = """
        ply
        format ascii 1.0
        comment tree_id 三号地块 12-A
        comment scan_date 2026-06-25 10:15:00
        comment gps_lat 35.123456
        comment gps_lon 139.654321
        element vertex 0
        end_header
        """
        try headerContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.treeID, "三号地块 12-A")
        XCTAssertEqual(parsed.gpsLat, 35.123456, accuracy: 0.000001)
        XCTAssertEqual(parsed.gpsLon, 139.654321, accuracy: 0.000001)
    }

    func testPLYParserReadsHeaderMetadataBeyondLegacy16KBPrefix() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent(
            "Fallback_20260625_101500_lat35.1000_lon139.2000.ply"
        )
        let longComment = "comment filler \(String(repeating: "x", count: 17_000))"
        let headerContent = """
        ply
        format ascii 1.0
        \(longComment)
        comment tree_id 长注释后的树
        comment gps_lat 35.333333
        comment gps_lon 139.444444
        element vertex 0
        end_header
        """
        XCTAssertGreaterThan(headerContent.utf8.count, 16_384)
        XCTAssertLessThan(headerContent.utf8.count, PLYParserHelper.maximumHeaderSize)
        try headerContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.treeID, "长注释后的树")
        XCTAssertEqual(parsed.gpsLat, 35.333333, accuracy: 0.000001)
        XCTAssertEqual(parsed.gpsLon, 139.444444, accuracy: 0.000001)
    }

    func testPLYParserMissingCSVReturnsDefaults() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T002_20250301_080000_lat30.0_lon120.0.ply")
        try Data().write(to: plyURL)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.fruitCount, 0, "缺失CSV时fruitCount应为0")
        XCTAssertEqual(parsed.yieldKg, 0, "缺失CSV时yieldKg应为0")
        XCTAssertEqual(parsed.fruitType, "apple", "缺失CSV时fruitType默认apple")
        XCTAssertEqual(parsed.confidence, "low", "缺失CSV时confidence默认low")
    }

    func testPLYParserResultJSONCompanion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T003_20250601_120000_lat25.0_lon121.0.ply")
        let jsonURL = tempDir.appendingPathComponent("T003_20250601_120000_lat25.0_lon121.0_result.json")
        let jsonContent = """
        {"fruitCount": 25, "yieldKg": 8.75, "fruitType": "orange", "confidence": "high"}
        """
        try Data().write(to: plyURL)
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.fruitCount, 25)
        XCTAssertEqual(parsed.yieldKg, 8.75, accuracy: 0.01)
        XCTAssertEqual(parsed.fruitType, "orange")
        XCTAssertEqual(parsed.confidence, "high")
    }

    func testPLYParserFallbackMetadataFromURL() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("mystery_tree.ply")
        try Data().write(to: plyURL)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.treeID, "mystery_tree")
        XCTAssertEqual(parsed.gpsLat, 0)
        XCTAssertEqual(parsed.gpsLon, 0)
        XCTAssertEqual(parsed.fruitCount, 0)
    }

    func testPLYParserPointCloudDataNonExistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/pointcloud.ply")
        XCTAssertNil(PLYParserHelper.parsePointCloudData(at: url))
    }

    func testPLYParserPrefersTimestampFromFilename() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T001_20240506_123456_lat22.1234_lon114.5678.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")

        try Data().write(to: plyURL)
        try """
        树编号,水果类型,扫描日期,果实数量,产量(kg),GPS纬度,GPS经度
        T001,apple,2024-05-06 12:34:56,12,3.50,22.1234,114.5678
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: parsed.scanDate
        )

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 6)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 34)
        XCTAssertEqual(components.second, 56)
    }

    func testPLYParserReadsConfidenceFromResultCSV() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T004_20240506_123456_lat22.0_lon114.0.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")

        try Data().write(to: plyURL)
        try """
        树编号,水果类型,扫描日期,果实数量,产量(kg),GPS纬度,GPS经度,聚类Eps,聚类MinPoints,颜色过滤,遮挡系数K,点云大小,置信度,方法,备注
        T004,pear,2024-05-06 12:34:56,18,4.25,22.0,114.0,0.050,6,N/A,1.00,1000,medium,Fusion,OK
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.fruitCount, 18)
        XCTAssertEqual(parsed.yieldKg, 4.25, accuracy: 0.001)
        XCTAssertEqual(parsed.fruitType, "pear")
        XCTAssertEqual(parsed.confidence, "medium")
    }

    func testPLYParserReadsResultCSVByHeaderWhenColumnsAreReordered() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T005_20240506_123456_lat22.0_lon114.0.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")

        try Data().write(to: plyURL)
        try """
        置信度,树编号,产量(kg),水果类型,果实数量
        high,T005,8.75,orange,31
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.fruitCount, 31)
        XCTAssertEqual(parsed.yieldKg, 8.75, accuracy: 0.001)
        XCTAssertEqual(parsed.fruitType, "orange")
        XCTAssertEqual(parsed.confidence, "high")
    }

    func testPLYParserTrimsCompanionCSVValuesAndCRLF() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T006_20240506_123456_lat22.0_lon114.0.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")

        try Data().write(to: plyURL)
        try "水果类型,果实数量,产量(kg),置信度\r\n orange , 31 , 8.75 ,high\r\n"
            .write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.fruitCount, 31)
        XCTAssertEqual(parsed.yieldKg, 8.75, accuracy: 0.001)
        XCTAssertEqual(parsed.fruitType, "orange")
        XCTAssertEqual(parsed.confidence, "high")
    }

    // MARK: - ScanHistoryStore.deleteFiles transaction ordering

    func testDeleteFilesPrimaryPLYExistsRemoveThrows() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let removeItem: (URL) throws -> Void = { url in
            removed.append(url)
            throw NSError(domain: "TestError", code: 1)
        }
        let fileExists: (String) -> Bool = { $0 == fileURL.path }

        let result = ScanHistoryStore.deleteFiles(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        )

        XCTAssertFalse(result, "Should return false when primary PLY removal throws")
        XCTAssertEqual(removed.count, 1, "Should only attempt primary PLY removal, not companions")
        XCTAssertEqual(removed.first, fileURL, "Only the primary PLY URL should be passed to removeItem")
    }

    func testDeleteFilesPrimaryPLYMissingCleansCompanions() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")

        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let removeItem: (URL) throws -> Void = { removed.append($0) }
        let fileExists: (String) -> Bool = {
            $0 == csvURL.path || $0 == jsonURL.path
        }

        let result = ScanHistoryStore.deleteFiles(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        )

        XCTAssertTrue(result, "Should return true when companions are cleaned")
        XCTAssertEqual(removed.count, 2, "Should clean both CSV and JSON companions")
        XCTAssertEqual(removed[0], csvURL, "CSV companion should be removed first")
        XCTAssertEqual(removed[1], jsonURL, "JSON companion should be removed second")
    }

    func testDeleteFilesCompanionFailureReturnsFalseAndContinuesCleanup() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")

        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let removeItem: (URL) throws -> Void = { url in
            removed.append(url)
            if url == csvURL {
                throw NSError(domain: "TestError", code: 2)
            }
        }
        let fileExists: (String) -> Bool = { _ in true }

        let result = ScanHistoryStore.deleteFiles(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        )

        XCTAssertFalse(result, "Should return false when any companion removal throws")
        XCTAssertEqual(removed.count, 3, "Should still attempt JSON cleanup after CSV removal fails")
        XCTAssertEqual(removed[0], fileURL, "First removal must be primary PLY")
        XCTAssertEqual(removed[1], csvURL, "Second removal must be CSV companion")
        XCTAssertEqual(removed[2], jsonURL, "Third removal must be JSON companion")
    }

    func testDeleteFilesOrderPLYThenCSVThenJSON() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")

        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let removeItem: (URL) throws -> Void = { removed.append($0) }
        let fileExists: (String) -> Bool = { _ in true }

        let result = ScanHistoryStore.deleteFiles(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        )

        XCTAssertTrue(result, "Should return true when all files exist and removal succeeds")
        XCTAssertEqual(removed.count, 3, "Should attempt removal of all three files")
        XCTAssertEqual(removed[0], fileURL, "First removal must be primary PLY")
        XCTAssertEqual(removed[1], csvURL, "Second removal must be CSV companion")
        XCTAssertEqual(removed[2], jsonURL, "Third removal must be JSON companion")
    }

    // MARK: - Calibration input parsing

    func testCalibrationInputParserRequiresNonNegativeEstimatedFruitCount() {
        XCTAssertEqual(CalibrationRecordInputParser.requiredNonNegativeInt(" 12 "), 12)
        XCTAssertEqual(CalibrationRecordInputParser.requiredNonNegativeInt("0"), 0)
        XCTAssertNil(CalibrationRecordInputParser.requiredNonNegativeInt(""))
        XCTAssertNil(CalibrationRecordInputParser.requiredNonNegativeInt("-1"))
        XCTAssertNil(CalibrationRecordInputParser.requiredNonNegativeInt("1.5"))
        XCTAssertNil(CalibrationRecordInputParser.requiredNonNegativeInt("abc"))
    }

    func testCalibrationInputParserAllowsBlankEstimatedYieldButRejectsInvalidValues() throws {
        XCTAssertEqual(CalibrationRecordInputParser.estimatedYieldKgOrZero(""), 0)
        let parsedYield = try XCTUnwrap(CalibrationRecordInputParser.estimatedYieldKgOrZero(" 2.75 "))
        XCTAssertEqual(parsedYield, 2.75, accuracy: 0.001)
        XCTAssertNil(CalibrationRecordInputParser.estimatedYieldKgOrZero("-0.1"))
        XCTAssertNil(CalibrationRecordInputParser.estimatedYieldKgOrZero("nan"))
        XCTAssertNil(CalibrationRecordInputParser.estimatedYieldKgOrZero("abc"))
    }

    func testCalibrationInputParserOptionalFieldsTreatBlankAsValidAndRejectNegativeValues() throws {
        XCTAssertTrue(CalibrationRecordInputParser.isOptionalNonNegativeIntValid(""))
        XCTAssertNil(CalibrationRecordInputParser.optionalNonNegativeInt(""))
        XCTAssertEqual(CalibrationRecordInputParser.optionalNonNegativeInt("4"), 4)
        XCTAssertFalse(CalibrationRecordInputParser.isOptionalNonNegativeIntValid("-4"))

        XCTAssertTrue(CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid(""))
        XCTAssertNil(CalibrationRecordInputParser.optionalNonNegativeDouble(""))
        let parsedActualYield = try XCTUnwrap(CalibrationRecordInputParser.optionalNonNegativeDouble("1.25"))
        XCTAssertEqual(parsedActualYield, 1.25, accuracy: 0.001)
        XCTAssertFalse(CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid("-1.25"))
        XCTAssertFalse(CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid("inf"))
    }
}
