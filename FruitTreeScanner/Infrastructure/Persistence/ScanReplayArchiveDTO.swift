import Foundation
import simd

enum ScanReplayError: LocalizedError {
    case invalidArchive
    case budgetExceeded
    case unavailable
    case algorithmMismatch

    var errorDescription: String? {
        let key: String
        switch self {
        case .invalidArchive: key = "replay.error.invalid"
        case .budgetExceeded: key = "replay.error.budget"
        case .unavailable: key = "replay.error.unavailable"
        case .algorithmMismatch: key = "replay.error.version"
        }
        return NSLocalizedString(key, comment: "")
    }
}

enum ScanReplayLimits {
    static let maximumPoints = 120_000
    static let maximumObservations = 4_096
    static let maximumDepthSamples = 81
    static let maximumInputBytes = 8 * 1_024 * 1_024
    static let pointHeaderBytes = 12
    static let pointStrideBytes = 24
    static let maximumPointBytes = pointHeaderBytes + maximumPoints * pointStrideBytes
}

struct ScanReplayBuildIdentity: Codable {
    let schemaVersion: Int
    let sourcesSHA256: String
    let sourceFileCount: Int

    static func current() throws -> Self {
        guard let url = Bundle.main.url(forResource: "ScanReplayBuildIdentity", withExtension: "json"),
              let data = PLYParserHelper.readBoundedCompanionData(at: url, maximumByteCount: 1_024) else {
            throw ScanReplayError.unavailable
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.sourceFileCount > 0,
              value.sourcesSHA256.count == 64, value.sourcesSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ScanReplayError.invalidArchive
        }
        return value
    }
}

protocol ReplayArrayLimit { static var count: Int { get } }
enum ReplayObservationLimit: ReplayArrayLimit { static let count = ScanReplayLimits.maximumObservations }
enum ReplaySampleLimit: ReplayArrayLimit { static let count = ScanReplayLimits.maximumDepthSamples }
enum ReplayMatrixLimit: ReplayArrayLimit { static let count = 16 }
enum ReplayGeometryLimit: ReplayArrayLimit { static let count = 4 }
enum ReplayRejectionLimit: ReplayArrayLimit { static let count = 32 }

/// Count is checked before allocating the array, including for malicious JSON.
struct ReplayArray<Element: Codable & Sendable, Limit: ReplayArrayLimit>: Codable, Sendable {
    let values: [Element]

    init(_ values: [Element]) throws {
        guard values.count <= Limit.count else { throw ScanReplayError.budgetExceeded }
        self.values = values
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count.map({ $0 <= Limit.count }) ?? true else { throw ScanReplayError.budgetExceeded }
        var values: [Element] = []
        while !container.isAtEnd {
            guard values.count < Limit.count else { throw ScanReplayError.budgetExceeded }
            values.append(try container.decode(Element.self))
        }
        self.values = values
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in values { try container.encode(value) }
    }
}

struct ReplayDepthSampleDTO: Codable, Sendable {
    let x: UInt32
    let y: UInt32
    let depth: UInt32
    let row: Int
    let column: Int

    init(_ value: ObservationDepthSample) {
        x = value.normalizedImageX.bitPattern
        y = value.normalizedImageY.bitPattern
        depth = value.depthMeters.bitPattern
        row = value.row
        column = value.column
    }

    var value: ObservationDepthSample {
        .init(normalizedImageX: Float(bitPattern: x), normalizedImageY: Float(bitPattern: y),
              depthMeters: Float(bitPattern: depth), row: row, column: column)
    }
}

struct ReplayObservationDTO: Codable, Sendable {
    let id: UUID
    let frameID: UUID
    let category: FruitCategory
    let boundingBox: ReplayArray<UInt64, ReplayGeometryLimit>
    let confidence: UInt32
    let timestamp: UInt64
    let cameraTransform: ReplayArray<UInt32, ReplayMatrixLimit>?
    let cameraIntrinsics: ReplayArray<UInt32, ReplayMatrixLimit>?
    let imageSize: ReplayArray<UInt64, ReplayGeometryLimit>?
    let coordinateConvention: ObservationCoordinateConvention
    let depthConfidenceProvenance: DepthConfidenceProvenance
    let hasDepthMap: Bool
    let roiDepthSamples: ReplayArray<ReplayDepthSampleDTO, ReplaySampleLimit>
    let projectionDepthSamples: ReplayArray<UInt32, ReplaySampleLimit>
    let rejectionReasons: ReplayArray<ObservationRejectionReason, ReplayRejectionLimit>

