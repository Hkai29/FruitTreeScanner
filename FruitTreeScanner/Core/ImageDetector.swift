// ImageDetector.swift
// 图像水果检测组件 - 使用 CoreML 模型

import Foundation
import os
import Vision
@preconcurrency import CoreVideo
import simd

// MARK: - ImageDetector

final class ImageDetector: @unchecked Sendable {

    // pixelBuffer is synchronously copied (duplicatePixelBuffer) inside enqueueFrame
    // before QueuedFrame is created, so cross-detectionQueue transfer is safe.
    struct QueuedFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
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

    // CoreML 模型 (由初始化时注入)
    var coreMLModel: VNCoreMLModel?
    private(set) var modelStatus: ImageDetectorModelStatus = .fallback(reason: "模型尚未加载")
    var diagnosticsRecorder = ImageDetectionDiagnosticsRecorder()
    let categoryMapper = FruitCategoryMapper.standard

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
        loadCoreMLModel()
    }

    func updateConfig(_ newConfig: FruitScanConfig) {
        lock.lock()
        defer { lock.unlock() }
        self.config = newConfig
    }

    func configSnapshot() -> FruitScanConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    /// 加载 CoreML 模型
    /// - Important: 调用此方法前需要先将 .mlmodel 文件添加到项目
    private func loadCoreMLModel() {
        // 尝试加载用户训练的模型
        // 如果模型不存在，使用 Vision 内置分类器作为 fallback
        do {
            let loadedModel = try ImageDetectorModelLoader.loadModel(named: "FruitsDetector")
            coreMLModel = loadedModel.model
            modelStatus = .coreML(
                resourceName: loadedModel.resourceName,
                bundleExtension: loadedModel.bundleExtension
            )
            Log.detection.info("CoreML model loaded: \(loadedModel.resourceName)")
            updateModelDiagnostics()
        } catch {
            coreMLModel = nil
            modelStatus = .fallback(reason: error.localizedDescription)
            Log.detection.warning("CoreML model not available, using fallback: \(error.localizedDescription)")
            updateModelDiagnostics()
        }
    }

    func diagnosticsSnapshot() -> ImageDetectionDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticsRecorder.snapshot
    }

    private func updateModelDiagnostics() {
        lock.lock()
        defer { lock.unlock() }
        applyModelStatusToDiagnosticsLocked()
    }

    private func applyModelStatusToDiagnosticsLocked() {
        diagnosticsRecorder.apply(modelStatus: modelStatus)
    }

    // MARK: - Public Methods

    /// Process the queued frames and return detected fruits.
    /// This method performs detection on a background thread.
    func processQueue() async -> [DetectedFruit] {
        let framesToProcess = await drainPendingFrames()
        guard !framesToProcess.isEmpty else { return [] }

        var allDetectedFruits: [DetectedFruit] = []

        for frame in framesToProcess {
            let fruits = await performDetection(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
            let enriched = fruits.map { fruit in
                DetectedFruit(
                    category: fruit.category,
                    boundingBox: fruit.boundingBox,
                    confidence: fruit.confidence,
                    timestamp: fruit.timestamp,
                    cameraTransform: frame.cameraTransform,
                    cameraIntrinsics: frame.cameraIntrinsics,
                    imageSize: frame.imageSize
                )
            }
            allDetectedFruits.append(contentsOf: enriched)
        }

        return allDetectedFruits
    }

    func recordCoreMLDetection(
        observationCount: Int,
        confidenceFilteredCount: Int,
        unmappedObservationCount: Int,
        mappedFruitCount: Int
    ) {
        lock.lock()
        diagnosticsRecorder.recordCoreMLDetection(
            observationCount: observationCount,
            confidenceFilteredCount: confidenceFilteredCount,
            unmappedObservationCount: unmappedObservationCount,
            mappedFruitCount: mappedFruitCount
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
