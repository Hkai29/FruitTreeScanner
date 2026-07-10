import Foundation

struct FruitVarietyParams: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let category: String
    var diamMin: Float
    var diamMax: Float
    var averageWeightG: Float
    var density: Float
    var clusterEps: Float
    var sphericityThreshold: Float
    var isCustomized: Bool
    
    init(category: FruitCategory) {
        self.id = UUID()
        self.category = category.rawValue
        self.diamMin = category.diamMin
        self.diamMax = category.diamMax
        self.averageWeightG = category.averageWeightG
        self.density = category.density
        self.clusterEps = category.clusterEps
        self.sphericityThreshold = category.sphericityThreshold
        self.isCustomized = false
    }
    
    var fruitCategory: FruitCategory? {
        FruitCategory(rawValue: category)
    }
    
    var displayName: String {
        fruitCategory?.displayName ?? category
    }
}

@MainActor
final class FruitParametersStore: ObservableObject {
    static let shared = FruitParametersStore()
    
    @Published var params: [FruitVarietyParams] = []
    
    nonisolated static let userDefaultsKey = "fruitVarietyParams"
    private let defaults: UserDefaults
    private let commitDelayNanoseconds: @Sendable (Int) -> UInt64
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0
    
    init(
        defaults: UserDefaults = .standard,
        commitDelayNanoseconds: @escaping @Sendable (Int) -> UInt64 = { _ in 0 }
    ) {
        self.defaults = defaults
        self.commitDelayNanoseconds = commitDelayNanoseconds
        loadParams()
        normalizeParams()
    }
    
    private func initializeDefaultParams() {
        params = FruitCategory.allCases.map { FruitVarietyParams(category: $0) }
        saveParams()
    }
    
    func loadParams() {
        guard let data = defaults.data(forKey: Self.userDefaultsKey) else { return }
        do {
            params = try JSONDecoder().decode([FruitVarietyParams].self, from: data)
        } catch {
            Log.settings.error("Failed to read fruit variety parameters: \(error.localizedDescription)")
        }
    }

    func saveParams() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = params
        let commitDelayNanoseconds = commitDelayNanoseconds(generation)
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try Task.checkCancellation()
                let encoded = try JSONEncoder().encode(snapshot)
                try Task.checkCancellation()
                if commitDelayNanoseconds > 0 {
                    await Task.detached {
                        try? await Task.sleep(nanoseconds: commitDelayNanoseconds)
                    }.value
                }
                await self?.commitSave(encoded, generation: generation)
            } catch is CancellationError {
                await self?.finishSaving(generation: generation)
            } catch {
                Log.settings.error("Failed to save fruit variety parameters: \(error.localizedDescription)")
                await self?.finishSaving(generation: generation)
            }
        }
    }

    private func commitSave(_ encoded: Data, generation: Int) {
        guard saveGeneration == generation else { return }
        defaults.set(encoded, forKey: Self.userDefaultsKey)
        saveTask = nil
    }

    private func finishSaving(generation: Int) {
        if saveGeneration == generation {
            saveTask = nil
        }
    }

    func waitForPendingSave() async {
        if let saveTask {
            await saveTask.value
        }
    }

    var hasPendingSave: Bool {
        saveTask != nil
    }

    private func normalizeParams() {
        if params.isEmpty {
            initializeDefaultParams()
            return
        }

        var normalized: [FruitVarietyParams] = []
        normalized.reserveCapacity(FruitCategory.allCases.count)

        for category in FruitCategory.allCases {
            if let existing = params.first(where: { $0.category == category.rawValue }) {
                normalized.append(Self.sanitized(existing, fallback: category))
            } else {
                normalized.append(FruitVarietyParams(category: category))
            }
        }

        if normalized != params {
            params = normalized
            saveParams()
        }
    }

    private static func sanitized(_ value: FruitVarietyParams, fallback category: FruitCategory) -> FruitVarietyParams {
        var result = value
        let defaults = FruitVarietyParams(category: category)
        result.diamMin = clampFinite(result.diamMin, min: 0.005, max: 0.5, fallback: defaults.diamMin)
        result.diamMax = clampFinite(result.diamMax, min: result.diamMin, max: 0.7, fallback: defaults.diamMax)
        result.averageWeightG = clampFinite(result.averageWeightG, min: 1, max: 10_000, fallback: defaults.averageWeightG)
        result.density = clampFinite(result.density, min: 0.05, max: 3, fallback: defaults.density)
        result.clusterEps = clampFinite(result.clusterEps, min: 0.001, max: 0.5, fallback: defaults.clusterEps)
        result.sphericityThreshold = clampFinite(result.sphericityThreshold, min: 0, max: 1, fallback: defaults.sphericityThreshold)
        return result
    }

    private static func clampFinite(_ value: Float, min: Float, max: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return Swift.max(min, Swift.min(value, max))
    }
    
    func updateParam(for category: FruitCategory, updates: (inout FruitVarietyParams) -> Void) {
        guard let index = params.firstIndex(where: { $0.category == category.rawValue }) else { return }
        updates(&params[index])
        params[index].isCustomized = true
        saveParams()
    }
    
    func resetToDefault(for category: FruitCategory) {
        guard let index = params.firstIndex(where: { $0.category == category.rawValue }) else { return }
        params[index] = FruitVarietyParams(category: category)
        saveParams()
    }
    
    func resetAll() {
        initializeDefaultParams()
    }
    
    func param(for category: FruitCategory) -> FruitVarietyParams {
        params.first { $0.category == category.rawValue } ?? FruitVarietyParams(category: category)
    }

    func parameterSnapshot() -> [String: FruitVarietyParams] {
        Dictionary(uniqueKeysWithValues: params.map { ($0.category, $0) })
    }
    
    func customizedCount() -> Int {
        params.filter { $0.isCustomized }.count
    }
}

@MainActor
extension FruitCategory {
    func getParams() -> FruitVarietyParams {
        FruitParametersStore.shared.param(for: self)
    }
    
    func getDiameterMin() -> Float {
        getParams().diamMin
    }
    
    func getDiameterMax() -> Float {
        getParams().diamMax
    }
    
    func getAverageWeightG() -> Float {
        getParams().averageWeightG
    }
    
    func getDensity() -> Float {
        getParams().density
    }
    
    func getClusterEps() -> Float {
        getParams().clusterEps
    }
    
    func getSphericityThreshold() -> Float {
        getParams().sphericityThreshold
    }

    func makeClusterConfig(minPoints: Int) -> ClusterConfig {
        getParams().makeClusterConfig(minPoints: minPoints)
    }
}

extension FruitVarietyParams {
    func makeClusterConfig(minPoints: Int) -> ClusterConfig {
        return ClusterConfig(
            minPoints: minPoints,
            minDiameter: diamMin,
            maxDiameter: diamMax,
            baseEps: clusterEps,
            sphericityThreshold: sphericityThreshold
        )
    }
}