    init(_ value: Observation) throws {
        id = value.id
        frameID = value.frameID.rawValue
        category = value.category
        boundingBox = try ReplayArray([value.boundingBox.origin.x, value.boundingBox.origin.y,
                                      value.boundingBox.width, value.boundingBox.height].map { Double($0).bitPattern })
        confidence = value.confidence.bitPattern
        timestamp = value.timestamp.bitPattern
        cameraTransform = try value.cameraTransform.map { matrix in
            try ReplayArray((0..<4).flatMap { column in (0..<4).map { matrix[column][$0].bitPattern } })
        }
        cameraIntrinsics = try value.cameraIntrinsics.map { matrix in
            try ReplayArray((0..<3).flatMap { column in (0..<3).map { matrix[column][$0].bitPattern } })
        }
        imageSize = try value.imageSize.map { try ReplayArray([Double($0.width).bitPattern, Double($0.height).bitPattern]) }
        coordinateConvention = value.coordinateConvention
        depthConfidenceProvenance = value.depthConfidenceProvenance
        hasDepthMap = value.hasDepthMap
        roiDepthSamples = try ReplayArray(value.roiDepthSamples.map(ReplayDepthSampleDTO.init))
        projectionDepthSamples = try ReplayArray(value.projectionDepthSamples.map(\.bitPattern))
        rejectionReasons = try ReplayArray(value.rejectionReasons)
    }

    func value() throws -> Observation {
        guard boundingBox.values.count == 4,
              cameraTransform.map({ $0.values.count == 16 }) ?? true,
              cameraIntrinsics.map({ $0.values.count == 9 }) ?? true,
              imageSize.map({ $0.values.count == 2 }) ?? true else { throw ScanReplayError.invalidArchive }
        let box = boundingBox.values.map(Double.init(bitPattern:))
        let transform = cameraTransform.map { raw -> simd_float4x4 in
            let v = raw.values.map(Float.init(bitPattern:))
            return simd_float4x4(columns: (.init(v[0], v[1], v[2], v[3]), .init(v[4], v[5], v[6], v[7]),
                                          .init(v[8], v[9], v[10], v[11]), .init(v[12], v[13], v[14], v[15])))
        }
        let intrinsics = cameraIntrinsics.map { raw -> simd_float3x3 in
            let v = raw.values.map(Float.init(bitPattern:))
            return simd_float3x3(columns: (.init(v[0], v[1], v[2]), .init(v[3], v[4], v[5]), .init(v[6], v[7], v[8])))
        }
        return Observation(id: id, frameID: FrameID(rawValue: frameID), category: category,
            boundingBox: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]),
            confidence: Float(bitPattern: confidence), timestamp: Double(bitPattern: timestamp),
            cameraTransform: transform, cameraIntrinsics: intrinsics,
            imageSize: imageSize.map { CGSize(width: Double(bitPattern: $0.values[0]), height: Double(bitPattern: $0.values[1])) },
            coordinateConvention: coordinateConvention, depthConfidenceProvenance: depthConfidenceProvenance,
            hasDepthMap: hasDepthMap, roiDepthSamples: roiDepthSamples.values.map(\.value),
            projectionDepthSamples: projectionDepthSamples.values.map(Float.init(bitPattern:)),
            rejectionReasons: rejectionReasons.values)
    }
}

struct ReplayProducerDTO: Codable, Sendable {
    let algorithmRevision: String
    let sourcesSHA256: String
    let inputContractRevision: String
    let modelState: String
    let modelFingerprint: String?
    let analysisInputSampleLimit: Int
    let liveSnapshotSampleLimit: Int
    let retainedDetectionFrameLimit: Int
    let requestedCameraResolution: String
    let requestedCameraFrameRate: String
    let rendererSettings: RendererScanSettings

    init(plan: ScanPlan) throws {
        algorithmRevision = plan.algorithmRevision
        sourcesSHA256 = try ScanReplayBuildIdentity.current().sourcesSHA256
        inputContractRevision = "post-detection-input-v1-20261011"
        switch plan.modelIdentity {
        case .verified: modelState = "verified"
        case .preparing: modelState = "preparing"
        case .modelMissing: modelState = "missing"
        case .fingerprintUnavailable: modelState = "fingerprintUnavailable"
        }
        modelFingerprint = plan.modelIdentity.fingerprint
        analysisInputSampleLimit = plan.resourceBudget.analysisInputSampleLimit
        liveSnapshotSampleLimit = plan.resourceBudget.liveSnapshotSampleLimit
        retainedDetectionFrameLimit = plan.resourceBudget.retainedDetectionFrameLimit
        requestedCameraResolution = plan.requestedCameraResolution
        requestedCameraFrameRate = plan.requestedCameraFrameRate
        rendererSettings = plan.rendererSettings
    }
}

