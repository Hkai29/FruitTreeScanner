// ImageDetector.swift
// 图像水果检测组件 - 使用 CoreML 模型

import Foundation
import Vision
import CoreVideo

// MARK: - ImageDetectorDelegate

protocol ImageDetectorDelegate: AnyObject {
    func imageDetector(_ detector: ImageDetector, didDetect fruits: [DetectedFruit])
}

// MARK: - ImageDetector

final class ImageDetector {

    // MARK: - Properties

    weak var delegate: ImageDetectorDelegate?
    var config: FruitScanConfig

    private let detectionQueue = DispatchQueue(label: "com.fruittreescanner.imagedetector", qos: .userInitiated)
    private var pendingFrames: [(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval)] = []
    private var frameCounter: Int = 0
    private let lock = NSLock()

    // CoreML 模型 (由初始化时注入)
    private var coreMLModel: VNCoreMLModel?

    // 水果类别映射（COCO 类别 ID -> FruitCategory）
    // YOLOv8 COCO 模型输出的是类别 ID，不是字符串
    private let cocoCategoryMapping: [Int: FruitCategory] = [
        77: .apple,    // COCO apple
        78: .orange,   // COCO orange
        52: .pear,     // COCO banana (最接近)
    ]

    // 字符串到 FruitCategory 的映射（用于 fallback 或 Vision 内置分类器）

