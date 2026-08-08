import XCTest
@testable import FruitTreeScanner

@MainActor
final class FruitParametersStoreTests: XCTestCase {
    func testRapidSavesKeepLatestParametersAndDoNotClearLatestSaveTask() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)

        let store = FruitParametersStore(
            defaults: defaults,
            commitDelayNanoseconds: { generation in
                switch generation {
                case 1, 4:
                    return 50_000_000
                case 2, 3:
                    return 150_000_000
                default:
                    return 0
                }
            }
        )
        store.updateParam(for: .apple) { $0.averageWeightG = 100 }
        store.updateParam(for: .apple) { $0.averageWeightG = 200 }

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(store.hasPendingSave)
        await store.waitForPendingSave()

        let persisted = try persistedParams(from: defaults)
        XCTAssertEqual(persisted.first(where: { $0.category == FruitCategory.apple.rawValue })?.averageWeightG, 200)

        store.updateParam(for: .apple) { $0.averageWeightG = 300 }
        store.updateParam(for: .apple) { $0.averageWeightG = 400 }
        await store.waitForPendingSave()
        try await Task.sleep(nanoseconds: 180_000_000)

        let afterLateStaleSave = try persistedParams(from: defaults)
        XCTAssertEqual(afterLateStaleSave.first(where: { $0.category == FruitCategory.apple.rawValue })?.averageWeightG, 400)
    }

    func testSingleSaveUsesExistingKeyAndCodableFormat() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)

        let store = FruitParametersStore(defaults: defaults)
        store.updateParam(for: .pear) { $0.density = 0.95 }
        await store.waitForPendingSave()

        XCTAssertNotNil(defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        let reloaded = FruitParametersStore(defaults: defaults)
        XCTAssertEqual(reloaded.param(for: .pear).density, 0.95, accuracy: 0.0001)
    }

    func testValidPartialSnapshotStillNormalizesAndPersists() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        var customizedApple = FruitVarietyParams(category: .apple)
        customizedApple.averageWeightG = 246
        customizedApple.isCustomized = true
        defaults.set(
            try JSONEncoder().encode([customizedApple]),
            forKey: FruitParametersStore.userDefaultsKey
        )

        let store = FruitParametersStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertEqual(store.params.count, FruitCategory.allCases.count)
        XCTAssertEqual(store.param(for: .apple).averageWeightG, 246)
        let persisted = try persistedParams(from: defaults)
        XCTAssertEqual(persisted.count, FruitCategory.allCases.count)
        XCTAssertEqual(
            persisted.first(where: { $0.category == FruitCategory.apple.rawValue }),
            customizedApple
        )
    }

    func testCorruptedSnapshotUsesDefaultsWithoutOverwritingStoredPayload() async {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let corruptedPayload = Data([0xFF, 0x00, 0x7F])
        defaults.set(corruptedPayload, forKey: FruitParametersStore.userDefaultsKey)

        let store = FruitParametersStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertEqual(store.params.count, FruitCategory.allCases.count)
        XCTAssertEqual(defaults.data(forKey: FruitParametersStore.userDefaultsKey), corruptedPayload)
    }

    func testExplicitUpdateReplacesPreservedCorruptSnapshotWithValidData() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set(Data([0xFF, 0x00, 0x7F]), forKey: FruitParametersStore.userDefaultsKey)

        let store = FruitParametersStore(defaults: defaults)
        store.updateParam(for: .apple) { $0.averageWeightG = 321 }
        await store.waitForPendingSave()

        let persisted = try persistedParams(from: defaults)
        XCTAssertEqual(persisted.count, FruitCategory.allCases.count)
        XCTAssertEqual(
            persisted.first(where: { $0.category == FruitCategory.apple.rawValue })?.averageWeightG,
            321
        )
    }

    func testMissingSnapshotInitializesAndPersistsDefaults() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = FruitParametersStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertEqual(store.params.count, FruitCategory.allCases.count)
        XCTAssertEqual(try persistedParams(from: defaults).count, FruitCategory.allCases.count)
    }

    func testVarietyDatabaseCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "variety.title": "Variety Parameters",
                "variety.more_actions": "More variety actions",
                "variety.reset_all": "Reset All Parameters",
                "variety.reset_all_message": "Reset every variety parameter to its default value? This cannot be undone.",
                "variety.reset": "Reset",
                "variety.search_prompt": "Search varieties",
                "variety.active_scan": "Current scan: %@",
                "variety.customized_count": "Customized varieties: %d",
                "variety.search_results": "Search results: %d",
                "variety.search_empty_title": "No matching varieties",
                "variety.search_empty_message": "No parameters match “%@”.",
                "variety.current": "Current",
                "variety.current_accessibility": "%@, current scan variety",
                "variety.use_accessibility": "Use %@ for scanning",
                "variety.use_hint": "Sets this variety for future scans.",
                "variety.customized_accessibility": "%@, customized parameters",
                "variety.edit_accessibility": "Edit %@ parameters",
                "variety.chip.diameter": "Dia.",
                "variety.chip.average_weight": "Avg.",
                "variety.chip.eps": "Eps",
                "variety.edit_title": "Edit %@",
                "variety.edit_impact": "Changing these parameters affects %@ detection and yield estimates.",
                "variety.section.size": "Fruit Size",
                "variety.minimum_diameter": "Minimum Diameter",
                "variety.maximum_diameter": "Maximum Diameter",
                "variety.section.weight_density": "Weight and Density",
                "variety.average_weight": "Average Fruit Weight",
                "variety.density": "Density",
                "variety.section.thresholds": "Detection Thresholds",
                "variety.sphericity_threshold": "Sphericity Threshold",
                "variety.section.clustering": "Clustering",
                "variety.cluster_radius": "Clustering Radius (Eps)",
                "variety.reset_default": "Reset to Defaults",
                "variety.reset_parameter_title": "Reset Parameters",
                "variety.reset_parameter_message": "Reset this variety to its default parameter values?",
                "variety.slider_hint": "Swipe up or down to adjust the value.",
                "variety.unit_value": "%@ %@",
                "variety.diameter_range": "%@–%@ %@"
            ],
            "zh": [
                "variety.title": "品种参数库",
                "variety.more_actions": "更多品种操作",
                "variety.reset_all": "重置所有参数",
                "variety.reset_all_message": "确定要将所有品种参数重置为默认值吗？此操作无法撤销。",
                "variety.reset": "重置",
                "variety.search_prompt": "搜索品种",
                "variety.active_scan": "当前扫描：%@",
                "variety.customized_count": "已自定义品种：%d",
                "variety.search_results": "搜索结果：%d",
                "variety.search_empty_title": "没有匹配的品种",
                "variety.search_empty_message": "未找到与“%@”匹配的参数。",
                "variety.current": "当前",
                "variety.current_accessibility": "%@，当前扫描品种",
                "variety.use_accessibility": "将%@设为扫描品种",
                "variety.use_hint": "设为后续扫描使用的品种。",
                "variety.customized_accessibility": "%@，参数已自定义",
                "variety.edit_accessibility": "编辑%@参数",
                "variety.chip.diameter": "直径",
                "variety.chip.average_weight": "均重",
                "variety.chip.eps": "Eps",
                "variety.edit_title": "编辑%@",
                "variety.edit_impact": "调整参数会影响%@的检测和产量估算结果。",
                "variety.section.size": "果实尺寸",
                "variety.minimum_diameter": "最小直径",
                "variety.maximum_diameter": "最大直径",
                "variety.section.weight_density": "重量与密度",
                "variety.average_weight": "平均单果重量",
                "variety.density": "密度",
                "variety.section.thresholds": "检测阈值",
                "variety.sphericity_threshold": "球形度阈值",
                "variety.section.clustering": "聚类参数",
                "variety.cluster_radius": "聚类半径 (Eps)",
                "variety.reset_default": "重置为默认值",
                "variety.reset_parameter_title": "重置参数",
                "variety.reset_parameter_message": "确定要将此品种重置为默认参数吗？",
                "variety.slider_hint": "上下轻扫以调整数值。",
                "variety.unit_value": "%@ %@",
                "variety.diameter_range": "%@–%@ %@"
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

    func testVarietyParameterFormatterUsesTheRequestedLocaleWithoutChangingValues() {
        XCTAssertEqual(
            VarietyParameterFormatter.decimal(0.875, fractionDigits: 3, locale: Locale(identifier: "en_US")),
            "0.875"
        )
        XCTAssertEqual(
            VarietyParameterFormatter.decimal(0.875, fractionDigits: 3, locale: Locale(identifier: "fr_FR")),
            "0,875"
        )
        XCTAssertEqual(
            VarietyParameterFormatter.integer(1_500, locale: Locale(identifier: "en_US")),
            "1500",
            "Compact parameter values must not gain grouping separators"
        )
    }

    func testVarietySearchMatcherSupportsLocalizedNamesAndStableIdentifiers() {
        XCTAssertTrue(
            VarietySearchMatcher.matches(
                category: .mandarin,
                query: "柑橘",
                localizedName: "柑橘"
            )
        )
        XCTAssertTrue(
            VarietySearchMatcher.matches(
                category: .mandarin,
                query: "MANDARIN",
                localizedName: "柑橘"
            )
        )
        XCTAssertFalse(
            VarietySearchMatcher.matches(
                category: .mandarin,
                query: "apple",
                localizedName: "柑橘"
            )
        )
    }

    private func seedDefaultParams(in defaults: UserDefaults) throws {
        let params = FruitCategory.allCases.map { FruitVarietyParams(category: $0) }
        defaults.set(try JSONEncoder().encode(params), forKey: FruitParametersStore.userDefaultsKey)
    }

    private func persistedParams(from defaults: UserDefaults) throws -> [FruitVarietyParams] {
        let data = try XCTUnwrap(defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        return try JSONDecoder().decode([FruitVarietyParams].self, from: data)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FruitParametersStoreTests.\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: FruitParametersStore.userDefaultsKey)
    }
}
