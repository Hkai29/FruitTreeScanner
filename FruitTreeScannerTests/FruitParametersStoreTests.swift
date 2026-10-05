import Combine
import XCTest
@testable import FruitTreeScanner

@MainActor
final class FruitParametersStoreTests: XCTestCase {
    func testEditCommitMergesEachFieldAndPreservesOtherNewerParameters() async throws {
        let cases: [(WritableKeyPath<FruitVarietyParams, Float>, Float)] = [
            (\.diamMin, 0.040), (\.diamMax, 0.170), (\.averageWeightG, 222),
            (\.density, 0.93), (\.clusterEps, 0.055), (\.sphericityThreshold, 0.64)
        ]
        for (field, value) in cases {
            let defaults = makeDefaults()
            defer { clear(defaults) }
            try seedDefaultParams(in: defaults)
            let store = FruitParametersStore(defaults: defaults)
            let baseline = store.param(for: .pear)
            let apple = store.param(for: .apple)
            var draft = baseline
            draft[keyPath: field] = value
            store.updateParam(for: .pear) {
                $0.diamMin = 0.035
                $0.diamMax = 0.165
                $0.averageWeightG = 333
                $0.density = 0.92
                $0.clusterEps = 0.060
                $0.sphericityThreshold = 0.66
                $0[keyPath: field] = baseline[keyPath: field]
            }
            var expected = store.param(for: .pear)
            expected[keyPath: field] = value
            assertAccepted(store.commitEdits(for: .pear, baseline: baseline, edited: draft))
            await store.waitForPendingSave()
            XCTAssertEqual(store.param(for: .pear), expected)
            XCTAssertEqual(store.param(for: .apple), apple)
            XCTAssertEqual(try persistedParams(from: defaults).first { $0.category == "pear" }, expected)
        }
    }