    private let stringCategoryMapping: [String: FruitCategory] = [
        "apple": .apple,
        "orange": .orange,
        "pear": .pear,
        "peach": .peach,
        "cherry": .cherry,
        "banana": .pear  // COCO banana 映射为梨
    ]

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
        loadCoreMLModel()
    }

    func updateConfig(_ newConfig: FruitScanConfig) {
        self.config = newConfig
    }

    /// 加载 CoreML 模型
    /// - Important: 调用此方法前需要先将 .mlmodel 文件添加到项目
    private func loadCoreMLModel() {
        // 尝试加载用户训练的模型
        // 如果模型不存在，使用 Vision 内置分类器作为 fallback
        if let model = try? loadModel(named: "FruitsDetector") {
            coreMLModel = model
            print("ImageDetector: CoreML model loaded successfully")
        } else {
            print("ImageDetector: Using Vision built-in classifier (no custom model found)")
        }
    }

    private func loadModel(named name: String) throws -> VNCoreMLModel {
        // 尝试从 bundle 加载 CoreML 模型
        // 注意：.mlmodelc 是已编译的模型目录，直接使用；.mlmodel 需要编译
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            // .mlmodelc 已编译，直接加载
            print("🔍 [ImageDetector] 找到已编译模型: \(name).mlmodelc")
            let mlModel = try MLModel(contentsOf: modelURL)
            let model = try VNCoreMLModel(for: mlModel)
            print("🔍 [ImageDetector] 模型加载成功!")
            return model
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            // .mlmodel 需要先编译
            print("🔍 [ImageDetector] 找到未编译模型: \(name).mlmodel，开始编译...")
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            print("🔍 [ImageDetector] 模型编译并加载成功!")
            return model
        }

        throw NSError(domain: "ImageDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(name)"])
    }

    // MARK: - Public Methods

    /// Enqueue a frame for detection. Frames are sampled based on imageDetectionInterval.
    func enqueueFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        frameCounter += 1

        // Only enqueue frames at the configured interval
        guard frameCounter % config.imageDetectionInterval == 0 else {
            return
        }

        pendingFrames.append((pixelBuffer: pixelBuffer, timestamp: timestamp))
    }

    /// Process the queued frames and return detected fruits.
    /// This method performs detection on a background thread.
    func processQueue() async -> [DetectedFruit] {
        lock.lock()
        guard !pendingFrames.isEmpty else {
            lock.unlock()
            return []
        }
        let framesToProcess = pendingFrames
        pendingFrames.removeAll()
        lock.unlock()

        var allDetectedFruits: [DetectedFruit] = []

        for frame in framesToProcess {
            let fruits = await performDetection(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
            allDetectedFruits.append(contentsOf: fruits)
        }

        return allDetectedFruits
    }

    // MARK: - Private Methods

    /// Perform CoreML-based detection on a single frame.
    private func performDetection(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async -> [DetectedFruit] {
        return await withCheckedContinuation { continuation in
            detectionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                if let model = self.coreMLModel {
                    // 使用自定义 CoreML 模型
                    self.performCoreMLDetection(pixelBuffer: pixelBuffer, timestamp: timestamp, model: model, completion: { fruits in
                        continuation.resume(returning: fruits)
                    })
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
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self,
                  error == nil,
                  let observations = request.results as? [VNRecognizedObjectObservation] else {
                print("🔍 [ImageDetector] CoreML观察结果为空或出错: \(error?.localizedDescription ?? "无结果")")
                completion([])
                return
            }

            print("🔍 [ImageDetector] 检测到 \(observations.count) 个物体候选")
            for obs in observations {
                print("      类别: \(obs.labels.first?.identifier ?? "未知"), 置信度: \(obs.confidence)")
            }

            let detectedFruits = self.mapObjectObservationsToFruits(observations: observations, timestamp: timestamp)
            print("🔍 [ImageDetector] 映射后得到 \(detectedFruits.count) 个果实")
            completion(detectedFruits)
        }

        // 配置请求
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("ImageDetector: CoreML detection failed - \(error.localizedDescription)")
            completion([])
        }
    }

    /// 将 Vision 目标检测结果映射到 DetectedFruit
    private func mapObjectObservationsToFruits(observations: [VNRecognizedObjectObservation], timestamp: TimeInterval) -> [DetectedFruit] {
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

            // 尝试用字符串匹配（COCO 类别名称）
            if let mapped = self.stringCategoryMapping[topLabel.identifier.lowercased()] {
                category = mapped
            }
            // 尝试用数字 ID 匹配（COCO 类别 ID）
            else if let cocoID = Int(topLabel.identifier), let mapped = self.cocoCategoryMapping[cocoID] {
                category = mapped
            }

            if let fruitCategory = category {
                print("🔍 [ImageDetector] 映射成功: \(topLabel.identifier) -> \(fruitCategory.displayName)")
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
    private func performVisionClassification(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let classifyRequest = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self,
                  error == nil,
                  let observations = request.results as? [VNClassificationObservation] else {
                completion([])
                return
            }

            let detectedFruits = self.mapObservationsToFruits(observations: observations, timestamp: timestamp)
            completion(detectedFruits)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([classifyRequest])
        } catch {
            print("ImageDetector: Vision classification failed - \(error.localizedDescription)")
            completion([])
        }
    }

    /// 将 Vision 分类结果映射到水果 (Fallback)
    private func mapObservationsToFruits(observations: [VNClassificationObservation], timestamp: TimeInterval) -> [DetectedFruit] {
        var detectedFruits: [DetectedFruit] = []

        // 过滤高于置信度阈值的观察结果
        let filteredObservations = observations.filter { $0.confidence >= config.minConfidence }

        for observation in filteredObservations {
            if let category = mapIdentifierToFruitCategory(observation.identifier) {
                // 使用占位符边界框 (分类无法提供定位)
                let boundingBox = createPlaceholderBoundingBox(for: observation)

                let fruit = DetectedFruit(
                    category: category,
                    boundingBox: boundingBox,
                    confidence: observation.confidence,
                    timestamp: timestamp
                )
                detectedFruits.append(fruit)
            }
        }

        return detectedFruits
    }

    /// 映射分类标识符到水果类别
    /// 注意：Vision 内置分类器的 fallback 映射必须非常严格
    /// 只有明确包含水果名称时才匹配，避免误判普通物体
    private func mapIdentifierToFruitCategory(_ identifier: String) -> FruitCategory? {
        let lowercaseIdentifier = identifier.lowercased()

        // 必须同时包含 "fruit" 和具体水果名称才算匹配
        let hasFruit = lowercaseIdentifier.contains("fruit")

        if hasFruit && lowercaseIdentifier.contains("apple") {
            return .apple
        } else if hasFruit && (lowercaseIdentifier.contains("orange") || lowercaseIdentifier.contains("citrus")) {
            return .orange
        } else if hasFruit && lowercaseIdentifier.contains("pear") {
            return .pear
        } else if hasFruit && lowercaseIdentifier.contains("peach") {
            return .peach
        } else if hasFruit && lowercaseIdentifier.contains("cherry") {
            return .cherry
        }

        // 对于没有 "fruit" 字样的，明确的水果名称也接受
        if lowercaseIdentifier == "apple" || lowercaseIdentifier == "orange" ||
           lowercaseIdentifier == "pear" || lowercaseIdentifier == "peach" ||
           lowercaseIdentifier == "cherry" {
            return FruitCategory(rawValue: lowercaseIdentifier)
        }

        return nil
    }

    /// 创建占位符边界框
    /// 注意: Vision 分类器不提供边界框，这里返回中心区域
    private func createPlaceholderBoundingBox(for observation: VNClassificationObservation) -> CGRect {
        return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    }
}
