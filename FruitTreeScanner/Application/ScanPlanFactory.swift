import Foundation

protocol ScanModelIdentityProviding: Sendable {
    func modelIdentity() async -> ScanModelIdentity
}

actor BundledScanModelIdentityProvider: ScanModelIdentityProviding {
    private var cachedIdentity: ScanModelIdentity?
    private var preparation: Task<ScanModelIdentity, Never>?

    func modelIdentity() async -> ScanModelIdentity {
        if let cachedIdentity = cachedIdentity { return cachedIdentity }
        if let preparation = preparation {
            let identity = await preparation.value
            cachedIdentity = identity
            self.preparation = nil
            return identity
        }

        let task = Task.detached(priority: .utility) {
            ScanModelFingerprint.bundledIdentity
        }
        preparation = task
        let identity = await task.value
        cachedIdentity = identity
        preparation = nil
        return identity
    }
}

extension ScanFruitConfiguration {
    @MainActor
    /// Compatibility capture for callers that do not yet construct a ScanPlan.
    static func capture(
        selectedCategory: FruitCategory,
        settings: ScanSettingsProviding,
        calibrationRecordsLoader: ScanCalibrationRecordsLoader = {
            try CalibrationRecordPersistence.load()
        }
    ) -> ScanFruitConfiguration {
        let snapshot = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: selectedCategory,
            settings: settings,
            calibrationRecordsLoader: calibrationRecordsLoader
        )
        return snapshot.makeConfiguration(modelIdentity: ScanModelFingerprint.bundledIdentity)
    }
}

struct ScanFruitConfigurationSnapshot: Sendable {
    let selectedCategory: FruitCategory
    let parametersSnapshot: [String: FruitVarietyParams]
    let defaultParams: FruitVarietyParams
    let clusterConfig: ClusterConfig
    let fusionConfig: FruitScanConfig
    /// Captured only to encode the historical calibration contract.
    let legacyFusionSphericityThreshold: Float
    let colorFilter: ColorFilter
    let calibrationRecords: [CalibrationRecord]
    let calibrationWarning: ScanCalibrationWarning?

    @MainActor
    static func capture(
        selectedCategory: FruitCategory,
        settings: ScanSettingsProviding,
        calibrationRecordsLoader: ScanCalibrationRecordsLoader
    ) -> ScanFruitConfigurationSnapshot {
        let parametersSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = parametersSnapshot[selectedCategory.rawValue]
            ?? FruitVarietyParams(category: selectedCategory)
        let clusterConfig = settings.clusterConfig(for: defaultParams)
        let fusionConfig = settings.fruitScanConfig
        let legacyFusionSphericityThreshold = settings.legacyFusionSphericityThreshold
        let colorFilter = settings.colorFilter(for: selectedCategory)

        do {
            return ScanFruitConfigurationSnapshot(
                selectedCategory: selectedCategory,
                parametersSnapshot: parametersSnapshot,
                defaultParams: defaultParams,
                clusterConfig: clusterConfig,
                fusionConfig: fusionConfig,
                legacyFusionSphericityThreshold: legacyFusionSphericityThreshold,
                colorFilter: colorFilter,
                calibrationRecords: try calibrationRecordsLoader(),
                calibrationWarning: nil
            )
        } catch {
            Log.scan.error("Calibration records unavailable at scan start: \(error.localizedDescription)")
            return ScanFruitConfigurationSnapshot(
                selectedCategory: selectedCategory,
                parametersSnapshot: parametersSnapshot,
                defaultParams: defaultParams,
                clusterConfig: clusterConfig,
                fusionConfig: fusionConfig,
                legacyFusionSphericityThreshold: legacyFusionSphericityThreshold,
                colorFilter: colorFilter,
                calibrationRecords: [],
                calibrationWarning: .recordsUnavailable
            )
        }
    }

