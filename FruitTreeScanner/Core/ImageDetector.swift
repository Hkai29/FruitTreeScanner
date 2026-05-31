// ImageDetector.swift
// 图像水果检测组件 - 使用 CoreML 模型

import Foundation
import Vision
@preconcurrency import CoreVideo
import simd

// MARK: - ImageDetectorDelegate

protocol ImageDetectorDelegate: AnyObject {
    func imageDetector(_ detector: ImageDetector, didDetect fruits: [DetectedFruit])
}

// MARK: - ImageDetector

final class ImageDetector: @unchecked Sendable {

    private struct QueuedFrame {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageSize: CGSize
    }

    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    // MARK: - Properties

    weak var delegate: ImageDetectorDelegate?
    private var config: FruitScanConfig

    private let detectionQueue = DispatchQueue(label: "com.fruittreescanner.imagedetector", qos: .userInitiated)
    private var pendingFrames: [QueuedFrame] = []
    private var frameCounter: Int = 0
    private var lastQueuedTimestamp: TimeInterval = 0
    private var queueGeneration: Int = 0
    private var preparingFrameGeneration: Int?
    private let minimumQueueInterval: TimeInterval = 0.45
    private let lock = NSLock()

    // CoreML 模型 (由初始化时注入)
    private var coreMLModel: VNCoreMLModel?

    // 自定义训练模型类别 ID (0-25) -> FruitCategory
    // 与 FruitCategory.allCases 顺序一致，匹配 train_yolov8.py 中 FRUIT_CLASSES_26
    private let customModelCategoryMapping: [Int: FruitCategory] = [
        0:  .apple,
        1:  .orange,
        2:  .mandarin,
        3:  .pomelo,
        4:  .pear,
        5:  .peach,
        6:  .cherry,
        7:  .grape,
        8:  .persimmon,
        9:  .mango,
        10: .kiwi,
        11: .plum,
        12: .pomegranate,
        13: .loquat,
        14: .lychee,
        15: .longan,
        16: .bayberry,
        17: .jujube,
        18: .hawthorn,
        19: .fig,
        20: .papaya,
        21: .chestnut,
        22: .mulberry,
        23: .blueberry,
        24: .strawberry,
        25: .coconut,
    ]

    // COCO 预训练模型类别 ID -> FruitCategory (fallback)
    private let cocoCategoryMapping: [Int: FruitCategory] = [
        77: .apple,
        78: .orange,
        52: .pear,
    ]

    // 字符串到 FruitCategory 的映射（自定义模型输出字符串名称 / Vision 内置分类器）
    private let stringCategoryMapping: [String: FruitCategory] = [
        "apple": .apple,
        "orange": .orange,
        "mandarin": .mandarin,
        "tangerine": .mandarin,
        "clementine": .mandarin,
        "pomelo": .pomelo,
        "pear": .pear,
        "peach": .peach,
        "cherry": .cherry,
        "grape": .grape,
        "persimmon": .persimmon,
        "mango": .mango,
        "kiwi": .kiwi,
        "kiwifruit": .kiwi,
        "plum": .plum,
        "pomegranate": .pomegranate,
        "loquat": .loquat,
        "lychee": .lychee,
        "lichee": .lychee,
        "longan": .longan,
        "bayberry": .bayberry,
        "waxberry": .bayberry,
        "jujube": .jujube,
        "hawthorn": .hawthorn,
        "fig": .fig,
        "papaya": .papaya,
        "chestnut": .chestnut,
        "mulberry": .mulberry,
        "blueberry": .blueberry,
        "strawberry": .strawberry,
        "coconut": .coconut,
        "banana": .pear,
    ]

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