    func testEditCommitRejectsConflictAtomicallyWithoutPublishingOrSaving() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)
        let store = FruitParametersStore(defaults: defaults)
        let baseline = store.param(for: .pear)
        var draft = baseline
        draft.averageWeightG = 222
        draft.density = 0.94
        store.updateParam(for: .pear) { $0.density = 0.92 }
        await store.waitForPendingSave()
        let current = store.param(for: .pear)
        let bytes = defaults.data(forKey: FruitParametersStore.userDefaultsKey)
        var publications = 0
        let observation = store.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        assertConflict(store.commitEdits(for: .pear, baseline: baseline, edited: draft), current: current)
        XCTAssertEqual(store.param(for: .pear), current, "A later conflicting field must prevent an earlier weight write")
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.hasPendingSave)
        XCTAssertEqual(defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
    }

    func testEditCommitProtectsBothDiameterBoundsAndAllowsSafeMerge() async throws {
        for (lower, upper, editLower, accepted) in [(Float(0.142), Float(0.145), false, false),
                                                   (0.035, 0.039, true, false),
                                                   (0.040, 0.145, false, true)] {
            let defaults = makeDefaults()
            defer { clear(defaults) }
            try seedDefaultParams(in: defaults)
            let store = FruitParametersStore(defaults: defaults)
            store.updateParam(for: .pear) { $0.diamMin = 0.035; $0.diamMax = 0.145 }
            let baseline = store.param(for: .pear)
            var draft = baseline
            if editLower { draft.diamMin = 0.040 } else { draft.diamMax = 0.140 }
            store.updateParam(for: .pear) { $0.diamMin = lower; $0.diamMax = upper }
            await store.waitForPendingSave()
            let current = store.param(for: .pear)
            let bytes = defaults.data(forKey: FruitParametersStore.userDefaultsKey)
            let result = store.commitEdits(for: .pear, baseline: baseline, edited: draft)
            if accepted {
                assertAccepted(result)
                await store.waitForPendingSave()
                var expected = current
                expected.diamMax = 0.140
                XCTAssertEqual(store.param(for: .pear), expected)
            } else {
                assertConflict(result, current: current)
                XCTAssertEqual(store.param(for: .pear), current)
                XCTAssertFalse(store.hasPendingSave)
                XCTAssertEqual(defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
            }
        }
    }

    func testEditCommitRejectsResetIdentityAndAcceptsFreshDraft() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)
        let store = FruitParametersStore(defaults: defaults)
        let baseline = store.param(for: .pear)
        let apple = store.param(for: .apple)
        var draft = baseline
        draft.averageWeightG = 181
        store.resetToDefault(for: .pear)
        await store.waitForPendingSave()
        let reset = store.param(for: .pear)
        XCTAssertNotEqual(reset.id, baseline.id)
        XCTAssertEqual(reset.averageWeightG, baseline.averageWeightG)
        let bytes = defaults.data(forKey: FruitParametersStore.userDefaultsKey)
        assertConflict(store.commitEdits(for: .pear, baseline: baseline, edited: draft), current: reset)
        XCTAssertEqual(store.param(for: .pear), reset)
        XCTAssertFalse(store.hasPendingSave)
        XCTAssertEqual(defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        var fresh = reset
        fresh.averageWeightG = 181
        assertAccepted(store.commitEdits(for: .pear, baseline: reset, edited: fresh))
        await store.waitForPendingSave()
        fresh.isCustomized = true
        XCTAssertEqual(store.param(for: .pear), fresh)
        XCTAssertEqual(store.param(for: .apple), apple)
        XCTAssertEqual(try persistedParams(from: defaults).first { $0.category == "pear" }, fresh)
    }

    func testUneditedCommitDoesNotCustomizePublishOrScheduleSave() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)
        let store = FruitParametersStore(defaults: defaults)
        let baseline = store.param(for: .pear)
        let bytes = defaults.data(forKey: FruitParametersStore.userDefaultsKey)
        var publications = 0
        let observation = store.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        assertAccepted(store.commitEdits(for: .pear, baseline: baseline, edited: baseline))
        XCTAssertEqual(store.param(for: .pear), baseline)
        XCTAssertFalse(store.param(for: .pear).isCustomized)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.hasPendingSave)
        XCTAssertEqual(defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
    }

    func testEditCommitRejectsWrongCategoryAndNonFiniteChanges() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedDefaultParams(in: defaults)
        let store = FruitParametersStore(defaults: defaults)
        let baseline = store.param(for: .pear)
        var wrong = store.param(for: .apple)
        wrong.averageWeightG = 222
        assertConflict(store.commitEdits(for: .pear, baseline: baseline, edited: wrong), current: baseline)
        var invalid = baseline
        invalid.density = .nan
        assertConflict(store.commitEdits(for: .pear, baseline: baseline, edited: invalid), current: baseline)
        XCTAssertEqual(store.param(for: .pear), baseline)
        XCTAssertFalse(store.hasPendingSave)
    }

    private func assertAccepted(_ result: FruitParametersStore.EditCommitResult,
                                file: StaticString = #filePath, line: UInt = #line) {
        if case .accepted = result { return }
        XCTFail("Expected this edit to be accepted", file: file, line: line)
    }

    private func assertConflict(_ result: FruitParametersStore.EditCommitResult, current: FruitVarietyParams,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case .conflict(let latest) = result else {
            XCTFail("Expected the entire edit to be rejected", file: file, line: line)
            return
        }
        XCTAssertEqual(latest, current, file: file, line: line)
    }

    func testParameterSchemaFixtureKeepsIdentityAndCalibrationFields() throws {
        // Fixed pre-migration schema fixture; not a user's private stored record.
        let fixture = Data(#"{"id":"01234567-89AB-4CDE-8F01-23456789ABCD","category":"pear","diamMin":0.031,"diamMax":0.13,"averageWeightG":245,"density":0.94,"clusterEps":0.047,"sphericityThreshold":0.33,"isCustomized":true}"#.utf8)
        let parameters = try JSONDecoder().decode(FruitVarietyParams.self, from: fixture)
        XCTAssertEqual(parameters.id, UUID(uuidString: "01234567-89AB-4CDE-8F01-23456789ABCD"))
        XCTAssertEqual(parameters.fruitCategory, .pear)
        XCTAssertTrue(parameters.isCustomized)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // A separate Foundation encoder can expand Float decimals; use fixed
        // JSONEncoder-compatible bytes instead of normalizing through NSNumber.
        let expected = Data(#"{"averageWeightG":245,"category":"pear","clusterEps":0.047,"density":0.94,"diamMax":0.13,"diamMin":0.031,"id":"01234567-89AB-4CDE-8F01-23456789ABCD","isCustomized":true,"sphericityThreshold":0.33}"#.utf8)
        XCTAssertEqual(try encoder.encode(parameters), expected,
            "Moving the parameter value must not change its persisted identity, keys or calibration inputs")
    }

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
                "variety.parameters.concurrent_update": "Parameters changed on another screen. Nothing was saved. Latest values loaded; adjust them again and save.",
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
                "variety.parameters.concurrent_update": "参数已在其他页面更新，本次未保存。已载入最新值，请重新调整后保存。",
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
