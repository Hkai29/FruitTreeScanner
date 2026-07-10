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