    private func configSnapshot() -> FruitScanConfig {
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
            coreMLModel = try loadModel(named: "FruitsDetector")
            #if DEBUG
            print("ImageDetector: CoreML model loaded successfully")
            #endif
        } catch {
            #if DEBUG
            print("[ImageDetector] Failed to load CoreML model: \(error)")
            print("ImageDetector: Using Vision built-in classifier (no custom model found)")
            #endif
        }
    }

    private func loadModel(named name: String) throws -> VNCoreMLModel {
        // 尝试从 bundle 加载 CoreML 模型
        // 注意：.mlmodelc 是已编译的模型目录，直接使用；.mlmodel 需要编译
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            // .mlmodelc 已编译，直接加载
            #if DEBUG
            print("🔍 [ImageDetector] 找到已编译模型: \(name).mlmodelc")
            #endif
            let mlModel = try MLModel(contentsOf: modelURL)
            let model = try VNCoreMLModel(for: mlModel)
            #if DEBUG
            print("🔍 [ImageDetector] 模型加载成功!")
            #endif
            return model
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            // .mlmodel 需要先编译
            #if DEBUG
            print("🔍 [ImageDetector] 找到未编译模型: \(name).mlmodel，开始编译...")
            #endif
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            #if DEBUG
            print("🔍 [ImageDetector] 模型编译并加载成功!")
            #endif
            return model
        }

        throw NSError(domain: "ImageDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(name)"])
    }

    // MARK: - Public Methods

    /// Enqueue a frame for detection. Frames are sampled based on imageDetectionInterval.
    func enqueueFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize
    ) {
        lock.lock()
        frameCounter += 1

        // Only enqueue frames at the configured interval.
        let detectionInterval = max(config.imageDetectionInterval, 1)
        if frameCounter % detectionInterval != 0 {
            lock.unlock()
            return
        }

        if timestamp - lastQueuedTimestamp < minimumQueueInterval {
            lock.unlock()
            return
        }

        if !pendingFrames.isEmpty || preparingFrameGeneration != nil {
            lock.unlock()
            return
        }

        // Reserve this sampling slot, then copy off the ARSession delegate path.
        lastQueuedTimestamp = timestamp
        let generation = queueGeneration
        preparingFrameGeneration = generation
        lock.unlock()

        let sourcePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        detectionQueue.async { [weak self, sourcePixelBuffer, timestamp, cameraTransform, cameraIntrinsics, imageSize, generation] in
            let copiedPixelBuffer = duplicatePixelBuffer(input: sourcePixelBuffer.value)
            let queuedFrame = QueuedFrame(
                pixelBuffer: copiedPixelBuffer,
                timestamp: timestamp,
                cameraTransform: cameraTransform,
                cameraIntrinsics: cameraIntrinsics,
                imageSize: imageSize
            )

            self?.finishPreparingFrame(queuedFrame, generation: generation)
        }
    }

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

    func clearQueue() {
        lock.lock()
        pendingFrames.removeAll()
        frameCounter = 0
        lastQueuedTimestamp = 0
        queueGeneration &+= 1
        preparingFrameGeneration = nil
        lock.unlock()
    }

    private func finishPreparingFrame(_ queuedFrame: QueuedFrame, generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        if preparingFrameGeneration == generation {
            preparingFrameGeneration = nil
        }
        guard generation == queueGeneration else { return }
        guard pendingFrames.isEmpty else { return }
        pendingFrames.append(queuedFrame)
    }

    private func drainPendingFrames() async -> [QueuedFrame] {
        let maxAttempts = 6
        for _ in 0..<maxAttempts {
            let drainResult = drainPendingFramesIfReady()
            if !drainResult.frames.isEmpty || !drainResult.isPreparing {
                return drainResult.frames
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        return drainPendingFramesIfReady().frames
    }

    private func drainPendingFramesIfReady() -> (frames: [QueuedFrame], isPreparing: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard !pendingFrames.isEmpty else {
            return ([], preparingFrameGeneration != nil)
        }

        let framesToProcess = pendingFrames
        pendingFrames.removeAll()
        return (framesToProcess, preparingFrameGeneration != nil)
    }

    // MARK: - Private Methods

    /// Perform CoreML-based detection on a single frame.
    private func performDetection(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async -> [DetectedFruit] {
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let config = configSnapshot()

        return await withCheckedContinuation { continuation in
            detectionQueue.async { [weak self, sendablePixelBuffer, config] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                let pixelBuffer = sendablePixelBuffer.value
                if let model = self.coreMLModel {
                    // 使用自定义 CoreML 模型
                    self.performCoreMLDetection(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp,
                        model: model,
                        config: config,
                        completion: { fruits in
                            continuation.resume(returning: fruits)
                        }
                    )
                } else {
                    // Fallback: 使用 Vision 内置分类器
                    self.performVisionClassification(pixelBuffer: pixelBuffer, timestamp: timestamp, completion: { fruits in
                        continuation.resume(returning: fruits)
                    })
                }
            }
        }
    }

    /// 使用自定义 CoreML 模型进行目标检测
    private func performCoreMLDetection(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        model: VNCoreMLModel,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self,
                  error == nil,
                  let observations = request.results as? [VNRecognizedObjectObservation] else {
                #if DEBUG
                print("🔍 [ImageDetector] CoreML观察结果为空或出错: \(error?.localizedDescription ?? "无结果")")
                #endif
                completion([])
                return
            }

            #if DEBUG
            print("🔍 [ImageDetector] 检测到 \(observations.count) 个物体候选")
            for obs in observations {
                print("      类别: \(obs.labels.first?.identifier ?? "未知"), 置信度: \(obs.confidence)")
            }
            #endif

            let detectedFruits = self.mapObjectObservationsToFruits(
                observations: observations,
                timestamp: timestamp,
                config: config
            )
            #if DEBUG
            print("🔍 [ImageDetector] 映射后得到 \(detectedFruits.count) 个果实")
            #endif
            completion(detectedFruits)
        }

        // 配置请求
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("ImageDetector: CoreML detection failed - \(error.localizedDescription)")
            #endif
            completion([])
        }
    }

    /// 将 Vision 目标检测结果映射到 DetectedFruit
    private func mapObjectObservationsToFruits(
        observations: [VNRecognizedObjectObservation],
        timestamp: TimeInterval,
        config: FruitScanConfig
    ) -> [DetectedFruit] {
        var detectedFruits: [DetectedFruit] = []

        for observation in observations {
            // 检查置信度阈值
            guard observation.confidence >= config.minConfidence else {
                continue
            }

            // 获取最高置信度的标签
            guard let topLabel = observation.labels.first else {
                continue
            }

            var category: FruitCategory?

            // 1. 尝试自定义模型数字 ID (0-25)
            if let customID = Int(topLabel.identifier), let mapped = self.customModelCategoryMapping[customID] {
                category = mapped
            }
            // 2. 尝试字符串匹配（自定义模型输出名称 / COCO 类别名称）
            else if let mapped = self.stringCategoryMapping[topLabel.identifier.lowercased()] {
                category = mapped
            }
            // 3. 尝试 COCO 数字 ID 匹配 (fallback)
            else if let cocoID = Int(topLabel.identifier), let mapped = self.cocoCategoryMapping[cocoID] {
                category = mapped
            }

            if let fruitCategory = category {
                #if DEBUG
                print("🔍 [ImageDetector] 映射成功: \(topLabel.identifier) -> \(fruitCategory.displayName)")
                #endif
                let fruit = DetectedFruit(
                    category: fruitCategory,
                    boundingBox: observation.boundingBox,
                    confidence: topLabel.confidence,
                    timestamp: timestamp
                )
                detectedFruits.append(fruit)
            }
        }

        return detectedFruits
    }

    /// 使用 Vision 内置分类器 (Fallback)
    /// 注意：分类器只提供类别，不提供位置，无法用于 2D→3D 投影
    /// 因此 fallback 模式只记录类别信息，不产生带边界框的 DetectedFruit
    private func performVisionClassification(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        completion([])
    }
}
