// YieldEstimateModels.swift
// Shared yield-estimation result and diagnostic models.

import simd

struct FruitInfo {
    let center: SIMD3<Float>
    let radiusM: Float
    let diameterCm: Float
    let volumeCm3: Float
    let weightG: Float
    let pointCount: Int
    let massEstimate: FruitMassEstimate?
}

struct YieldResult: Sendable {
    var nLidar: Int = 0
    var nVisual: Int? = nil
    var correctionK: Float = 1.0
    var yieldBVisibleKg: Float = 0
    var yieldBCorrectedKg: Float = 0
    var meanDiameterCm: Float = 0
    var meanVolumeCm3: Float = 0

    var yieldAKg: Float? = nil

    var yieldFinalKg: Float = 0
    var confidence: String = "low"
    var methodUsed: String = ""
    var note: String = ""

    var treeHeightM: Float = 0
    var crownVolM3: Float = 0

    var clusterEps: Float = 0
    var clusterMinPoints: Int = 0
    var fruitCategory: String = ""
    var colorFilterDesc: String = ""
    var occlusionK: Float = 1.0
    var pointCloudSize: Int = 0
    var diagnostics: ScanYieldDiagnostics = ScanYieldDiagnostics()
    var fruitMassEstimates: [FruitMassEstimate] = []
    var validatedFruits: [ValidatedFruitData] = []
}

struct ScanYieldDiagnostics: Sendable, Equatable {
    var pointCloudPointCount: Int = 0
    var imageDetectionCount: Int = 0
    var deduplicatedImageDetectionCount: Int = 0
    var pointCloudColorFilteredCount: Int = 0
    var pointCloudDenoisedPointCount: Int = 0
    var pointCloudOutlierPointCount: Int = 0
    var pointCloudOutlierRatio: Float = 0
    var pointCloudClusterCandidateCount: Int = 0
    var detectionDepthCandidateCount: Int = 0
    var detectionDepthSupportRatio: Float = 0
    var pointCloudCandidateCount: Int = 0
    var fusedFruitCount: Int = 0
    var validatedFruitCount: Int = 0
    var fusedValidationCount: Int = 0
    var trackedImageFruitCount: Int = 0
    var imageOnlyFruitCount: Int = 0
    var cloudOnlyFruitCount: Int = 0
    var validationSourceReliability: Float = 0
    var localCalibrationCountFactor: Float = 1
    var localCalibrationYieldFactor: Float = 1
    var localCalibrationCountSampleCount: Int = 0
    var localCalibrationYieldSampleCount: Int = 0
    var canopyPointCount: Int = 0
    var canopyPreprocessedPointCount: Int = 0
    var canopyGroundFilteredPointCount: Int = 0
    var canopyTrunkFilteredPointCount: Int = 0
    var canopyNeighborFilteredPointCount: Int = 0
    var canopyClusterCount: Int = 0
    var canopyRobustPointCount: Int = 0
    var canopyHeightM: Float = 0
    var canopyWidthM: Float = 0
    var canopyDepthM: Float = 0
    var canopyOuterVolumeM3: Float = 0
    var canopyVolumeM3: Float = 0
    var canopyEffectiveVolumeCoefficient: Float = 0
    var canopyProjectionXYCoefficient: Float = 0
    var canopyProjectionXZCoefficient: Float = 0
    var canopyProjectionYZCoefficient: Float = 0
    var canopyProjectionEffectiveCoefficient: Float = 0
    var canopyVoxelSizeM: Float = 0
    var canopyPartitionSizeM: Float = 0
    var canopyPartitionCount: Int = 0
    var pointCloudAngleCoverage: Float = 0
    var cameraAngleCoverage: Float = 0
    var scanAngleCoverage: Float = 0
    var cloudOnlyConservativeMode: Bool = false
    var depthAvailable: Bool = false
    var depthConfidenceFailureReason: String = ""
    var imageFramesProcessed: Int = 0
    var imageObservationCount: Int = 0
    var imageConfidenceFilteredCount: Int = 0
    var imageMappedFruitCount: Int = 0
    var imageModelStatus: String = "--"
    var imageModelName: String = "--"
    var imageFailureReason: String = ""
    var imageRuntimeModelLabels: [String] = []
    var imageRuntimeModelLabelsAvailable: Bool = false
    var imageModelLabelCompatibilityStatus: String = "unavailable"
    var imageModelLabelCompatibilityWarnings: [String] = []
    var imageRawDetectedLabels: [String] = []
    var imageMappedCategories: [String] = []
    var imageUnmappedLabels: [String] = []
    var filteredBySelectedFruitTypeCount: Int = 0
    var zeroYieldReasons: [String] = []

    var shortStatus: String {
        if zeroYieldReasons.isEmpty {
            return fusedFruitCount > 0 ? "融合有效" : "等待估算"
        }
        return zeroYieldReasons.joined(separator: "；")
    }
}

enum Season: Sendable {
    case mature
    case off

    var supportsYieldEstimation: Bool {
        self == .mature
    }
}