    func makeConfiguration(
        modelIdentity: ScanModelIdentity,
        experimentConfiguration: FruitScanExperimentConfig = .default,
        resourceBudget: ScanResourceBudget = .default
    ) -> ScanFruitConfiguration {
        let context = YieldCalibrationContext.make(
            parameters: parametersSnapshot,
            cluster: clusterConfig,
            fusion: fusionConfig,
            color: colorFilter,
            modelFingerprint: modelIdentity.fingerprint,
            experimentConfiguration: experimentConfiguration,
            resourceBudget: resourceBudget,
            legacyFusionSphericityThreshold: legacyFusionSphericityThreshold
        )
        let modelWarning: ScanCalibrationWarning?
        switch modelIdentity {
        case .verified(_):
            modelWarning = nil
        case .modelMissing:
            modelWarning = .modelMissing
        case .preparing, .fingerprintUnavailable:
            modelWarning = .modelIdentityUnavailable
        }
        let warning = calibrationWarning ?? modelWarning
        let correction = context.map { context in
            YieldCalibrationCorrector.correction(
                from: calibrationRecords,
                fruitCategory: selectedCategory,
                fruitType: selectedCategory.rawValue,
                requiredAlgorithmRevision: YieldAlgorithmRevision.current,
                requiredContext: context
            )
        } ?? .neutral

        return ScanFruitConfiguration(
            selectedCategory: selectedCategory,
            parametersSnapshot: parametersSnapshot,
            defaultParams: defaultParams,
            clusterConfig: clusterConfig,
            fusionConfig: fusionConfig,
            colorFilter: colorFilter,
            calibrationCorrection: correction,
            calibrationWarning: warning,
            calibrationContext: context,
            modelIdentity: modelIdentity
        )
    }
}

@MainActor
final class ScanPlanFactory {
    let settings: SettingsStore

    private let calibrationRecordsLoader: ScanCalibrationRecordsLoader
    private let modelIdentityProvider: ScanModelIdentityProviding
    private let experimentConfiguration: FruitScanExperimentConfig
    private let resourceBudget: ScanResourceBudget
    private(set) var modelIdentity: ScanModelIdentity = .preparing

    init(
        settings: SettingsStore = .shared,
        calibrationRecordsLoader: @escaping ScanCalibrationRecordsLoader = {
            try CalibrationRecordPersistence.load()
        },
        modelIdentityProvider: ScanModelIdentityProviding = BundledScanModelIdentityProvider(),
        experimentConfiguration: FruitScanExperimentConfig = .default,
        resourceBudget: ScanResourceBudget = .default
    ) {
        self.settings = settings
        self.calibrationRecordsLoader = calibrationRecordsLoader
        self.modelIdentityProvider = modelIdentityProvider
        self.experimentConfiguration = experimentConfiguration
        self.resourceBudget = resourceBudget
    }

    func prepareModelIdentity() async {
        guard modelIdentity == .preparing else { return }
        modelIdentity = await modelIdentityProvider.modelIdentity()
    }

    func makePlan(
        treeID: String,
        season: Season,
        selectedCategory: FruitCategory,
        renderer: Renderer?
    ) -> ScanPlan {
        let particleCapacity = max(renderer?.particlesBuffer.count ?? settings.maxPointCount, 1)
        let snapshot = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: selectedCategory,
            settings: settings,
            calibrationRecordsLoader: calibrationRecordsLoader
        )
        let rendererSettings = RendererScanSettings(
            store: settings,
            particleCapacity: particleCapacity,
            depthConfiguration: experimentConfiguration.depth
        )
        let configuration = snapshot.makeConfiguration(
            modelIdentity: modelIdentity,
            experimentConfiguration: experimentConfiguration,
            resourceBudget: resourceBudget
        )

        if !modelIdentity.canApplyCalibration {
            Log.scan.warning("Scan plan has no verified bundled model identity; local calibration is disabled")
        }

        return ScanPlan(
            treeID: treeID,
            season: season,
            fruitConfiguration: configuration,
            rendererSettings: rendererSettings,
            resourceBudget: resourceBudget,
            requestedCameraResolution: settings.cameraResolution,
            requestedCameraFrameRate: settings.cameraFrameRate,
            autoExportCSV: settings.autoExportCSV,
            modelIdentity: modelIdentity,
            experimentConfiguration: experimentConfiguration
        )
    }
}
