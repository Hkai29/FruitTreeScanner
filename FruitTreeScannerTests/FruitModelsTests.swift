import XCTest
import Combine
import SceneKit
import SwiftUI
import UIKit
@testable import FruitTreeScanner

final class FruitModelsTests: XCTestCase {

    func testFruitCategorySuggestionRequiresStableDominantFrames() {
        let stableApple = (0..<3).map { offset in
            DetectedFruit(
                category: .apple,
                boundingBox: .zero,
                confidence: 0.9,
                timestamp: TimeInterval(offset)
            )
        }
        let suggestion = FruitCategoryVerification.suggestion(from: stableApple)

        XCTAssertEqual(suggestion?.category, .apple)
        XCTAssertEqual(suggestion?.supportingFrameCount, 3)
        XCTAssertNil(FruitCategoryVerification.suggestion(from: [stableApple[0]]))
    }

    func testFruitCategorySuggestionRejectsAmbiguousEvidence() {
        let detections = (0..<3).flatMap { offset in
            [
                DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.9, timestamp: TimeInterval(offset)),
                DetectedFruit(category: .pear, boundingBox: .zero, confidence: 0.9, timestamp: TimeInterval(offset))
            ]
        }

        XCTAssertNil(FruitCategoryVerification.suggestion(from: detections))
        XCTAssertNil(FruitCategoryVerification.mismatch(selectedCategory: .pear, detections: detections))
    }

    func testFruitCategoryMismatchDoesNotChangeSelectedCategory() {
        let detections = (0..<3).map { offset in
            DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.9, timestamp: TimeInterval(offset))
        }

        let mismatch = FruitCategoryVerification.mismatch(selectedCategory: .pear, detections: detections)
        XCTAssertEqual(mismatch?.selectedCategory, .pear)
        XCTAssertEqual(mismatch?.dominantDetectedCategory, .apple)
    }

    func testSupportedFruitDisplayNamesAreLocalizedAndNonEmpty() {
        for category in FruitCategory.scanSupportedCategories {
            let name = L10n.Fruit.name(for: category)
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotEqual(name, category.rawValue)
        }
    }

    func testLocalizedMismatchMessageUsesDisplayNamesInsteadOfRawValues() {
        let message = L10n.FruitCategoryVerification.mismatchMessage(
            selected: .pear,
            detected: .apple
        )

        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains(FruitCategory.pear.rawValue))
        XCTAssertFalse(message.contains(FruitCategory.apple.rawValue))
        XCTAssertFalse(L10n.FruitCategoryVerification.switchAccessibilityHint(to: .apple).isEmpty)
    }

    func testHistoryFilterLayoutPolicyStacksAccessibilitySizesAndKeepsMinimumTarget() {
        let standard = ScanHistoryFilterLayoutPolicy(isAccessibilitySize: false)
        XCTAssertEqual(standard.arrangement, .horizontal)
        XCTAssertEqual(standard.minimumControlHeight, Design.Touch.minimumHeight)

        let accessibility = ScanHistoryFilterLayoutPolicy(isAccessibilitySize: true)
        XCTAssertEqual(accessibility.arrangement, .vertical)
        XCTAssertEqual(accessibility.minimumControlHeight, Design.Touch.minimumHeight)
    }

    func testHistoryStatusLocalizationMappingIsIndependentFromPersistedRawValues() {
        XCTAssertEqual(
            ScanStatus.allCases.map(L10n.History.statusLocalizationKey(for:)),
            [
                "history.filter.status.not_scanned",
                "history.filter.status.scanned",
                "history.filter.status.reviewing",
                "history.filter.status.completed"
            ]
        )

        XCTAssertEqual(ScanStatus.allCases.map(\.rawValue), ["未扫描", "已扫描", "复查中", "已完成"])
    }

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

    func testRGBToLabSeparatesRedFruitFromGreenLeaf() {
        let redAppleLab = FruitCategory.rgbToLab(SIMD3<Float>(0.85, 0.20, 0.08))
        let leafLab = FruitCategory.rgbToLab(SIMD3<Float>(0.32, 0.45, 0.18))

        XCTAssertGreaterThan(redAppleLab.y, 0, "红果在 Lab a 通道应偏红")
        XCTAssertLessThan(leafLab.y, 0, "绿叶在 Lab a 通道应偏绿")
        XCTAssertGreaterThan(redAppleLab.y - leafLab.y, 50, "Lab 色度应能明显拉开红果与绿叶")
    }

    func testDefaultAppleColorFilterUsesLabGuardToRejectLeafGreen() {
        let legacyRGBOnly = ColorFilter(rMin: 0.25, gMin: 0.22, bMax: 0.42)

        XCTAssertTrue(
            legacyRGBOnly.matches(r: 0.32, g: 0.45, b: 0.18),
            "旧 RGB 盒子会把这类绿叶颜色误放进苹果候选"
        )
        XCTAssertFalse(
            FruitCategory.apple.colorFilter.matches(r: 0.32, g: 0.45, b: 0.18),
            "默认苹果过滤应通过 Lab 色度护栏拒绝绿叶"
        )
        XCTAssertTrue(
            FruitCategory.apple.colorFilter.matches(r: 0.85, g: 0.25, b: 0.08),
            "默认苹果过滤仍应保留成熟红果"
        )
        XCTAssertTrue(
            FruitCategory.apple.colorFilter.description.contains("Lab"),
            "结果诊断应能说明本次启用了 Lab 色度过滤"
        )
    }

    func testSettingsHSVNormalizationClampsRanges() {
        XCTAssertEqual(SettingsStore.normalizedHue(-20, fallback: 330), 0)
        XCTAssertEqual(SettingsStore.normalizedHue(420, fallback: 330), 360)
        XCTAssertEqual(SettingsStore.normalizedUnit(-0.5, fallback: 0.3), 0)
        XCTAssertEqual(SettingsStore.normalizedUnit(1.5, fallback: 0.3), 1)
    }

    func testSettingsHSVNormalizationRejectsNonFiniteValues() {
        XCTAssertEqual(SettingsStore.normalizedHue(.nan, fallback: 330), 330)
        XCTAssertEqual(SettingsStore.normalizedHue(.infinity, fallback: 25), 25)
        XCTAssertEqual(SettingsStore.normalizedUnit(.nan, fallback: 0.3), 0.3)
        XCTAssertEqual(SettingsStore.normalizedUnit(-.infinity, fallback: 0.4), 0.4)
    }

    func testSettingsCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "settings.title": "Settings",
                "settings.section.device": "Device",
                "settings.camera_settings": "Camera Settings",
                "settings.camera_settings_subtitle": "Resolution and capture frame rate",
                "settings.actual_resolution": "Actual Resolution",
                "settings.section.data": "Data",
                "settings.auto_export_csv": "Auto Export After Scan",
                "settings.auto_export_csv_hint": "Automatically exports a CSV file when a scan completes.",
                "settings.section.scan": "Scanning",
                "settings.current_fruit_type": "Current Fruit Type",
                "settings.fruit_type_hint": "Used for image detection, point-cloud clustering, and yield conversion.",
                "settings.variety_database": "Variety Parameters",
                "settings.variety_database_subtitle": "Edit size, weight, and clustering parameters for the current fruit",
                "settings.scan_quality": "Quality Preset",
                "settings.quality.high": "High",
                "settings.quality.medium": "Medium",
                "settings.quality.low": "Low",
                "settings.quality_hint": "High quality raises the depth-confidence threshold. The point cloud is cleaner, but low light or fast motion may require another pass.",
                "settings.max_points": "Maximum Points",
                "settings.max_points_hint": "More points retain more detail, but use more memory and increase export size and processing time.",
                "settings.precision": "Precision",
                "settings.precision_hint": "A smaller value reduces the voxel-sampling interval for fine branches and small fruit, but analysis takes longer.",
                "settings.target_resolution": "Target Resolution",
                "settings.capture_frame_rate": "Capture Frame Rate",
                "settings.camera_format_hint": "ARKit chooses the closest supported camera format for the target resolution and frame rate. Actual results depend on device capability and system load.",
                "settings.max_points_value": "%@ pts",
                "settings.centimeters_value": "%@ cm",
                "settings.section_expanded": "Expanded",
                "settings.section_collapsed": "Collapsed",
                "settings.section_toggle_hint": "Double-tap to expand or collapse this section."
            ],
            "zh": [
                "settings.title": "设置",
                "settings.section.device": "设备",
                "settings.camera_settings": "相机设置",
                "settings.camera_settings_subtitle": "分辨率与采集帧率",
                "settings.actual_resolution": "实际分辨率",
                "settings.section.data": "数据",
                "settings.auto_export_csv": "扫描后自动导出",
                "settings.auto_export_csv_hint": "扫描完成后自动导出 CSV 文件。",
                "settings.section.scan": "扫描",
                "settings.current_fruit_type": "当前水果类型",
                "settings.fruit_type_hint": "用于图像检测、点云聚类与产量换算。",
                "settings.variety_database": "品种参数库",
                "settings.variety_database_subtitle": "编辑当前水果的尺寸、重量与聚类参数",
                "settings.scan_quality": "质量预设",
                "settings.quality.high": "高",
                "settings.quality.medium": "中",
                "settings.quality.low": "低",
                "settings.quality_hint": "高质量会提高深度置信度门槛，点云更干净，但弱光或快速移动时可能需要补扫。",
                "settings.max_points": "最大点数",
                "settings.max_points_hint": "更多点能保留更多细节，但会增加内存占用、导出文件大小和结果计算时间。",
                "settings.precision": "精度",
                "settings.precision_hint": "更小的值会减少体素采样间隔，适合细枝和小果，但分析时间更长。",
                "settings.target_resolution": "目标分辨率",
                "settings.capture_frame_rate": "采集帧率",
                "settings.camera_format_hint": "ARKit 会为目标分辨率和帧率选择最接近的可用相机格式；实际结果取决于设备能力和系统负载。",
                "settings.max_points_value": "%@ 点",
                "settings.centimeters_value": "%@ cm",
                "settings.section_expanded": "已展开",
                "settings.section_collapsed": "已折叠",
                "settings.section_toggle_hint": "轻点两下即可展开或折叠此分区。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testSettingsQualityPresetIdentifiersRemainStableWhileDisplayNamesAreLocalized() {
        XCTAssertEqual(
            SettingsStore.qualityPresetOptions,
            ["高", "中", "低"],
            "Persisted algorithm identifiers must remain unchanged"
        )
        XCTAssertEqual(L10n.Settings.qualityPresetName(for: "高"), L10n.Settings.qualityHigh)
        XCTAssertEqual(L10n.Settings.qualityPresetName(for: "中"), L10n.Settings.qualityMedium)
        XCTAssertEqual(L10n.Settings.qualityPresetName(for: "低"), L10n.Settings.qualityLow)
        XCTAssertEqual(
            L10n.Settings.qualityPresetName(for: "future-value"),
            "future-value",
            "Unknown future identifiers must remain visible instead of becoming blank"
        )
    }

    func testSettingsDynamicValuesPreserveTheUnderlyingMeasurements() {
        let pointCount = L10n.Settings.maxPointCountValue(1_200_000)
        let precision = L10n.Settings.precisionValue(1.2)

        XCTAssertEqual(pointCount.filter(\.isNumber), "1200000")
        XCTAssertEqual(precision.filter(\.isNumber), "12")
    }

    func testSettingsStorePublishesFruitTypeChanges() {
        let suiteName = "FruitModelsTests.SettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)
        var publicationCount = 0
        let cancellable = settings.objectWillChange.sink {
            publicationCount += 1
        }
        defer {
            cancellable.cancel()
            defaults.removePersistentDomain(forName: suiteName)
        }

        settings.fruitType = FruitCategory.pear.rawValue

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(settings.fruitType, FruitCategory.pear.rawValue)
        XCTAssertEqual(defaults.string(forKey: SettingsStoreKey.fruitType), FruitCategory.pear.rawValue)
    }

    func testSettingsStoreDoesNotPublishUnchangedFruitType() {
        let suiteName = "FruitModelsTests.SettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(FruitCategory.apple.rawValue, forKey: SettingsStoreKey.fruitType)
        let settings = SettingsStore(defaults: defaults)
        var publicationCount = 0
        let cancellable = settings.objectWillChange.sink {
            publicationCount += 1
        }
        defer {
            cancellable.cancel()
            defaults.removePersistentDomain(forName: suiteName)
        }

        settings.fruitType = FruitCategory.apple.rawValue

        XCTAssertEqual(publicationCount, 0)
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

    func testFruitCategoryMapperNormalizesCaseWhitespaceUnderscoresAndHyphens() {
        let mapper = FruitCategoryMapper.standard

        XCTAssertEqual(mapper.category(for: " APPLE "), .apple)
        XCTAssertEqual(mapper.category(for: "kiwi_fruit"), .kiwi)
        XCTAssertEqual(mapper.category(for: "mandarin-orange"), .mandarin)
        XCTAssertEqual(mapper.category(for: "bay berry"), .bayberry)
    }

    func testFruitCategoryMapperReturnsNilForUnknownLabel() {
        XCTAssertNil(FruitCategoryMapper.standard.category(for: "dragon fruit"))
    }

    func testFruitCategoryMapperRuntimeLabelsDoNotTreatClassIDsAsFruitNames() {
        let mapper = FruitCategoryMapper.standard

        XCTAssertEqual(mapper.category(forRuntimeModelLabel: "apple"), .apple)
        XCTAssertNil(mapper.category(forRuntimeModelLabel: "0"))
    }

    func testFruitCategoryMapperDoesNotMapBananaToPear() {
        XCTAssertNil(FruitCategoryMapper.standard.category(for: "banana"))
        XCTAssertNil(FruitCategory.fromCOCO(52))
    }

    func testCustomModelOrderMatchesFruitCategoryCases() {
        XCTAssertEqual(FruitCategory.customModelLabelOrder, FruitCategory.allCases.map(\.rawValue))
        for (index, category) in FruitCategory.allCases.enumerated() {
            XCTAssertEqual(FruitCategory.fromCustomModel(index), category)
        }
        XCTAssertNil(FruitCategory.fromCustomModel(FruitCategory.allCases.count))
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
        XCTAssertEqual(counter.weightedTotal(fruits), 0.85, accuracy: 0.001)
    }

    func testWeightedFruitTotalUsesConfidenceEvidence() {
        let counter = FruitCounter()
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 0), confidence: 0.55, source: .fused),
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0.1, 0, 0), confidence: 0.8, source: .trackedImage),
        ]

        XCTAssertEqual(counter.weightedTotal(fruits), 1.15, accuracy: 0.001)
    }

    func testFruitCountUsesConfidenceEvidenceWeights() {
        let counter = FruitCounter()
        let fruits = [
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, 0), confidence: 0.4, source: .imageOnly),
            ValidatedFruit(category: .orange, position: SIMD3<Float>(0.1, 0, 0), confidence: 0.95, source: .fused),
        ]

        let result = counter.count(fruits)

        XCTAssertEqual(result.fruitCounts["apple"], 0, "低置信单帧视觉证据不应被整数计数抬成 1")
        XCTAssertEqual(result.fruitCounts["orange"], 1, "高置信 fused 证据仍应计入整数数量")
        XCTAssertEqual(result.totalCount, 1)
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
        XCTAssertEqual(parsed.fruitType, "")
        XCTAssertEqual(parsed.persistenceState, .incomplete)
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

    func testPLYParserRejectsNonFiniteGPSMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let headerURL = tempDir.appendingPathComponent("bad_header_gps.ply")
        try """
        ply
        format ascii 1.0
        comment tree_id Bad_GPS
        comment gps_lat nan
        comment gps_lon inf
        end_header
        """.write(to: headerURL, atomically: true, encoding: .utf8)

        let headerParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: headerURL))
        XCTAssertEqual(headerParsed.gpsLat, 0)
        XCTAssertEqual(headerParsed.gpsLon, 0)

        let filenameURL = tempDir.appendingPathComponent("BadGPS_20240506_123456_latnan_loninf.ply")
        try Data().write(to: filenameURL)

        let filenameParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: filenameURL))
        XCTAssertEqual(filenameParsed.gpsLat, 0)
        XCTAssertEqual(filenameParsed.gpsLon, 0)
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

    func testPLYParserWithoutCompanionIsIncompleteAndHasNoDefaultFruit() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("T002_20250301_080000_lat30.0_lon120.0.ply")
        try Data().write(to: plyURL)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
        XCTAssertEqual(parsed.fruitType, "")
        XCTAssertEqual(parsed.confidence, "")
        XCTAssertEqual(parsed.persistenceState, .incomplete)
        XCTAssertEqual(parsed.persistenceFailureReason, "orphanPLYDetected")
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
        XCTAssertEqual(parsed.persistenceState, .complete)
    }

    func testPLYParserRejectsRevisionedJSONWithoutCompletionManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("partial_json.ply")
        let jsonURL = tempDir.appendingPathComponent("partial_json_result.json")
        try Data().write(to: plyURL)
        try """
        {"fruitCount": 25, "yieldKg": 8.75, "fruitType": "orange", "confidence": "high", "exportRevision": "v1-partial"}
        """.write(to: jsonURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .invalid)
        XCTAssertEqual(parsed.persistenceFailureReason, "scanResultManifestMissing")
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
        XCTAssertEqual(parsed.fruitType, "")
        XCTAssertEqual(parsed.confidence, "")
    }

    func testPLYParserRejectsRevisionedCSVWithoutCompletionManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("partial_csv.ply")
        let csvURL = tempDir.appendingPathComponent("partial_csv.csv")
        try Data().write(to: plyURL)
        try """
        水果类型,果实数量,产量(kg),置信度,ExportRevision
        orange,25,8.75,high,v1-partial
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .invalid)
        XCTAssertEqual(parsed.persistenceFailureReason, "scanResultManifestMissing")
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
        XCTAssertEqual(parsed.fruitType, "")
        XCTAssertEqual(parsed.confidence, "")
    }

    func testPLYParserRejectsNonFiniteCompanionYield() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvPLYURL = tempDir.appendingPathComponent("CSVBadYield_20250601_120000_lat25.0_lon121.0.ply")
        let csvURL = csvPLYURL.deletingPathExtension().appendingPathExtension("csv")
        try Data().write(to: csvPLYURL)
        try """
        树编号,水果类型,扫描日期,果实数量,产量(kg)
        CSVBadYield,apple,2025-06-01 12:00:00,12,nan
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let csvParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: csvPLYURL))
        XCTAssertEqual(csvParsed.fruitCount, 0)
        XCTAssertEqual(csvParsed.yieldKg, 0)
        XCTAssertEqual(csvParsed.persistenceState, .invalid)

        let jsonPLYURL = tempDir.appendingPathComponent("JSONBadYield_20250601_120000_lat25.0_lon121.0.ply")
        let jsonURL = tempDir.appendingPathComponent("JSONBadYield_20250601_120000_lat25.0_lon121.0_result.json")
        try Data().write(to: jsonPLYURL)
        try """
        {"fruitCount": 25, "yieldKg": "inf", "fruitType": "orange", "confidence": "high"}
        """.write(to: jsonURL, atomically: true, encoding: .utf8)

        let jsonParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: jsonPLYURL))
        XCTAssertEqual(jsonParsed.fruitCount, 0)
        XCTAssertEqual(jsonParsed.yieldKg, 0)
        XCTAssertEqual(jsonParsed.persistenceState, .invalid)
    }

    func testPLYParserRejectsNegativeCompanionCountAndYield() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvPLYURL = tempDir.appendingPathComponent("CSVNegativeYield_20250601_120000_lat25.0_lon121.0.ply")
        let csvURL = csvPLYURL.deletingPathExtension().appendingPathExtension("csv")
        try Data().write(to: csvPLYURL)
        try """
        树编号,水果类型,扫描日期,果实数量,产量(kg)
        CSVNegativeYield,apple,2025-06-01 12:00:00,-12,-3.5
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let csvParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: csvPLYURL))
        XCTAssertEqual(csvParsed.fruitCount, 0)
        XCTAssertEqual(csvParsed.yieldKg, 0)

        let jsonPLYURL = tempDir.appendingPathComponent("JSONNegativeYield_20250601_120000_lat25.0_lon121.0.ply")
        let jsonURL = tempDir.appendingPathComponent("JSONNegativeYield_20250601_120000_lat25.0_lon121.0_result.json")
        try Data().write(to: jsonPLYURL)
        try """
        {"fruitCount": -25, "yieldKg": -8.0, "fruitType": "orange", "confidence": "medium"}
        """.write(to: jsonURL, atomically: true, encoding: .utf8)

        let jsonParsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: jsonPLYURL))
        XCTAssertEqual(jsonParsed.fruitCount, 0)
        XCTAssertEqual(jsonParsed.yieldKg, 0)
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

    func testPLYParserRejectsOversizedLegacyCSVBeforeParsing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("oversized-legacy.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")
        try Data().write(to: plyURL)
        let validPrefix = """
        树编号,水果类型,扫描日期,果实数量,产量(kg),GPS纬度,GPS经度
        T001,apple,2024-05-06 12:34:56,12,3.50,22.1234,114.5678

        """
        let oversizedCSV = validPrefix + String(repeating: "x", count: 1_048_576)
        try oversizedCSV.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .invalid)
        XCTAssertEqual(parsed.persistenceFailureReason, "scanResultCSVFailed")
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
    }

    func testPLYParserRejectsOversizedLegacyJSONBeforeParsing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("oversized-legacy-json.ply")
        let jsonURL = tempDir.appendingPathComponent("oversized-legacy-json_result.json")
        try Data().write(to: plyURL)
        try Data(
            #"{"fruitCount":12,"yieldKg":3.5,"fruitType":"apple","confidence":"high","padding":""#.utf8
        ).write(to: jsonURL)
        do {
            let handle = try FileHandle(forWritingTo: jsonURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let chunk = Data(repeating: 0x78, count: 64 * 1_024)
            var remainingByteCount = PLYParserHelper.maximumCompanionMetadataByteCount + 1
            while remainingByteCount > 0 {
                let writeByteCount = min(chunk.count, remainingByteCount)
                try handle.write(contentsOf: chunk.prefix(writeByteCount))
                remainingByteCount -= writeByteCount
            }
            try handle.write(contentsOf: Data(#""}"#.utf8))
        }

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .invalid)
        XCTAssertEqual(parsed.persistenceFailureReason, "scanResultJSONFailed")
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
    }

    func testCompanionBoundedReaderAcceptsLimitAndRejectsOneExtraByte() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("bounded.data")

        try Data(repeating: 0x61, count: 32).write(to: fileURL)
        XCTAssertEqual(
            PLYParserHelper.readBoundedCompanionData(
                at: fileURL,
                maximumByteCount: 32
            )?.count,
            32
        )

        try Data(repeating: 0x61, count: 33).write(to: fileURL)
        XCTAssertNil(
            PLYParserHelper.readBoundedCompanionData(
                at: fileURL,
                maximumByteCount: 32
            )
        )
    }

    func testPLYParserRejectsOversizedTransactionalManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("oversized-manifest.ply")
        let metadataURL = tempDir.appendingPathComponent("oversized-manifest_result.json")
        let manifestURL = tempDir.appendingPathComponent("oversized-manifest_complete.json")
        let revision = "v1-test"
        try Data().write(to: plyURL)
        try JSONSerialization.data(withJSONObject: [
            "fruitCount": 12,
            "yieldKg": 3.5,
            "fruitType": "apple",
            "confidence": "high",
            "exportRevision": revision
        ]).write(to: metadataURL)
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "exportRevision": revision,
            "requiredFiles": [metadataURL.lastPathComponent],
            "padding": String(
                repeating: "x",
                count: PLYParserHelper.maximumCompanionManifestByteCount
            )
        ]).write(to: manifestURL)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .invalid)
        XCTAssertEqual(parsed.persistenceFailureReason, "scanResultRevisionMismatch")
        XCTAssertEqual(parsed.fruitCount, 0)
        XCTAssertEqual(parsed.yieldKg, 0)
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

    func testPLYParserPreservesQuotedEmbeddedCRLFInCompanionCSV() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("quoted-crlf.ply")
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")
        try Data().write(to: plyURL)
        try "水果类型,果实数量,产量(kg),置信度\r\n\"orange,\r\npremium\",31,8.75,high\r\n"
            .write(to: csvURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(PLYParserHelper.parsePLYFile(at: plyURL))

        XCTAssertEqual(parsed.persistenceState, .complete)
        XCTAssertEqual(parsed.fruitCount, 31)
        XCTAssertEqual(parsed.yieldKg, 8.75, accuracy: 0.001)
        XCTAssertEqual(parsed.fruitType, "orange,\npremium")
        XCTAssertEqual(parsed.confidence, "high")
    }

    func testScanFileRecordNormalizesInvalidNumericFields() {
        let negativeRecord = ScanFileRecord(
            id: "bad-record.ply",
            treeID: "T-bad",
            fileURL: URL(fileURLWithPath: "/tmp/bad-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            fruitCount: -7,
            yieldKg: -1.25
        )

        XCTAssertEqual(negativeRecord.fruitCount, 0)
        XCTAssertEqual(negativeRecord.yieldKg, 0)

        let nonFiniteRecord = ScanFileRecord(
            id: "non-finite-record.ply",
            treeID: "T-non-finite",
            fileURL: URL(fileURLWithPath: "/tmp/non-finite-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            fruitCount: 7,
            yieldKg: .nan,
            gpsLat: .infinity,
            gpsLon: -.infinity
        )

        XCTAssertEqual(nonFiniteRecord.fruitCount, 7)
        XCTAssertEqual(nonFiniteRecord.yieldKg, 0)
        XCTAssertEqual(nonFiniteRecord.gpsLat, 0)
        XCTAssertEqual(nonFiniteRecord.gpsLon, 0)

        let outOfRangeRecord = ScanFileRecord(
            id: "out-of-range-record.ply",
            treeID: "T-out-of-range",
            fileURL: URL(fileURLWithPath: "/tmp/out-of-range-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 90.1,
            gpsLon: -180.1
        )

        XCTAssertEqual(outOfRangeRecord.gpsLat, 0)
        XCTAssertEqual(outOfRangeRecord.gpsLon, 0)

        let partiallyInvalidRecord = ScanFileRecord(
            id: "partially-invalid-record.ply",
            treeID: "T-partially-invalid",
            fileURL: URL(fileURLWithPath: "/tmp/partially-invalid-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 91,
            gpsLon: 121.4737
        )

        XCTAssertEqual(partiallyInvalidRecord.gpsLat, 0)
        XCTAssertEqual(partiallyInvalidRecord.gpsLon, 0)
    }

    func testScanFileRecordPreservesValidNegativeGPSCoordinates() {
        let record = ScanFileRecord(
            id: "southern-western.ply",
            treeID: "T-gps",
            fileURL: URL(fileURLWithPath: "/tmp/southern-western.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            fruitCount: 4,
            yieldKg: 1.25,
            gpsLat: -33.8688,
            gpsLon: -70.6693
        )

        XCTAssertEqual(record.fruitCount, 4)
        XCTAssertEqual(record.yieldKg, 1.25, accuracy: 0.0001)
        XCTAssertEqual(record.gpsLat, -33.8688, accuracy: 0.000001)
        XCTAssertEqual(record.gpsLon, -70.6693, accuracy: 0.000001)

        let boundaryRecord = ScanFileRecord(
            id: "gps-boundary.ply",
            treeID: "T-boundary",
            fileURL: URL(fileURLWithPath: "/tmp/gps-boundary.ply"),
            scanDate: Date(timeIntervalSince1970: 1717200000),
            gpsLat: 90,
            gpsLon: 180
        )

        XCTAssertEqual(boundaryRecord.gpsLat, 90, accuracy: 0.000001)
        XCTAssertEqual(boundaryRecord.gpsLon, 180, accuracy: 0.000001)
    }

    @MainActor
    func testBatchExportRecordRowsRenderAtSupportedTextSizes() {
        let scanDate = Date(timeIntervalSince1970: 1_786_230_000)
        let completeRecord = ScanFileRecord(
            id: "complete-batch-row.ply",
            treeID: "NORTH-ORCHARD-TREE-2026-08-09-A",
            fileURL: URL(fileURLWithPath: "/tmp/complete-batch-row.ply"),
            scanDate: scanDate,
            fruitCount: 123,
            yieldKg: 45.6,
            gpsLat: 36.12,
            gpsLon: 139.65,
            fruitType: "apple",
            persistenceState: .complete
        )
        let invalidRecord = ScanFileRecord(
            id: "invalid-batch-row.ply",
            treeID: "SOUTH-BLOCK-TREE-B",
            fileURL: URL(fileURLWithPath: "/tmp/invalid-batch-row.ply"),
            scanDate: scanDate,
            fruitType: "pear",
            persistenceState: .invalid
        )
        let rows: [(name: String, dynamicTypeSize: DynamicTypeSize, view: AnyView)] = [
            (
                "Selected-AX5",
                .accessibility5,
                AnyView(
                    BatchExportRecordRow(
                        record: completeRecord,
                        isExportable: true,
                        isSelected: true,
                        onToggle: {}
                    )
                )
            ),
            (
                "Invalid-AX5",
                .accessibility5,
                AnyView(
                    BatchExportRecordRow(
                        record: invalidRecord,
                        isExportable: false,
                        isSelected: false,
                        onToggle: {}
                    )
                )
            ),
            (
                "Selected-Standard",
                .large,
                AnyView(
                    BatchExportRecordRow(
                        record: completeRecord,
                        isExportable: true,
                        isSelected: true,
                        onToggle: {}
                    )
                )
            )
        ]

        for row in rows {
            let rootView = VStack {
                row.view
                Spacer(minLength: 0)
            }
            .padding(Design.Space.md)
            .environment(\.dynamicTypeSize, row.dynamicTypeSize)
            .frame(width: 390, height: 844, alignment: .top)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportRecordRow-\(row.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    func testBatchExportRecordCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "batch_export.record.fruit_count_one": "%d fruit",
                "batch_export.record.fruit_count_other": "%d fruits",
                "batch_export.record.yield_format": "%.1f kg",
                "batch_export.record.unavailable.incomplete": "This record was not saved completely and can’t be exported",
                "batch_export.record.unavailable.invalid": "This record contains invalid data and can’t be exported",
                "batch_export.record.accessibility.label": "%@, %@, %@",
                "batch_export.record.accessibility.selected": "Selected, exportable",
                "batch_export.record.accessibility.not_selected": "Not selected, exportable",
                "batch_export.record.accessibility.toggle_hint": "Double-tap to toggle selection"
            ],
            "zh": [
                "batch_export.record.fruit_count_one": "%d 个果实",
                "batch_export.record.fruit_count_other": "%d 个果实",
                "batch_export.record.yield_format": "%.1f kg",
                "batch_export.record.unavailable.incomplete": "记录未完整保存，无法导出",
                "batch_export.record.unavailable.invalid": "记录数据无效，无法导出",
                "batch_export.record.accessibility.label": "%@，%@，%@",
                "batch_export.record.accessibility.selected": "已选择，可导出",
                "batch_export.record.accessibility.not_selected": "未选择，可导出",
                "batch_export.record.accessibility.toggle_hint": "双击切换选择状态"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }

        let englishBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let chineseBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "zh", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        XCTAssertEqual(
            L10n.BatchExport.recordAccessibilityLabel(
                treeID: "TREE-17",
                fruitCount: 2,
                yieldKg: 1.5,
                in: englishBundle
            ),
            "TREE-17, 2 fruits, 1.5 kg"
        )
        XCTAssertEqual(
            L10n.BatchExport.recordAccessibilityValue(
                isExportable: false,
                isSelected: false,
                persistenceState: .invalid,
                in: chineseBundle
            ),
            "记录数据无效，无法导出"
        )
        XCTAssertEqual(L10n.BatchExport.fruitTypeLabel("apple", in: englishBundle), "Apple")
        XCTAssertEqual(L10n.BatchExport.fruitTypeLabel("apple", in: chineseBundle), "苹果")
        XCTAssertEqual(
            L10n.BatchExport.fruitTypeLabel("custom-orchard-fruit", in: chineseBundle),
            "custom-orchard-fruit",
            "Unknown persisted identifiers must remain unchanged"
        )
    }

    func testHistoryPresentationTreatsCompleteZeroAsReliableResult() {
        let presentation = ScanHistoryRecordPresentation(
            record: makeHistoryRecord(
                fruitCount: 0,
                yieldKg: 0,
                persistenceState: .complete
            )
        )

        XCTAssertEqual(presentation.integrity, .complete)
        XCTAssertEqual(presentation.detail, .none)
        XCTAssertEqual(presentation.fruitCount, 0)
        XCTAssertEqual(presentation.yieldKg, 0)
        XCTAssertTrue(presentation.hasReliableResult)
        XCTAssertFalse(presentation.showsRecoveryAction)
    }

    func testHistoryPresentationHidesMetricsForOrphanPLYAndOffersRecovery() {
        let presentation = ScanHistoryRecordPresentation(
            record: makeHistoryRecord(
                fruitCount: 99,
                yieldKg: 42.5,
                persistenceState: .incomplete,
                persistenceFailureReason: "orphanPLYDetected"
            )
        )

        XCTAssertEqual(presentation.integrity, .incomplete)
        XCTAssertEqual(presentation.detail, .missingResult)
        XCTAssertNil(presentation.fruitCount)
        XCTAssertNil(presentation.yieldKg)
        XCTAssertFalse(presentation.hasReliableResult)
        XCTAssertTrue(presentation.showsRecoveryAction)
    }

    func testHistoryPresentationMapsKnownInvalidCompanionFailures() {
        let expectedDetails: [(String, ScanHistoryRecordPresentation.Detail)] = [
            ("scanResultJSONFailed", .unreadableJSON),
            ("scanResultCSVFailed", .unreadableCSV),
            ("scanResultRevisionMismatch", .revisionMismatch)
        ]

        for (reason, expectedDetail) in expectedDetails {
            let presentation = ScanHistoryRecordPresentation(
                record: makeHistoryRecord(
                    fruitCount: 88,
                    yieldKg: 31,
                    persistenceState: .invalid,
                    persistenceFailureReason: reason
                )
            )

            XCTAssertEqual(presentation.integrity, .invalid)
            XCTAssertEqual(presentation.detail, expectedDetail)
            XCTAssertNil(presentation.fruitCount)
            XCTAssertNil(presentation.yieldKg)
            XCTAssertTrue(presentation.showsRecoveryAction)
        }
    }

    func testHistoryPresentationUsesConservativeInvalidFallbackForUnknownReason() {
        let presentation = ScanHistoryRecordPresentation(
            record: makeHistoryRecord(
                persistenceState: .invalid,
                persistenceFailureReason: "futureInvalidReason"
            )
        )

        XCTAssertEqual(presentation.integrity, .invalid)
        XCTAssertEqual(presentation.detail, .invalidUnknown)
        XCTAssertFalse(presentation.hasReliableResult)
        XCTAssertTrue(presentation.showsRecoveryAction)
    }

    func testHistoryPresentationUsesConservativeIncompleteFallbackForUnknownReason() {
        let presentation = ScanHistoryRecordPresentation(
            record: makeHistoryRecord(
                persistenceState: .incomplete,
                persistenceFailureReason: "futureIncompleteReason"
            )
        )

        XCTAssertEqual(presentation.integrity, .incomplete)
        XCTAssertEqual(presentation.detail, .incompleteUnknown)
        XCTAssertFalse(presentation.hasReliableResult)
        XCTAssertTrue(presentation.showsRecoveryAction)
    }

    func testHistoryPresentationUsesPersistenceStateAsAuthority() {
        let presentation = ScanHistoryRecordPresentation(
            record: makeHistoryRecord(
                fruitCount: 7,
                yieldKg: 2.5,
                persistenceState: .complete,
                persistenceFailureReason: "scanResultJSONFailed"
            )
        )

        XCTAssertEqual(presentation.integrity, .complete)
        XCTAssertEqual(presentation.detail, .none)
        XCTAssertEqual(presentation.fruitCount, 7)
        XCTAssertEqual(presentation.yieldKg, 2.5)
        XCTAssertFalse(presentation.showsRecoveryAction)
    }

    func testHistoryStatusVisualPolicyReservesSemanticColorForNonTextAccents() {
        let policy = ScanHistoryStatusVisualPolicy()

        XCTAssertEqual(policy.symbolForeground, .semanticAccent)
        XCTAssertEqual(policy.titleForeground, .primaryText)
        XCTAssertEqual(policy.recoverySymbolForeground, .semanticAccent)
        XCTAssertEqual(policy.recoveryTextForeground, .primaryText)
    }

    private func makeHistoryRecord(
        fruitCount: Int = 0,
        yieldKg: Float = 0,
        persistenceState: ScanPersistenceState,
        persistenceFailureReason: String? = nil
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: "history-presentation.ply",
            treeID: "T-history",
            fileURL: URL(fileURLWithPath: "/tmp/history-presentation.ply"),
            scanDate: Date(timeIntervalSince1970: 1_717_200_000),
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            persistenceState: persistenceState,
            persistenceFailureReason: persistenceFailureReason
        )
    }

    func testImportFileErrorClassifierRecognizesUserCancellation() {
        let cocoaCancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        let urlCancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        XCTAssertTrue(ImportFileErrorClassifier.isUserCancellation(cocoaCancellation))
        XCTAssertTrue(ImportFileErrorClassifier.isUserCancellation(urlCancellation))
    }

    func testImportFileErrorClassifierDoesNotHideRealErrors() {
        let parseError = PLYImportService.ImportError.invalidPLY
        let fileError = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue)

        XCTAssertFalse(ImportFileErrorClassifier.isUserCancellation(parseError))
        XCTAssertFalse(ImportFileErrorClassifier.isUserCancellation(fileError))
    }

    func testImportFileCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "import.navigation_title": "Import File",
                "import.header_title": "Point Cloud Import",
                "import.header_subtitle": "Add a PLY point cloud for viewing, comparison, and export.",
                "import.status.idle_title": "Choose a PLY File",
                "import.status.idle_message": "ASCII and binary PLY files are supported. Imported files are added to Scan History.",
                "import.status.selecting_title": "Choose a File",
                "import.status.selecting_message": "Choose one .ply point-cloud file from Files.",
                "import.status.processing_title": "Processing",
                "import.status.success_title": "Import Complete",
                "import.status.success_message": "%@ was added to Scan History. Import another file or close this page.",
                "import.status.error_title": "Import Failed",
                "import.button.select": "Choose PLY File",
                "import.button.continue": "Import Another PLY File",
                "import.rule.history": "Imported files appear in Scan History",
                "import.rule.metadata": "Readable scan metadata is preserved",
                "import.rule.duplicate": "Duplicate names create a new copy",
                "import.error.no_file": "No file was selected",
                "import.error.unsupported_format": "Only PLY point-cloud files are supported",
                "import.error.invalid_ply": "The file is not a valid PLY point cloud",
                "import.error.invalid_point_cloud": "The PLY point-cloud data is incomplete or cannot be read"
            ],
            "zh": [
                "import.navigation_title": "导入文件",
                "import.header_title": "点云导入",
                "import.header_subtitle": "把已有 PLY 点云加入扫描记录，用于查看、对比和后续导出。",
                "import.status.idle_title": "等待选择 PLY 文件",
                "import.status.idle_message": "支持 ASCII 和 Binary PLY，导入后会写入本机扫描记录。",
                "import.status.selecting_title": "请选择文件",
                "import.status.selecting_message": "从文件应用中选择一个 .ply 点云文件。",
                "import.status.processing_title": "正在处理",
                "import.status.success_title": "导入成功",
                "import.status.success_message": "%@ 已添加到扫描记录，可继续导入或关闭此页。",
                "import.status.error_title": "导入失败",
                "import.button.select": "选择 PLY 文件",
                "import.button.continue": "继续导入 PLY 文件",
                "import.rule.history": "导入后会出现在扫描记录",
                "import.rule.metadata": "保留可读取的扫描元数据",
                "import.rule.duplicate": "同名文件会自动生成新副本",
                "import.error.no_file": "未选择文件",
                "import.error.unsupported_format": "当前导入记录只支持 PLY 点云文件",
                "import.error.invalid_ply": "文件不是有效的 PLY 点云",
                "import.error.invalid_point_cloud": "PLY 点云数据不完整或当前无法读取"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testImportFileFormatsSuccessAndMapsProductionErrors() {
        let successMessage = L10n.Import.successMessage(fileName: "TREE-17.ply")
        XCTAssertTrue(successMessage.contains("TREE-17.ply"))

        let expectedErrors: [(PLYImportService.ImportError, String)] = [
            (.unsupportedFormat, L10n.Import.unsupportedFormatError),
            (.invalidPLY, L10n.Import.invalidPLYError),
            (.invalidPointCloud, L10n.Import.invalidPointCloudError)
        ]

        for (error, expectedMessage) in expectedErrors {
            XCTAssertEqual(error.errorDescription, expectedMessage)
            XCTAssertEqual(error.localizedDescription, expectedMessage)
        }
    }

    func testImportStatusResetsOnlySelectingStateAfterImporterDismissal() {
        XCTAssertEqual(ImportStatus.selecting.afterImporterDismissal, .idle)
        XCTAssertEqual(ImportStatus.idle.afterImporterDismissal, .idle)
        XCTAssertEqual(ImportStatus.processing("TREE-17.ply").afterImporterDismissal, .processing("TREE-17.ply"))
        XCTAssertEqual(ImportStatus.success("TREE-17.ply").afterImporterDismissal, .success("TREE-17.ply"))
        XCTAssertEqual(ImportStatus.error("broken").afterImporterDismissal, .error("broken"))
    }

    @MainActor
    func testImportFileContentRendersAtAccessibilityTextSize() {
        let rootView = ImportFileContentView(
            status: .success("NORTH-ORCHARD-TREE-2026-08-09.ply"),
            isProcessing: false,
            onImportTap: {}
        )
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "ImportFileContent-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

    func testPointCloudPreviewCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "point_cloud.navigation_title": "Point Cloud Preview",
                "point_cloud.accessibility.close_preview": "Close point cloud preview",
                "point_cloud.empty.title": "No Scan Data",
                "point_cloud.empty.message": "Scan or import a PLY file to see point clouds here.",
                "point_cloud.action.new_scan": "New Scan",
                "point_cloud.action.import_ply": "Import PLY",
                "point_cloud.status.loading_title": "Loading Point Cloud",
                "point_cloud.status.loading_message": "Reading PLY points and color data…",
                "point_cloud.status.error_title": "Unable to Open Point Cloud",
                "point_cloud.status.no_file_title": "No Point Cloud File",
                "point_cloud.status.no_file_message": "Scan or import a PLY file to rotate, measure, and share it here.",
                "point_cloud.status.no_points_title": "No Displayable Points",
                "point_cloud.status.no_points_message": "No valid points were found. Check the PLY file.",
                "point_cloud.error.load_failed": "Unable to read the point-cloud file.",
                "point_cloud.selector.search_placeholder": "Search tree ID",
                "point_cloud.selector.no_results": "No records found for tree ID “%@”",
                "point_cloud.accessibility.clear_search": "Clear search",
                "point_cloud.viewer.title": "Point Cloud",
                "point_cloud.accessibility.share": "Share point cloud",
                "point_cloud.metric.points": "Pts",
                "point_cloud.metric.height": "H",
                "point_cloud.metric.footprint": "Crown",
                "point_cloud.accessibility.point_count": "Point count: %@",
                "point_cloud.accessibility.height": "Height: %@",
                "point_cloud.accessibility.footprint": "Crown footprint: %@",
                "point_cloud.tool.reset": "Reset",
                "point_cloud.tool.color": "Colors",
                "point_cloud.tool.zoom_in": "Zoom In",
                "point_cloud.tool.zoom_out": "Zoom Out",
                "point_cloud.tool.measure": "Measure",
                "point_cloud.legend.color_format": "Color: %@",
                "point_cloud.legend.actual_height_format": "Actual height %@",
                "point_cloud.legend.low": "Low",
                "point_cloud.legend.high": "High",
                "point_cloud.legend.sparse": "Sparse",
                "point_cloud.legend.dense": "Dense",
                "point_cloud.legend.fruit_candidates": "Fruit candidates",
                "point_cloud.legend.uniform_bright": "Uniform bright",
                "point_cloud.view.orbit": "Orbit",
                "point_cloud.view.front": "Front",
                "point_cloud.view.top": "Top",
                "point_cloud.view.side": "Side",
                "point_cloud.view_detail.orbit": "Perspective orbit",
                "point_cloud.view_detail.front": "Height profile",
                "point_cloud.view_detail.top": "Canopy projection",
                "point_cloud.view_detail.side": "Side profile",
                "point_cloud.color.height": "Height",
                "point_cloud.color.density": "Density",
                "point_cloud.color.fruit": "Fruit",
                "point_cloud.color.uniform": "Uniform",
                "point_cloud.measurement.start": "Start",
                "point_cloud.measurement.end": "End",
                "point_cloud.measurement.instruction": "Tap the point cloud to measure",
                "point_cloud.measurement.distance": "Measured distance",
                "point_cloud.accessibility.close_measurement": "Stop measuring",
                "scan.measurement.prompt.select_first": "Tap the first point",
                "scan.measurement.prompt.record_point_cloud": "Record a point cloud before measuring",
                "scan.measurement.prompt.surface_not_found": "No point selected. Tap the tree surface",
                "scan.measurement.prompt.select_second": "Tap the second point",
                "scan.measurement.prompt.complete": "Measurement complete. Tap to reset",
                "scan.measurement.calculating": "Calculating…",
                "scan.measurement.distance_format": "%.2f m"
            ],
            "zh": [
                "point_cloud.navigation_title": "点云预览",
                "point_cloud.accessibility.close_preview": "关闭点云预览",
                "point_cloud.empty.title": "暂无扫描数据",
                "point_cloud.empty.message": "完成扫描或导入 PLY 后，点云文件会自动出现在这里。",
                "point_cloud.action.new_scan": "新建扫描",
                "point_cloud.action.import_ply": "导入 PLY",
                "point_cloud.status.loading_title": "正在读取点云",
                "point_cloud.status.loading_message": "正在解析 PLY 点和颜色数据…",
                "point_cloud.status.error_title": "无法打开点云",
                "point_cloud.status.no_file_title": "暂无点云文件",
                "point_cloud.status.no_file_message": "完成扫描或导入 PLY 后，可在这里旋转、测量和分享点云。",
                "point_cloud.status.no_points_title": "没有可显示的点",
                "point_cloud.status.no_points_message": "该文件未解析到有效点云，请检查 PLY 内容。",
                "point_cloud.error.load_failed": "无法读取点云文件。",
                "point_cloud.selector.search_placeholder": "搜索编号",
                "point_cloud.selector.no_results": "未找到编号“%@”的记录",
                "point_cloud.accessibility.clear_search": "清除搜索",
                "point_cloud.viewer.title": "点云查看",
                "point_cloud.accessibility.share": "分享点云",
                "point_cloud.metric.points": "点",
                "point_cloud.metric.height": "高",
                "point_cloud.metric.footprint": "冠幅",
                "point_cloud.accessibility.point_count": "点数：%@",
                "point_cloud.accessibility.height": "高度：%@",
                "point_cloud.accessibility.footprint": "冠幅：%@",
                "point_cloud.tool.reset": "重置",
                "point_cloud.tool.color": "色彩",
                "point_cloud.tool.zoom_in": "放大",
                "point_cloud.tool.zoom_out": "缩小",
                "point_cloud.tool.measure": "测量",
                "point_cloud.legend.color_format": "色彩：%@",
                "point_cloud.legend.actual_height_format": "真实高度 %@",
                "point_cloud.legend.low": "低",
                "point_cloud.legend.high": "高",
                "point_cloud.legend.sparse": "稀",
                "point_cloud.legend.dense": "密",
                "point_cloud.legend.fruit_candidates": "果实候选",
                "point_cloud.legend.uniform_bright": "统一亮色",
                "point_cloud.view.orbit": "自由",
                "point_cloud.view.front": "正面",
                "point_cloud.view.top": "俯视",
                "point_cloud.view.side": "侧面",
                "point_cloud.view_detail.orbit": "透视旋转",
                "point_cloud.view_detail.front": "高度轮廓",
                "point_cloud.view_detail.top": "冠层投影",
                "point_cloud.view_detail.side": "侧向轮廓",
                "point_cloud.color.height": "高度",
                "point_cloud.color.density": "密度",
                "point_cloud.color.fruit": "果实",
                "point_cloud.color.uniform": "统一",
                "point_cloud.measurement.start": "起点",
                "point_cloud.measurement.end": "终点",
                "point_cloud.measurement.instruction": "点击点云表面测量",
                "point_cloud.measurement.distance": "测量距离",
                "point_cloud.accessibility.close_measurement": "停止测量",
                "scan.measurement.prompt.select_first": "点击第1个点",
                "scan.measurement.prompt.record_point_cloud": "请先录制点云",
                "scan.measurement.prompt.surface_not_found": "未选中点云，请点果树表面",
                "scan.measurement.prompt.select_second": "点击第2个点",
                "scan.measurement.prompt.complete": "测量完成，点击重置",
                "scan.measurement.calculating": "计算中…",
                "scan.measurement.distance_format": "%.2f m"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testLiveScanMeasurementPromptsUseTypedLocalizedState() throws {
        let expected: [String: [String]] = [
            "en": [
                "Tap the first point",
                "Record a point cloud before measuring",
                "No point selected. Tap the tree surface",
                "Tap the second point",
                "Measurement complete. Tap to reset",
            ],
            "zh": [
                "点击第1个点",
                "请先录制点云",
                "未选中点云，请点果树表面",
                "点击第2个点",
                "测量完成，点击重置",
            ],
        ]

        XCTAssertEqual(
            L10n.PointCloud.ScanMeasurementPrompt.allCases.map(\.rawValue),
            [
                "scan.measurement.prompt.select_first",
                "scan.measurement.prompt.record_point_cloud",
                "scan.measurement.prompt.surface_not_found",
                "scan.measurement.prompt.select_second",
                "scan.measurement.prompt.complete",
            ]
        )

        for language in ["en", "zh"] {
            let bundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            XCTAssertEqual(
                L10n.PointCloud.ScanMeasurementPrompt.allCases.map {
                    L10n.PointCloud.scanMeasurementPrompt($0, in: bundle)
                },
                expected[language]
            )
        }
    }

    func testLiveScanMeasurementControllerResetsSemanticPresentationState() {
        let controller = MetalMeasurementController()
        XCTAssertEqual(controller.instructionPrompt, .selectFirst)

        controller.activate()
        controller.instructionPrompt = .complete
        controller.measuredDistance = 1.25
        controller.point1Screen = CGPoint(x: 10, y: 20)
        controller.point2Screen = CGPoint(x: 30, y: 40)
        controller.deactivate()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.instructionPrompt, .selectFirst)
        XCTAssertNil(controller.measuredDistance)
        XCTAssertNil(controller.point1Screen)
        XCTAssertNil(controller.point2Screen)
    }

    func testLiveScanMeasurementDistanceUsesLocalizedFormat() throws {
        for language in ["en", "zh"] {
            let bundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            XCTAssertEqual(L10n.PointCloud.scanMeasurementDistance(1.234, in: bundle), "1.23 m")
            XCTAssertEqual(
                L10n.PointCloud.scanMeasurementCalculating(in: bundle),
                language == "en" ? "Calculating…" : "计算中…"
            )
        }
    }

    @MainActor
    func testLiveScanMeasurementOverlayRendersLongPromptAndDistanceInCompactLayout() throws {
        let controller = MetalMeasurementController()
        controller.activate()
        controller.instructionPrompt = .surfaceNotFound
        controller.point1Screen = CGPoint(x: 96, y: 300)
        controller.point2Screen = CGPoint(x: 294, y: 410)
        controller.measuredDistance = 1.234

        let content = MetalMeasurementOverlay(
            controller: controller,
            measuredDistance: .constant(nil),
            onClose: {}
        )
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 390, height: 844)
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 390, height: 844))

        let attachment = XCTAttachment(image: image)
        attachment.name = "LiveScanMeasurement-\(Locale.preferredLanguages.first ?? "unknown")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPointCloudMeasurementOverlayRendersAtAccessibilityTextSize() {
        let controller = PointCloudMeasurementController()
        controller.measuredDistance = 1.234
        var synchronizedDistance: Float?
        let measuredDistance = Binding<Float?>(
            get: { synchronizedDistance },
            set: { synchronizedDistance = $0 }
        )
        let rootView = MeasurementToolOverlay(
            controller: controller,
            measuredDistance: measuredDistance,
            onClose: {}
        )
        .environment(\.dynamicTypeSize, .accessibility5)
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        XCTAssertEqual(synchronizedDistance, controller.measuredDistance)
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "PointCloudMeasurementOverlay-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    func testPointCloudModesKeepStableRawValuesAndUseLocalizedDisplayNames() {
        XCTAssertEqual(
            PointCloudColorMode.allCases.map(\.rawValue),
            ["高度", "密度", "果实", "统一"],
            "Stable identifiers must not change when the display language changes"
        )
        XCTAssertEqual(
            PointCloudViewMode.allCases.map(\.rawValue),
            ["自由", "正面", "俯视", "侧面"],
            "Stable identifiers must not change when the display language changes"
        )

        XCTAssertEqual(
            PointCloudColorMode.allCases.map(\.displayName),
            [
                L10n.PointCloud.colorHeight,
                L10n.PointCloud.colorDensity,
                L10n.PointCloud.colorFruit,
                L10n.PointCloud.colorUniform
            ]
        )
        XCTAssertEqual(
            PointCloudViewMode.allCases.map(\.displayName),
            [
                L10n.PointCloud.viewOrbit,
                L10n.PointCloud.viewFront,
                L10n.PointCloud.viewTop,
                L10n.PointCloud.viewSide
            ]
        )
        XCTAssertEqual(
            PointCloudViewMode.allCases.map(\.detail),
            [
                L10n.PointCloud.viewDetailOrbit,
                L10n.PointCloud.viewDetailFront,
                L10n.PointCloud.viewDetailTop,
                L10n.PointCloud.viewDetailSide
            ]
        )
    }

    func testPointCloudDynamicCopyPreservesRuntimeValues() {
        XCTAssertTrue(L10n.PointCloud.noSearchResults(for: "TREE-17").contains("TREE-17"))
        XCTAssertTrue(L10n.PointCloud.colorLegend(modeName: "MODE-17").contains("MODE-17"))
        XCTAssertTrue(L10n.PointCloud.actualHeight("3.25 m").contains("3.25 m"))
        XCTAssertTrue(L10n.PointCloud.pointCountAccessibility("12,345").contains("12,345"))
        XCTAssertTrue(L10n.PointCloud.heightAccessibility("3.25 m").contains("3.25 m"))
        XCTAssertTrue(L10n.PointCloud.footprintAccessibility("2.00 x 4.00 m").contains("2.00 x 4.00 m"))
    }

    @MainActor
    func testPointCloudSelectionAndStatusRenderAtAccessibilityTextSize() {
        let firstURL = URL(fileURLWithPath: "/tmp/NORTH-ORCHARD-TREE-2026-08-09-A.ply")
        let records = [
            ScanFileRecord(
                id: "north-tree.ply",
                treeID: "NORTH-ORCHARD-TREE-2026-08-09-A",
                fileURL: firstURL,
                scanDate: Date(timeIntervalSince1970: 1_754_740_800),
                yieldKg: 12.4
            ),
            ScanFileRecord(
                id: "south-tree.ply",
                treeID: "SOUTH-BLOCK-TREE-B",
                fileURL: URL(fileURLWithPath: "/tmp/SOUTH-BLOCK-TREE-B.ply"),
                scanDate: Date(timeIntervalSince1970: 1_754_737_200),
                yieldKg: 8.1
            )
        ]
        let rootView = VStack(spacing: 0) {
            PointCloudFileSelector(
                records: records,
                selectedFile: firstURL,
                searchText: .constant("TREE"),
                onSelect: { _ in }
            )

            Spacer(minLength: 16)

            PointCloudStatusPanel(
                icon: "cube",
                title: L10n.PointCloud.noFileTitle,
                message: L10n.PointCloud.noFileMessage
            )

            Spacer(minLength: 16)
        }
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "PointCloudSelectionAndStatus-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

    @MainActor
    func testPointCloudControlsRenderAtAccessibilityTextSize() throws {
        let bounds = try XCTUnwrap(
            PointCloudBounds(vertices: [
                SCNVector3(-0.75, 0, -0.45),
                SCNVector3(0.75, 2.8, 0.45)
            ])
        )
        let rootView = VStack(spacing: 16) {
            PointCloudTopBar(
                pointCount: 12_345,
                bounds: bounds,
                viewMode: .orbit,
                canExport: true,
                onClose: {},
                onExport: {}
            )

            Spacer(minLength: 16)

            PointCloudBottomControls(
                pointCount: 12_345,
                canInteract: true,
                bounds: bounds,
                colorMode: .constant(.height),
                viewMode: .constant(.orbit),
                isMeasurementActive: true,
                onResetCamera: {},
                onZoomIn: {},
                onZoomOut: {},
                onToggleMeasurement: {}
            )
        }
        .padding(16)
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "PointCloudControls-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    // MARK: - Scan history loading and recovery

    func testScanHistoryDiskReadDistinguishesMissingDirectoryFromReadFailure() {
        let scansDirectory = URL(fileURLWithPath: "/tmp/scans", isDirectory: true)

        let missingDirectory = ScanHistoryStore.readRecords(
            at: scansDirectory,
            directoryExists: { _ in false },
            contentsOfDirectory: { _ in
                XCTFail("A missing directory must not be enumerated")
                return []
            },
            recordBuilder: { _ in
                XCTFail("A missing directory must not parse records")
                return nil
            }
        )
        let readFailure = ScanHistoryStore.readRecords(
            at: scansDirectory,
            directoryExists: { _ in true },
            contentsOfDirectory: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue)
            },
            recordBuilder: { _ in
                XCTFail("A failed directory enumeration must not parse records")
                return nil
            }
        )

        XCTAssertEqual(missingDirectory, .success([]))
        XCTAssertEqual(readFailure, .failure(.directoryUnavailable))
    }

    @MainActor
    func testScanHistoryLoadFailurePreservesLastSuccessfulSnapshotAndRetryClearsFailure() async {
        let initialRecord = makeScanHistoryRecord(id: "initial.ply")
        let repairedRecord = makeScanHistoryRecord(id: "repaired.ply")
        let driver = ScanHistoryLoadSequenceDriver(results: [
            .success([initialRecord]),
            .failure(.directoryUnavailable),
            .success([repairedRecord])
        ])
        let store = ScanHistoryStore(recordsLoader: { await driver.next() })

        await store.reloadRecords()
        XCTAssertEqual(store.scanFiles, [initialRecord])
        XCTAssertNil(store.loadFailure)

        await store.reloadRecords()
        XCTAssertEqual(
            store.scanFiles,
            [initialRecord],
            "A transient read failure must not replace a valid snapshot with false-empty history"
        )
        XCTAssertEqual(store.loadFailure, .directoryUnavailable)

        await store.reloadRecords()
        XCTAssertEqual(store.scanFiles, [repairedRecord])
        XCTAssertNil(store.loadFailure)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testScanHistoryLoadSeparatesDamagedResultsWithoutDroppingTheirPointCloudRecords() async {
        let validRecord = makeScanHistoryRecord(id: "valid.ply")
        let damagedRecord = makeScanHistoryRecord(
            id: "damaged.ply",
            persistenceState: .invalid,
            persistenceFailureReason: "scanResultJSONFailed"
        )
        let driver = ScanHistoryLoadSequenceDriver(results: [
            .success([validRecord, damagedRecord])
        ])
        let store = ScanHistoryStore(recordsLoader: { await driver.next() })

        await store.reloadRecords()

        XCTAssertEqual(store.scanFiles, [validRecord, damagedRecord])
        XCTAssertEqual(store.damagedRecords, [damagedRecord])
        XCTAssertNil(store.loadFailure)
    }

    @MainActor
    func testScanHistorySupersededLateLoadCannotOverwriteNewerResult() async {
        let olderRecord = makeScanHistoryRecord(id: "older.ply")
        let newerRecord = makeScanHistoryRecord(id: "newer.ply")
        let driver = ScanHistoryControlledLoadDriver()
        let store = ScanHistoryStore(recordsLoader: { await driver.load() })

        let olderTask = store.loadRecords()
        await driver.waitForPendingCount(1)
        let newerTask = store.loadRecords()
        await driver.waitForPendingCount(2)

        await driver.resume(request: 1, with: .success([newerRecord]))
        await newerTask.value
        XCTAssertEqual(store.scanFiles, [newerRecord])

        await driver.resume(request: 0, with: .success([olderRecord]))
        await olderTask.value
        XCTAssertEqual(
            store.scanFiles,
            [newerRecord],
            "A cancelled or superseded read must not apply after the latest generation"
        )
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testScanHistoryCancelledCurrentLoadClearsLoadingState() async {
        let store = ScanHistoryStore(recordsLoader: {
            while !Task.isCancelled {
                await Task.yield()
            }
            return .success([])
        })

        let loadTask = store.loadRecords()
        await Task.yield()
        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(
            store.isLoading,
            "Cancelling the active history load must not leave the loading UI stuck"
        )
    }

    func testScanHistoryCancelledDiskReadStopsBeforeBuildingRemainingRecords() async {
        let workerStarted = expectation(description: "Scan-history disk reader started")
        let allowWorkerToContinue = DispatchSemaphore(value: 0)

        let readTask = Task.detached {
            var builtRecordCount = 0
            var enumeratedURLCount = 0
            _ = ScanHistoryStore.readRecords(
                at: URL(fileURLWithPath: "/tmp/scans", isDirectory: true),
                directoryExists: { _ in true },
                directoryIterator: { _ in
                    ScanHistoryDirectoryIterator(
                        nextURL: {
                            guard enumeratedURLCount < 64 else { return nil }
                            defer { enumeratedURLCount += 1 }
                            return URL(
                                fileURLWithPath: "/tmp/scan-\(enumeratedURLCount).ply"
                            )
                        },
                        failureDescription: { nil }
                    )
                },
                recordBuilder: { url in
                    builtRecordCount += 1
                    if builtRecordCount == 1 {
                        workerStarted.fulfill()
                        allowWorkerToContinue.wait()
                    }
                    return ScanFileRecord(
                        id: url.lastPathComponent,
                        treeID: url.deletingPathExtension().lastPathComponent,
                        fileURL: url,
                        scanDate: Date(timeIntervalSince1970: TimeInterval(builtRecordCount))
                    )
                }
            )
            return (builtRecordCount, enumeratedURLCount)
        }

        await fulfillment(of: [workerStarted], timeout: 1)
        readTask.cancel()
        allowWorkerToContinue.signal()

        let (builtRecordCount, enumeratedURLCount) = await readTask.value
        XCTAssertEqual(
            builtRecordCount,
            1,
            "A cancelled disk read must not parse every remaining PLY in a large directory"
        )
        XCTAssertEqual(
            enumeratedURLCount,
            1,
            "A cancelled disk read must not enumerate the entire directory into memory"
        )
    }

    func testScanHistoryDiskReadConsumesLargeDirectoryIncrementallyAndSortsRecords() {
        let totalRecordCount = 10_000
        var enumeratedURLCount = 0
        var builtRecordCount = 0
        var maximumEnumerationLead = 0

        let result = ScanHistoryStore.readRecords(
            at: URL(fileURLWithPath: "/tmp/scans", isDirectory: true),
            directoryExists: { _ in true },
            directoryIterator: { _ in
                ScanHistoryDirectoryIterator(
                    nextURL: {
                        guard enumeratedURLCount < totalRecordCount else { return nil }
                        maximumEnumerationLead = max(
                            maximumEnumerationLead,
                            enumeratedURLCount + 1 - builtRecordCount
                        )
                        defer { enumeratedURLCount += 1 }
                        return URL(
                            fileURLWithPath: "/tmp/scan-\(enumeratedURLCount).ply"
                        )
                    },
                    failureDescription: { nil }
                )
            },
            recordBuilder: { url in
                builtRecordCount += 1
                let index = Int(
                    url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "scan-", with: "")
                ) ?? 0
                return ScanFileRecord(
                    id: url.lastPathComponent,
                    treeID: "TREE-\(index)",
                    fileURL: url,
                    scanDate: Date(timeIntervalSince1970: TimeInterval(index))
                )
            }
        )

        guard case .success(let records) = result else {
            return XCTFail("Expected the synthetic large-directory read to succeed")
        }
        XCTAssertEqual(records.count, totalRecordCount)
        XCTAssertEqual(records.first?.id, "scan-9999.ply")
        XCTAssertEqual(records.last?.id, "scan-0.ply")
        XCTAssertEqual(
            maximumEnumerationLead,
            1,
            "The reader should build each record before requesting the next directory entry"
        )
    }

    func testScanHistoryDiskReadCancellationPropagatesIntoDetachedWorker() async {
        let workerStarted = expectation(description: "Detached history reader started")
        let allowWorkerToFinish = DispatchSemaphore(value: 0)
        let workerObservedCancellation = expectation(
            description: "Detached history reader observed cancellation"
        )

        let loadTask = Task {
            await ScanHistoryStore.performDiskRead {
                workerStarted.fulfill()
                allowWorkerToFinish.wait()
                if Task.isCancelled {
                    workerObservedCancellation.fulfill()
                    return .cancelled
                }
                return .success([])
            }
        }

        await fulfillment(of: [workerStarted], timeout: 1)
        loadTask.cancel()
        allowWorkerToFinish.signal()

        let result = await loadTask.value
        await fulfillment(of: [workerObservedCancellation], timeout: 1)
        XCTAssertEqual(result, .cancelled)
    }

    func testScanHistoryLoadPresentationNeverShowsFailureAsEmptyHistory() {
        let cachedDamagedRecord = makeScanHistoryRecord(
            id: "cached.ply",
            persistenceState: .invalid,
            persistenceFailureReason: "scanResultJSONFailed"
        )
        let failedEmptyPresentation = ScanHistoryLoadPresentation(
            records: [],
            isLoading: false,
            loadFailure: .directoryUnavailable,
            damagedRecords: []
        )
        let stalePresentation = ScanHistoryLoadPresentation(
            records: [cachedDamagedRecord],
            isLoading: false,
            loadFailure: .directoryUnavailable,
            damagedRecords: [cachedDamagedRecord]
        )

        XCTAssertEqual(failedEmptyPresentation.primaryContent, .loadFailure)
        XCTAssertFalse(failedEmptyPresentation.showsLoadFailureBanner)
        XCTAssertEqual(stalePresentation.primaryContent, .records)
        XCTAssertTrue(stalePresentation.showsLoadFailureBanner)
        XCTAssertFalse(stalePresentation.showsDamagedRecordsBanner)
    }

    func testScanHistoryLoadPresentationNamesDamagedRecords() {
        let damagedRecord = makeScanHistoryRecord(
            id: "damaged-result.ply",
            persistenceState: .invalid,
            persistenceFailureReason: "scanResultRevisionMismatch"
        )

        let presentation = ScanHistoryLoadPresentation(
            records: [damagedRecord],
            isLoading: false,
            loadFailure: nil,
            damagedRecords: [damagedRecord]
        )

        XCTAssertEqual(presentation.primaryContent, .records)
        XCTAssertTrue(presentation.showsDamagedRecordsBanner)
        XCTAssertEqual(presentation.damagedRecordNames, ["damaged-result.ply"])
    }

    private func makeScanHistoryRecord(
        id: String,
        persistenceState: ScanPersistenceState = .complete,
        persistenceFailureReason: String? = nil
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id)"),
            scanDate: Date(timeIntervalSince1970: 1_720_000_000),
            persistenceState: persistenceState,
            persistenceFailureReason: persistenceFailureReason
        )
    }

    // MARK: - ScanHistoryStore.deleteFiles transaction ordering

    func testDeleteFilesPrimaryFailureOccursAfterCompanionCleanup() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let manifestURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_complete.json")
        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let removeItem: (URL) throws -> Void = { url in
            removed.append(url)
            if url == fileURL {
                throw NSError(domain: "TestError", code: 1)
            }
        }
        let fileExists: (String) -> Bool = { _ in true }

        let result = ScanHistoryStore.deleteFiles(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        )

        XCTAssertFalse(result, "Should return false when primary PLY removal throws")
        XCTAssertEqual(
            removed,
            [csvURL, jsonURL, manifestURL, fileURL],
            "The PLY anchor must be attempted only after companion cleanup succeeds"
        )
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

    func testDeleteFilesCompanionFailureKeepsPLYVisibleForFutureRetry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("recoverable_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let jsonURL = tempDir.appendingPathComponent("recoverable_record_result.json")
        let manifestURL = tempDir.appendingPathComponent("recoverable_record_complete.json")
        let artifactURLs = [fileURL, csvURL, jsonURL, manifestURL]
        for url in artifactURLs {
            try Data("test".utf8).write(to: url)
        }
        let record = ScanFileRecord(
            id: fileURL.lastPathComponent,
            treeID: "recoverable",
            fileURL: fileURL,
            scanDate: Date()
        )

        let result = ScanHistoryStore.deleteFilesWithResult(
            for: record,
            removeItem: { url in
                if url == csvURL {
                    throw NSError(domain: "TestError", code: 2)
                }
                try FileManager.default.removeItem(at: url)
            }
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "A companion failure must retain the PLY anchor so history can expose a later retry"
        )
        let reloaded = ScanHistoryStore.readRecords(
            at: tempDir,
            directoryExists: { FileManager.default.fileExists(atPath: $0) },
            contentsOfDirectory: { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) },
            recordBuilder: { url in url == fileURL ? record : nil }
        )
        XCTAssertEqual(reloaded, .success([record]))

        let retry = ScanHistoryStore.deleteFilesWithResult(for: record)
        XCTAssertTrue(retry.isComplete)
        XCTAssertTrue(
            artifactURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
            "A later retry should remove the preserved PLY and the failed companion"
        )
    }

    func testDeleteFilesCompanionFailureKeepsPrimaryForRetryAndContinuesCompanionCleanup() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let manifestURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_complete.json")

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
        XCTAssertEqual(
            removed,
            [csvURL, jsonURL, manifestURL],
            "Companion cleanup should continue, but the PLY anchor must remain after any failure"
        )
    }

    func testDeleteFilesRemovesPrimaryPLYAfterCompanions() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let manifestURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_complete.json")

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
        XCTAssertEqual(
            removed,
            [csvURL, jsonURL, manifestURL, fileURL],
            "Primary PLY should be removed only after every companion artifact"
        )
    }

    func testDeleteFilesWithResultReportsCompanionFailuresAndPreservedPrimary() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let manifestURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_complete.json")
        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let result = ScanHistoryStore.deleteFilesWithResult(
            for: record,
            fileExists: { _ in true },
            removeItem: { url in
                removed.append(url)
                throw NSError(domain: "TestError", code: 3)
            }
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            removed,
            [csvURL, jsonURL, manifestURL],
            "Each companion should be attempted while the PLY remains untouched"
        )
        XCTAssertEqual(
            result.residualArtifacts.map(\.kind),
            [.csv, .resultJSON, .completionManifest, .pointCloud]
        )
        XCTAssertEqual(
            result.residualArtifacts.map(\.url),
            [csvURL, jsonURL, manifestURL, fileURL]
        )
        for artifact in result.residualArtifacts.dropLast() {
            guard case .removalFailed(let message) = artifact.reason else {
                return XCTFail("Each failed companion should include the removal error")
            }
            XCTAssertFalse(message.isEmpty)
        }
        XCTAssertEqual(
            result.residualArtifacts.last?.reason,
            .notAttemptedAfterCompanionFailure
        )
    }

    func testDeleteFilesWithResultReportsEachFailedCompanionAndContinuesCleanup() {
        let fileURL = URL(fileURLWithPath: "/tmp/test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        let manifestURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_complete.json")
        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        var removed: [URL] = []
        let result = ScanHistoryStore.deleteFilesWithResult(
            for: record,
            fileExists: { _ in true },
            removeItem: { url in
                removed.append(url)
                if url == csvURL || url == manifestURL {
                    throw NSError(domain: "TestError", code: 4)
                }
            }
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            removed,
            [csvURL, jsonURL, manifestURL],
            "Companion failures must not prevent later companion attempts or delete the PLY"
        )
        XCTAssertEqual(
            result.residualArtifacts.map(\.kind),
            [.csv, .completionManifest, .pointCloud]
        )
        XCTAssertEqual(
            result.residualArtifacts.map(\.url),
            [csvURL, manifestURL, fileURL]
        )
        for artifact in result.residualArtifacts.dropLast() {
            guard case .removalFailed(let message) = artifact.reason else {
                return XCTFail("Failed companion should include its removal error")
            }
            XCTAssertFalse(message.isEmpty)
        }
        XCTAssertEqual(
            result.residualArtifacts.last?.reason,
            .notAttemptedAfterCompanionFailure
        )

        let batchResult = ScanHistoryBatchDeletionResult(
            records: [
                ScanHistoryRecordDeletionResult(recordID: "complete.ply", residualArtifacts: []),
                result
            ]
        )
        XCTAssertFalse(batchResult.isComplete)
        XCTAssertEqual(batchResult.failedRecordCount, 1)
        XCTAssertEqual(batchResult.records.map(\.recordID), ["complete.ply", record.id])
    }

    @MainActor
    func testDeleteRecordsWithResultReturnsStructuredBatchAndSupportsRepeat() async throws {
        let emptyResult = await ScanHistoryStore.shared.deleteRecordsWithResult([])
        XCTAssertTrue(emptyResult.isComplete)
        XCTAssertEqual(emptyResult.failedRecordCount, 0)
        XCTAssertTrue(emptyResult.records.isEmpty)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_record.ply")
        let csvURL = fileURL.deletingPathExtension().appendingPathExtension("csv")
        let jsonURL = tempDir.appendingPathComponent("test_record_result.json")
        let manifestURL = tempDir.appendingPathComponent("test_record_complete.json")
        let artifactURLs = [fileURL, csvURL, jsonURL, manifestURL]
        for url in artifactURLs {
            try Data("test".utf8).write(to: url)
        }
        let record = ScanFileRecord(
            id: "test_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        let firstResult = await ScanHistoryStore.shared.deleteRecordsWithResult([record])

        XCTAssertTrue(firstResult.isComplete)
        XCTAssertEqual(firstResult.failedRecordCount, 0)
        XCTAssertEqual(firstResult.records.map(\.recordID), [record.id])
        XCTAssertTrue(artifactURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

        let repeatedResult = await ScanHistoryStore.shared.deleteRecordsWithResult([record])

        XCTAssertTrue(repeatedResult.isComplete, "Deleting an already absent record should stay idempotent")
        XCTAssertEqual(repeatedResult.records.map(\.recordID), [record.id])
    }

    @MainActor
    func testDeleteRecordsWithResultCompletesStartedDeletionAfterCallerCancellation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("cancelled_record.ply")
        try Data("test".utf8).write(to: fileURL)
        let record = ScanFileRecord(
            id: "cancelled_record.ply",
            treeID: "test",
            fileURL: fileURL,
            scanDate: Date()
        )

        let task = Task {
            await ScanHistoryStore.shared.deleteRecordsWithResult([record])
        }
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.isComplete)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "A started irreversible deletion should not stop halfway after caller cancellation"
        )
    }

    @MainActor
    func testHistoryDeletionControllerReportsResidualKindsAndRetriesOnlyFailedRecords() async throws {
        let firstRecord = ScanFileRecord(
            id: "first.ply",
            treeID: "first",
            fileURL: URL(fileURLWithPath: "/tmp/first.ply"),
            scanDate: Date()
        )
        let secondRecord = ScanFileRecord(
            id: "second.ply",
            treeID: "second",
            fileURL: URL(fileURLWithPath: "/tmp/second.ply"),
            scanDate: Date()
        )
        let driver = ScanHistoryDeletionTestDriver()
        let controller = ScanHistoryDeletionController { records in
            await driver.delete(records)
        }

        let firstOperation = Task {
            await controller.delete([firstRecord, secondRecord])
        }
        let firstCall = await driver.nextCall()
        XCTAssertEqual(firstCall, [firstRecord, secondRecord])
        XCTAssertTrue(controller.isDeleting)

        await driver.completeNext(
            with: ScanHistoryBatchDeletionResult(
                records: [
                    ScanHistoryRecordDeletionResult(
                        recordID: firstRecord.id,
                        residualArtifacts: []
                    ),
                    ScanHistoryRecordDeletionResult(
                        recordID: secondRecord.id,
                        residualArtifacts: [
                            ScanHistoryDeletionArtifact(
                                kind: .csv,
                                url: secondRecord.fileURL.deletingPathExtension()
                                    .appendingPathExtension("csv"),
                                reason: .removalFailed("permission denied")
                            ),
                            ScanHistoryDeletionArtifact(
                                kind: .completionManifest,
                                url: secondRecord.fileURL.deletingLastPathComponent()
                                    .appendingPathComponent("second_complete.json"),
                                reason: .removalFailed("permission denied")
                            )
                        ]
                    )
                ]
            )
        )
        await firstOperation.value

        let failure = try XCTUnwrap(controller.failure)
        XCTAssertEqual(failure.recordsToRetry, [secondRecord])
        XCTAssertEqual(failure.residualKinds, [.csv, .completionManifest])
        XCTAssertEqual(failure.failedRecordCount, 1)
        XCTAssertFalse(controller.isDeleting)

        let retryOperation = Task {
            await controller.retry()
        }
        let retryCall = await driver.nextCall()
        XCTAssertEqual(retryCall, [secondRecord])
        await driver.completeNext(
            with: ScanHistoryBatchDeletionResult(
                records: [
                    ScanHistoryRecordDeletionResult(
                        recordID: secondRecord.id,
                        residualArtifacts: []
                    )
                ]
            )
        )
        await retryOperation.value

        XCTAssertNil(controller.failure)
        XCTAssertFalse(controller.isDeleting)
    }

    @MainActor
    func testHistoryDeletionControllerIgnoresLateResultAfterInvalidation() async {
        let record = ScanFileRecord(
            id: "late.ply",
            treeID: "late",
            fileURL: URL(fileURLWithPath: "/tmp/late.ply"),
            scanDate: Date()
        )
        let driver = ScanHistoryDeletionTestDriver()
        let controller = ScanHistoryDeletionController { records in
            await driver.delete(records)
        }

        let operation = Task {
            await controller.delete([record])
        }
        _ = await driver.nextCall()
        controller.invalidate()
        await driver.completeNext(
            with: ScanHistoryBatchDeletionResult(
                records: [
                    ScanHistoryRecordDeletionResult(
                        recordID: record.id,
                        residualArtifacts: [
                            ScanHistoryDeletionArtifact(
                                kind: .pointCloud,
                                url: record.fileURL,
                                reason: .removalFailed("late failure")
                            )
                        ]
                    )
                ]
            )
        )
        await operation.value

        XCTAssertFalse(controller.isDeleting)
        XCTAssertNil(controller.failure)
    }

    @MainActor
    func testHistoryDeletionControllerSuppressesResultAfterCallerCancellation() async {
        let record = ScanFileRecord(
            id: "cancelled.ply",
            treeID: "cancelled",
            fileURL: URL(fileURLWithPath: "/tmp/cancelled.ply"),
            scanDate: Date()
        )
        let driver = ScanHistoryDeletionTestDriver()
        let controller = ScanHistoryDeletionController { records in
            await driver.delete(records)
        }

        let operation = Task {
            await controller.delete([record])
        }
        _ = await driver.nextCall()
        operation.cancel()
        await driver.completeNext(
            with: ScanHistoryBatchDeletionResult(
                records: [
                    ScanHistoryRecordDeletionResult(
                        recordID: record.id,
                        residualArtifacts: [
                            ScanHistoryDeletionArtifact(
                                kind: .pointCloud,
                                url: record.fileURL,
                                reason: .removalFailed("cancelled result")
                            )
                        ]
                    )
                ]
            )
        )
        await operation.value

        XCTAssertFalse(controller.isDeleting)
        XCTAssertNil(controller.failure)
    }

    @MainActor
    func testHistoryDeletionControllerRejectsOverlappingDeletion() async {
        let firstRecord = ScanFileRecord(
            id: "first.ply",
            treeID: "first",
            fileURL: URL(fileURLWithPath: "/tmp/first.ply"),
            scanDate: Date()
        )
        let secondRecord = ScanFileRecord(
            id: "second.ply",
            treeID: "second",
            fileURL: URL(fileURLWithPath: "/tmp/second.ply"),
            scanDate: Date()
        )
        let driver = ScanHistoryDeletionTestDriver()
        let controller = ScanHistoryDeletionController { records in
            await driver.delete(records)
        }

        let firstOperation = Task {
            await controller.delete([firstRecord])
        }
        _ = await driver.nextCall()

        await controller.delete([secondRecord])
        let callCount = await driver.callCount()
        XCTAssertEqual(callCount, 1)

        await driver.completeNext(
            with: ScanHistoryBatchDeletionResult(
                records: [
                    ScanHistoryRecordDeletionResult(
                        recordID: firstRecord.id,
                        residualArtifacts: []
                    )
                ]
            )
        )
        await firstOperation.value
        XCTAssertFalse(controller.isDeleting)
    }

    @MainActor
    func testHistoryDeletionControllerIgnoresEmptyDeletion() async {
        let driver = ScanHistoryDeletionTestDriver()
        let controller = ScanHistoryDeletionController { records in
            await driver.delete(records)
        }

        await controller.delete([])

        let callCount = await driver.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(controller.isDeleting)
        XCTAssertNil(controller.failure)
    }

    // MARK: - Calibration input parsing

    func testCalibrationScanRecordImportPolicyUsesOnlyCompleteEvidenceAndPreservesOrder() {
        let scanDate = Date(timeIntervalSince1970: 1_720_000_000)
        func record(
            id: String,
            fruitCount: Int,
            yieldKg: Float,
            state: ScanPersistenceState
        ) -> ScanFileRecord {
            ScanFileRecord(
                id: id,
                treeID: id,
                fileURL: URL(fileURLWithPath: "/tmp/\(id).ply"),
                scanDate: scanDate,
                fruitCount: fruitCount,
                yieldKg: yieldKg,
                persistenceState: state
            )
        }

        let incomplete = record(
            id: "incomplete",
            fruitCount: 99,
            yieldKg: 42,
            state: .incomplete
        )
        let completeZero = record(
            id: "complete-zero",
            fruitCount: 0,
            yieldKg: 0,
            state: .complete
        )
        let invalid = record(
            id: "invalid",
            fruitCount: 88,
            yieldKg: 31,
            state: .invalid
        )
        let completeMeasured = record(
            id: "complete-measured",
            fruitCount: 12,
            yieldKg: 4.5,
            state: .complete
        )

        let eligible = CalibrationScanRecordImportPolicy.eligibleRecords(
            from: [incomplete, completeZero, invalid, completeMeasured]
        )

        XCTAssertEqual(eligible.map(\.id), [completeZero.id, completeMeasured.id])
        XCTAssertTrue(CalibrationScanRecordImportPolicy.isEligible(completeZero))
        XCTAssertFalse(CalibrationScanRecordImportPolicy.isEligible(incomplete))
        XCTAssertFalse(CalibrationScanRecordImportPolicy.isEligible(invalid))
    }

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

    func testCalibrationInputParserAcceptsLocaleDecimalSeparatorWithoutWeakeningValidation() throws {
        let locale = Locale(identifier: "de_DE")

        let estimatedYield = try XCTUnwrap(
            CalibrationRecordInputParser.estimatedYieldKgOrZero(" 2,75 ", locale: locale)
        )
        XCTAssertEqual(estimatedYield, 2.75, accuracy: 0.001)
        XCTAssertTrue(
            CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid("1,25", locale: locale)
        )

        let actualYield = try XCTUnwrap(
            CalibrationRecordInputParser.optionalNonNegativeDouble("1,25", locale: locale)
        )
        XCTAssertEqual(actualYield, 1.25, accuracy: 0.001)
        XCTAssertEqual(
            CalibrationRecordInputParser.optionalNonNegativeDouble("1.25", locale: locale),
            1.25,
            "Existing period-decimal input must remain compatible"
        )
        XCTAssertNil(
            CalibrationRecordInputParser.optionalNonNegativeDouble("1,2,3", locale: locale)
        )
        XCTAssertNil(
            CalibrationRecordInputParser.optionalNonNegativeDouble("-1,25", locale: locale)
        )
        XCTAssertNil(
            CalibrationRecordInputParser.optionalNonNegativeDouble("1,25kg", locale: locale)
        )
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

    // MARK: - Historical comparison data integrity

    func testHistoricalCompareItemsIncludeOnlyCompleteRecordsAndPreserveEvidence() throws {
        let complete = historicalCompareRecord(
            id: "complete.ply",
            treeID: "complete",
            fruitCount: 24,
            yieldKg: 8.6,
            confidence: "high",
            persistenceState: .complete
        )
        let incomplete = historicalCompareRecord(
            id: "incomplete.ply",
            treeID: "incomplete",
            fruitCount: 99,
            yieldKg: 99,
            confidence: "medium",
            persistenceState: .incomplete
        )
        let invalid = historicalCompareRecord(
            id: "invalid.ply",
            treeID: "invalid",
            fruitCount: 88,
            yieldKg: 88,
            confidence: "low",
            persistenceState: .invalid
        )

        let items = HistoricalCompareDataSource.items(from: [incomplete, complete, invalid])
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(items.map(\.id), ["complete.ply"])
        XCTAssertEqual(item.fruitCount, 24)
        XCTAssertEqual(item.yieldKg, 8.6, accuracy: 0.001)
        XCTAssertEqual(item.confidence, "high")
        XCTAssertNil(item.meanDiameterCm)
    }

    func testHistoricalCompareUnknownMetricsRemainUnavailable() throws {
        let record = historicalCompareRecord(
            id: "unknown.ply",
            treeID: "unknown",
            fruitCount: 0,
            yieldKg: 0,
            confidence: "",
            persistenceState: .complete
        )

        let item = try XCTUnwrap(HistoricalCompareDataSource.items(from: [record]).first)

        XCTAssertEqual(item.diameterFormatted, "--")
        XCTAssertEqual(item.confidenceFormatted, "--")
    }

    func testHistoricalCompareSelectionRefreshesAndDropsUnavailableItems() throws {
        let first = try XCTUnwrap(HistoricalCompareDataSource.items(from: [
            historicalCompareRecord(
                id: "first.ply",
                treeID: "first",
                fruitCount: 10,
                yieldKg: 2,
                confidence: "medium",
                persistenceState: .complete
            )
        ]).first)
        let second = try XCTUnwrap(HistoricalCompareDataSource.items(from: [
            historicalCompareRecord(
                id: "second.ply",
                treeID: "second",
                fruitCount: 20,
                yieldKg: 4,
                confidence: "high",
                persistenceState: .complete
            )
        ]).first)
        let refreshedFirst = try XCTUnwrap(HistoricalCompareDataSource.items(from: [
            historicalCompareRecord(
                id: "first.ply",
                treeID: "first",
                fruitCount: 15,
                yieldKg: 3,
                confidence: "high",
                persistenceState: .complete
            )
        ]).first)

        let selection = HistoricalCompareSelectionPolicy.reconciled(
            first: first,
            second: second,
            availableItems: [refreshedFirst]
        )

        XCTAssertEqual(selection.first, refreshedFirst)
        XCTAssertEqual(selection.first?.fruitCount, 15)
        XCTAssertNil(selection.second)
    }

    func testHistoricalCompareSelectionPreventsComparingItemWithItself() throws {
        let item = try XCTUnwrap(HistoricalCompareDataSource.items(from: [
            historicalCompareRecord(
                id: "same.ply",
                treeID: "same",
                fruitCount: 10,
                yieldKg: 2,
                confidence: "high",
                persistenceState: .complete
            )
        ]).first)

        let selection = HistoricalCompareSelectionPolicy.reconciled(
            first: item,
            second: item,
            availableItems: [item]
        )
        let selectable = HistoricalCompareSelectionPolicy.selectableItems(
            from: [item],
            excluding: item
        )

        XCTAssertEqual(selection.first, item)
        XCTAssertNil(selection.second)
        XCTAssertTrue(selectable.isEmpty)
    }

    func testHistoricalCompareYieldChangeIsUnavailableForZeroBaseline() throws {
        let items = HistoricalCompareDataSource.items(from: [
            historicalCompareRecord(
                id: "zero.ply",
                treeID: "zero",
                fruitCount: 0,
                yieldKg: 0,
                confidence: "high",
                persistenceState: .complete
            ),
            historicalCompareRecord(
                id: "positive.ply",
                treeID: "positive",
                fruitCount: 10,
                yieldKg: 3,
                confidence: "high",
                persistenceState: .complete
            )
        ])
        let zero = try XCTUnwrap(items.first { $0.id == "zero.ply" })
        let positive = try XCTUnwrap(items.first { $0.id == "positive.ply" })

        XCTAssertNil(zero.yieldChangePercent(to: positive))
        XCTAssertEqual(positive.yieldChangePercent(to: zero) ?? .nan, -100, accuracy: 0.001)
    }

    private func historicalCompareRecord(
        id: String,
        treeID: String,
        fruitCount: Int,
        yieldKg: Float,
        confidence: String,
        persistenceState: ScanPersistenceState
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/\(id)"),
            scanDate: Date(timeIntervalSince1970: 1_722_141_200),
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            confidence: confidence,
            persistenceState: persistenceState
        )
    }
}

private actor ScanHistoryDeletionTestDriver {
    private var queuedCalls: [[ScanFileRecord]] = []
    private var callWaiters: [CheckedContinuation<[ScanFileRecord], Never>] = []
    private var resultWaiters: [CheckedContinuation<ScanHistoryBatchDeletionResult, Never>] = []
    private var totalCallCount = 0

    func delete(_ records: [ScanFileRecord]) async -> ScanHistoryBatchDeletionResult {
        totalCallCount += 1
        if callWaiters.isEmpty {
            queuedCalls.append(records)
        } else {
            callWaiters.removeFirst().resume(returning: records)
        }
        return await withCheckedContinuation { continuation in
            resultWaiters.append(continuation)
        }
    }

    func nextCall() async -> [ScanFileRecord] {
        if !queuedCalls.isEmpty {
            return queuedCalls.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func completeNext(with result: ScanHistoryBatchDeletionResult) {
        precondition(!resultWaiters.isEmpty, "No pending deletion to complete")
        resultWaiters.removeFirst().resume(returning: result)
    }

    func callCount() -> Int {
        totalCallCount
    }
}

private actor ScanHistoryLoadSequenceDriver {
    private var results: [ScanHistoryLoadResult]

    init(results: [ScanHistoryLoadResult]) {
        self.results = results
    }

    func next() -> ScanHistoryLoadResult {
        precondition(!results.isEmpty, "Test requested more scan-history loads than configured")
        return results.removeFirst()
    }
}

private actor ScanHistoryControlledLoadDriver {
    private var continuations: [Int: CheckedContinuation<ScanHistoryLoadResult, Never>] = [:]
    private var nextRequest = 0

    func load() async -> ScanHistoryLoadResult {
        let request = nextRequest
        nextRequest += 1
        return await withCheckedContinuation { continuation in
            continuations[request] = continuation
        }
    }

    func waitForPendingCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resume(request: Int, with result: ScanHistoryLoadResult) {
        guard let continuation = continuations.removeValue(forKey: request) else {
            preconditionFailure("No pending scan-history load for request \(request)")
        }
        continuation.resume(returning: result)
    }
}
