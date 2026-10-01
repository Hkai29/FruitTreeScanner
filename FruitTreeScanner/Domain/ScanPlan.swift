import Foundation

struct ScanCameraRequest: Equatable, Sendable {
    let resolution: String
    let frameRate: String

    var targetFramesPerSecond: Int {
        switch frameRate {
        case "30fps": return 30
        case "120fps": return 120
        default: return 60
        }
    }

    var targetImageWidth: Int {
        switch resolution {
        case "720p": return 1280
        case "4K": return 3840
        default: return 1920
        }
    }
}

enum ScanModelIdentity: Equatable, Sendable {
    case preparing
    case verified(String)
    case modelMissing
    case fingerprintUnavailable

    var fingerprint: String? {
        guard case .verified(let fingerprint) = self else { return nil }
        return fingerprint
    }

    var canApplyCalibration: Bool { fingerprint != nil }
}

struct ScanResourceBudget: Equatable, Sendable, Encodable {
    let liveSnapshotSampleLimit: Int
    let analysisInputSampleLimit: Int
    /// The live detection window. Stable archived evidence has its own track bound.
    let retainedDetectionFrameLimit: Int

    static let `default` = ScanResourceBudget()

    init(
        liveSnapshotSampleLimit: Int = 240_000,
        analysisInputSampleLimit: Int = 120_000,
        retainedDetectionFrameLimit: Int = DetectionRetentionPolicy.defaultMaxFrameCount
    ) {
        self.liveSnapshotSampleLimit = min(max(liveSnapshotSampleLimit, 1), 240_000)
        self.analysisInputSampleLimit = min(max(analysisInputSampleLimit, 1), 120_000)
        self.retainedDetectionFrameLimit = min(max(retainedDetectionFrameLimit, 1), DetectionRetentionPolicy.defaultMaxFrameCount)
    }
}

/// Immutable values for one scan. Settings, file access, and model preparation
/// belong to the application factory, not this value or its lifecycle owner.
struct ScanPlan: Sendable {
    let id: UUID
    let treeID: String
    let season: Season
    let fruitConfiguration: ScanFruitConfiguration
    let rendererSettings: RendererScanSettings
    let resourceBudget: ScanResourceBudget
    let requestedCameraResolution: String
    let requestedCameraFrameRate: String
    let autoExportCSV: Bool
    let modelIdentity: ScanModelIdentity
    let algorithmRevision: String
    let experimentConfiguration: FruitScanExperimentConfig

    var cameraRequest: ScanCameraRequest {
        ScanCameraRequest(resolution: requestedCameraResolution, frameRate: requestedCameraFrameRate)
    }

    init(
        id: UUID = UUID(),
        treeID: String,
        season: Season,
        fruitConfiguration: ScanFruitConfiguration,
        rendererSettings: RendererScanSettings,
        resourceBudget: ScanResourceBudget,
        requestedCameraResolution: String,
        requestedCameraFrameRate: String,
        autoExportCSV: Bool,
        modelIdentity: ScanModelIdentity,
        algorithmRevision: String = YieldAlgorithmRevision.current,
        experimentConfiguration: FruitScanExperimentConfig = .default
    ) {
        self.id = id
        self.treeID = treeID
        self.season = season
        self.fruitConfiguration = fruitConfiguration
        self.rendererSettings = rendererSettings
        self.resourceBudget = resourceBudget
        self.requestedCameraResolution = requestedCameraResolution
        self.requestedCameraFrameRate = requestedCameraFrameRate
        self.autoExportCSV = autoExportCSV
        self.modelIdentity = modelIdentity
        self.algorithmRevision = algorithmRevision
        self.experimentConfiguration = experimentConfiguration
    }
}

struct ScanFruitConfiguration: Sendable {
    let selectedCategory: FruitCategory
    let parametersSnapshot: [String: FruitVarietyParams]
    let defaultParams: FruitVarietyParams
    let clusterConfig: ClusterConfig
    let fusionConfig: FruitScanConfig
    let colorFilter: ColorFilter
    let calibrationCorrection: YieldCalibrationCorrection
    let calibrationWarning: ScanCalibrationWarning?
    let calibrationContext: String?
    let modelIdentity: ScanModelIdentity
}

enum ScanCalibrationWarning: Equatable, Sendable {
    case recordsUnavailable
    case modelMissing
    case modelIdentityUnavailable
}

/// An absent context is an explicit unavailable identity, not permission to
/// recompute one from whichever model/settings happen to be available later.
struct ScanCalibrationIdentity: Equatable, Sendable {
    let algorithmRevision: String
    let context: String?
}