/// Points are stored separately as exact Float32 words. All other builder Input
/// fields are mandatory here unless the original field itself is optional.
struct ScanReplayInputDTO: Codable, Sendable {
    let schemaVersion: Int
    let identity: ScanEvidenceIdentity
    let producer: ReplayProducerDTO
    let pointCount: Int
    let observations: ReplayArray<ReplayObservationDTO, ReplayObservationLimit>
    let imageDiagnostics: ImageDetectionDiagnostics
    let fruitType: String
    let fruitCategory: FruitCategory?
    let paramsSnapshot: [String: FruitVarietyParams]
    let defaultParams: FruitVarietyParams
    let clusterConfig: ClusterConfig
    let fusionConfig: FruitScanConfig
    let colorFilter: ColorFilter?
    let experimentConfiguration: FruitScanExperimentConfig
    let calibrationIdentity: ScanCalibrationIdentity?
    let season: Season
    let calibrationCorrection: YieldCalibrationCorrection
    let categoryVerification: FruitCategoryVerificationSummary?

    init(input: ScanFusionYieldBuilder.Input, identity: ScanEvidenceIdentity, plan: ScanPlan) throws {
        guard identity.capture.context.planID == plan.id,
              input.finalPointCloudIdentity == identity.capture.pointCloud else { throw ScanEvidenceError.mismatchedInput }
        guard input.points.count > 0, input.points.count <= plan.resourceBudget.analysisInputSampleLimit,
              input.observations.count <= ScanReplayLimits.maximumObservations,
              input.paramsSnapshot.count <= 128 else { throw ScanReplayError.budgetExceeded }
        schemaVersion = 1
        self.identity = identity
        producer = try ReplayProducerDTO(plan: plan)
        pointCount = input.points.count
        observations = try ReplayArray(input.observations.map(ReplayObservationDTO.init))
        imageDiagnostics = input.imageDiagnostics
        fruitType = input.fruitType
        fruitCategory = input.fruitCategory
        paramsSnapshot = input.paramsSnapshot
        defaultParams = input.defaultParams
        clusterConfig = input.clusterConfig
        fusionConfig = input.fusionConfig
        colorFilter = input.colorFilter
        experimentConfiguration = input.experimentConfiguration
        calibrationIdentity = input.calibrationIdentity
        season = input.season
        calibrationCorrection = input.calibrationCorrection
        categoryVerification = input.categoryVerification
    }

    func input(points: [ColoredPoint]) throws -> ScanFusionYieldBuilder.Input {
        guard schemaVersion == 1, producer.inputContractRevision == "post-detection-input-v1-20261011",
              pointCount > 0, pointCount <= ScanReplayLimits.maximumPoints, pointCount == points.count,
              producer.analysisInputSampleLimit > 0, producer.analysisInputSampleLimit <= ScanReplayLimits.maximumPoints,
              pointCount <= producer.analysisInputSampleLimit, paramsSnapshot.count <= 128,
              identity.capture.pointCloud.analysisInputSampleLimit.map({ pointCount <= $0 }) ?? true,
              !producer.algorithmRevision.isEmpty, producer.sourcesSHA256.count == 64,
              producer.sourcesSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (1...240_000).contains(producer.liveSnapshotSampleLimit),
              (1...DetectionRetentionPolicy.defaultMaxFrameCount).contains(producer.retainedDetectionFrameLimit),
              ["verified", "preparing", "missing", "fingerprintUnavailable"].contains(producer.modelState),
              (producer.modelState == "verified") == (producer.modelFingerprint != nil) else { throw ScanReplayError.invalidArchive }
        return .init(points: points, observations: try observations.values.map { try $0.value() },
                     imageDiagnostics: imageDiagnostics, fruitType: fruitType, fruitCategory: fruitCategory,
                     paramsSnapshot: paramsSnapshot, defaultParams: defaultParams,
                     clusterConfig: clusterConfig, fusionConfig: fusionConfig, colorFilter: colorFilter,
                     season: season, calibrationCorrection: calibrationCorrection, categoryVerification: categoryVerification,
                     finalPointCloudIdentity: identity.capture.pointCloud, experimentConfiguration: experimentConfiguration,
                     calibrationIdentity: calibrationIdentity)
    }
}
