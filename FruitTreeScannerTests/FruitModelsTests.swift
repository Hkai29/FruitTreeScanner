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
    }

    func testPLYParserResultJSONCompanion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T003_20250601_120000_lat25.0_lon121.0.ply")
        let jsonURL = tempDir.appendingPathComponent("T003_20250601_120000_lat25.0_lon121.0_result.json")
        let jsonContent = """
        {"fruitCount": 25, "yieldKg": 8.75, "fruitType": "orange"}
        """
        try Data().write(to: plyURL)
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.fruitCount, 25)
        XCTAssertEqual(parsed.yieldKg, 8.75, accuracy: 0.01)
        XCTAssertEqual(parsed.fruitType, "orange")
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
}
