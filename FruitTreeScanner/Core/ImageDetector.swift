// ImageDetector.swift
// 图像水果检测组件 - 使用 CoreML 模型

import Foundation
import os
import Vision
@preconcurrency import CoreVideo
import simd

// MARK: - ImageDetector

final class ImageDetector: @unchecked Sendable {

    // RGB, depth, and depth-confidence buffers are synchronously copied
    // (duplicatePixelBuffer) inside enqueueFrame before QueuedFrame is created,
    // so transferring the frame to detectionQueue does not retain ARKit's
    // reusable buffers.
    struct QueuedFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let depthMap: CVPixelBuffer?
        let depthConfidenceMap: CVPixelBuffer?
        let depthConfidenceProvenance: DepthConfidenceProvenance
        let timestamp: TimeInterval
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageSize: CGSize
    }

    struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    // MARK: - Properties

    var config: FruitScanConfig

    let detectionQueue = DispatchQueue(label: "com.fruittreescanner.imagedetector", qos: .userInitiated)
    var pendingFrames: [QueuedFrame] = []
    var frameCounter: Int = 0
    var lastQueuedTimestamp: TimeInterval = 0
    var queueGeneration: Int = 0
    var preparingFrameGeneration: Int?
    let minimumQueueInterval: TimeInterval = 0.45
    let lock = NSLock()
    private let inference = ImageDetectorInference()

    // CoreML 模型 (由初始化时注入)
    var coreMLModel: VNCoreMLModel?
    private(set) var modelStatus: ImageDetectorModelStatus = .fallback(reason: "模型尚未加载")
    private var modelLabelDiagnostics = ModelLabelCompatibilityDiagnostics.unavailable
    var diagnosticsRecorder = ImageDetectorDiagnosticsRecorder()
    var detectionDebugState = DetectionDebugState()
    var detectionFailureSamples: [DetectionFailureSample] = []
    let maxDetectionFailureSamples = 20
    let categoryMapper = FruitCategoryMapper.standard

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
        self.detectionDebugState = DetectionDebugState(currentThreshold: config.minConfidence)
        loadCoreMLModel()
    }

    func updateConfig(_ newConfig: FruitScanConfig) {
        lock.lock()
        defer { lock.unlock() }
        self.config = newConfig
        detectionDebugState.currentThreshold = newConfig.minConfidence
        detectionDebugState.lastUpdatedAt = Date()
    }

    func configSnapshot() -> FruitScanConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    /// 加载 CoreML 模型
    /// - Important: 调用此方法前需要先将 .mlmodel 文件添加到项目
    private func loadCoreMLModel() {
        let loadState = ImageDetectorModelLoader.loadModelState(named: "FruitsDetector")
        coreMLModel = loadState.model
        modelStatus = loadState.status

        if let loadedModel = loadState.loadedModel {
            Log.detection.info(
                "CoreML model loaded: \(loadedModel.displayName), supportedClasses=\(loadedModel.supportedClasses.joined(separator: ","))"
            )
            modelLabelDiagnostics = loadedModel.labelDiagnostics
            updateModelDiagnostics()
            updateModelDebugStateLoaded(loadedModel)
            return
        }

        let failureMessage = loadState.failureMessage ?? "Unknown model load failure"
        Log.detection.error("CoreML model not available, using fallback: \(failureMessage)")
        modelLabelDiagnostics = .unavailable
        updateModelDiagnostics()
        updateModelDebugStateFailure(
            modelName: loadState.failureModelName ?? "FruitsDetector",
            modelURLFound: loadState.failureModelURLFound,
            errorMessage: failureMessage
        )
    }

    func diagnosticsSnapshot() -> ImageDetectionDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticsRecorder.snapshot
    }

    func modelLabelDiagnosticsSnapshot() -> ModelLabelCompatibilityDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return modelLabelDiagnostics
    }

    private func updateModelDiagnostics() {
        lock.lock()
        defer { lock.unlock() }
        applyModelStatusToDiagnosticsLocked()
        applyModelLabelDiagnosticsToDiagnosticsLocked()
    }

    /// Caller must hold `lock` so a queue reset cannot race with diagnostics updates.
    func applyModelLabelDiagnosticsToDiagnosticsLocked() {
        diagnosticsRecorder.apply(labelDiagnostics: modelLabelDiagnostics)
    }

    private func applyModelStatusToDiagnosticsLocked() {
        diagnosticsRecorder.apply(modelStatus: modelStatus)
    }

    private func updateModelDebugStateLoaded(_ loadedModel: ImageDetectorLoadedModel) {
        lock.lock()
        detectionDebugState.markModelLoaded(
            modelName: loadedModel.displayName,
            modelURLFound: true,
            supportedClasses: loadedModel.supportedClasses,
            labelDiagnostics: loadedModel.labelDiagnostics
        )
        lock.unlock()
    }

    private func updateModelDebugStateFailure(
        modelName: String,
        modelURLFound: Bool,
        errorMessage: String
    ) {
        lock.lock()
        detectionDebugState.markModelLoadFailure(
            modelName: modelName,
            modelURLFound: modelURLFound,
            errorMessage: errorMessage
        )
        lock.unlock()
    }

    // MARK: - Public Methods

    /// Process the queued frames and return detected fruits.
    /// This method performs detection on a background thread.
    func processQueue() async -> [DetectedFruit] {
        let framesToProcess = await drainPendingFrames()
        guard !framesToProcess.isEmpty else { return [] }

        var allDetectedFruits: [DetectedFruit] = []

        for frame in framesToProcess {
            let fruits = await inference.performDetection(
                detector: self,
                pixelBuffer: frame.pixelBuffer,
                timestamp: frame.timestamp,
                imageSize: frame.imageSize,
                queue: detectionQueue
            )
            let enriched = ImageDetectorQueue.enrich(fruits, with: frame)
            allDetectedFruits.append(contentsOf: enriched)
        }

        return allDetectedFruits
    }

    func recordCoreMLDetection(
        observationCount: Int,
        confidenceFilteredCount: Int,
        unmappedObservationCount: Int,
        mappedFruitCount: Int,
        rawDetectedLabels: [String] = [],
        mappedCategories: [String] = [],
        unmappedLabels: [String] = []
    ) {
        lock.lock()
        diagnosticsRecorder.recordCoreMLDetection(
            observationCount: observationCount,
            confidenceFilteredCount: confidenceFilteredCount,
            unmappedObservationCount: unmappedObservationCount,
            mappedFruitCount: mappedFruitCount,
            rawDetectedLabels: rawDetectedLabels,
            mappedCategories: mappedCategories,
            unmappedLabels: unmappedLabels
        )
        lock.unlock()
    }

    func recordDetectionFailure(_ reason: String) {
        lock.lock()
        diagnosticsRecorder.recordDetectionFailure(reason)
        lock.unlock()
    }

    func recordFallbackFrame(reason: String) {
        lock.lock()
        diagnosticsRecorder.recordFallbackFrame(reason: reason)
        lock.unlock()
    }

}
