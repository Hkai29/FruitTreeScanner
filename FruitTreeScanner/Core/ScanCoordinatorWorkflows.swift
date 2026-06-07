import ARKit
import os
import QuartzCore
import UIKit

extension ScanCoordinator {
    func startDetectionTimer() {
        // 低频处理最新帧，避免 Vision/CoreML 抢占扫描渲染资源。
        detectionTimer?.invalidate()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.processDetectionQueue()
        }
    }

    @MainActor
    func loadSettings() {
        var detectorConfig = settings.fruitScanConfig
        #if DEBUG
        detectorConfig.minConfidence = DetectionDebugConfiguration.effectiveThreshold(for: detectorConfig.minConfidence)
        #endif
        imageDetector.updateConfig(detectorConfig)
        publishImageDetectorStatus()
        renderer?.applyScanQualitySettings()
    }

    func publishImageDetectorStatus() {
        let modelStatus = imageDetector.modelStatus
        let status = modelStatus.hudLabel
        let detail = modelStatus.hudDetail
        let diagnostics = imageDetector.diagnosticsSnapshot()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            self.hudState?.update(
                visionModelStatus: status,
                visionModelDetail: detail,
                processedImageFrames: diagnostics.processedFrameCount,
                detectedFruitCount: max(self.detectedFruits.count, diagnostics.mappedFruitCount)
            )
        }
    }

    func processDetectionQueue() {
        guard renderer?.isRecording == true else { return }
        guard beginDetectionProcessing() else { return }

        detectionTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.finishDetectionProcessing() }
            let detected = await self.imageDetector.processQueue()
            guard !Task.isCancelled else { return }

            await self.appendDetectedFruits(detected)
        }
    }

    func flushPendingDetections() async {
        if let detectionTask {
            await detectionTask.value
        }
        guard !Task.isCancelled, !isTornDown else { return }
        guard beginDetectionProcessing() else { return }
        defer { finishDetectionProcessing() }

        let detected = await imageDetector.processQueue()
        guard !Task.isCancelled else { return }
        await appendDetectedFruits(detected)
    }

    func appendDetectedFruits(_ detected: [DetectedFruit]) async {
        guard !detected.isEmpty else { return }

        await MainActor.run {
            guard !self.isTornDown else { return }
            self.detectedFruits.append(contentsOf: detected)
        }
    }

    func beginDetectionProcessing() -> Bool {
        detectionProcessingLock.lock()
        defer { detectionProcessingLock.unlock() }
        guard !isDetectionProcessing else { return false }
        isDetectionProcessing = true
        return true
    }

    func finishDetectionProcessing() {
        detectionProcessingLock.lock()
        isDetectionProcessing = false
        detectionProcessingLock.unlock()
    }

    func stopRecording() {
        Log.scan.info("Stopping recording, flushing detection queue")
        processDetectionQueue()
        renderer?.isRecording = false
    }

    func exportPLY(treeID: String, lat: Double, lon: Double,
                   completion: @escaping (String?) -> Void) {
        guard let renderer else {
            Log.export.error("Export failed: renderer is nil")
            completion(nil)
            return
        }

        Log.export.info("Exporting PLY for tree \(treeID)")
        renderer.savePointCloud(treeID: treeID, gpsLat: lat, gpsLon: lon) { filename in
            if let filename {
                Log.export.info("PLY exported: \(filename)")
            } else {
                Log.export.error("PLY export failed: file write error")
            }
            completion(filename)
        }
    }

    func extractColoredPoints() -> [ColoredPoint] {
        guard let r = renderer else { return [] }
        return r.makeAnalysisPoints()
    }

    /// 多模态融合产量估算（新 pipeline）
    @MainActor
    func runMultiModalYieldEstimate(completion: @escaping (YieldResult, FruitCountResult?) -> Void) {
        let frameContext = makeFusionFrameContext()
        let fruitType = settings.fruitType
        let fruitCat = FruitCategory(rawValue: fruitType)
        let paramsSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = fruitCat.flatMap { paramsSnapshot[$0.rawValue] } ?? FruitVarietyParams(category: fruitCat ?? .apple)
        let clusterConfig = settings.clusterConfig(for: defaultParams)
        let fusionConfig = settings.fruitScanConfig
        let colorFilter = fruitCat.map { settings.colorFilter(for: $0) }

        fusionEstimateTask?.cancel()
        fusionEstimateTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.flushPendingDetections()
            guard !Task.isCancelled else { return }

            let points = self.extractColoredPoints()
            let imageDiagnostics = self.imageDetector.diagnosticsSnapshot()
            guard !Task.isCancelled else { return }

            let savedDetections: [DetectedFruit] = await MainActor.run {
                guard !self.isTornDown else { return [] as [DetectedFruit] }
                let saved = self.detectedFruits
                self.detectedFruits.removeAll()
                return saved
            }
            guard !Task.isCancelled else { return }

            Log.fusion.info("Starting yield estimation: \(points.count) points, \(savedDetections.count) detections")
            let (finalResult, countResult) = await ScanFusionYieldBuilder.build(
                from: .init(
                    points: points,
                    savedDetections: savedDetections,
                    imageDiagnostics: imageDiagnostics,
                    frameContext: frameContext,
                    fruitType: fruitType,
                    fruitCategory: fruitCat,
                    paramsSnapshot: paramsSnapshot,
                    defaultParams: defaultParams,
                    clusterConfig: clusterConfig,
                    fusionConfig: fusionConfig,
                    colorFilter: colorFilter
                )
            )
            guard !Task.isCancelled else { return }

            let resultToSend = finalResult
            Log.fusion.info("Yield estimate complete: \(resultToSend.yieldFinalKg, format: .fixed(precision: 2))kg, confidence=\(resultToSend.confidence), method=\(resultToSend.methodUsed)")
            await MainActor.run {
                guard !Task.isCancelled, !self.isTornDown else { return }
                self.hudState?.update(
                    detectedFruitCount: resultToSend.diagnostics.fusedFruitCount,
                    fusionStatus: resultToSend.diagnostics.fusedFruitCount > 0 ? "OK" : "0kg"
                )
                completion(resultToSend, countResult)
            }
        }
    }

    private func makeFusionFrameContext() -> ScanFusionFrameContext? {
        guard let frame = session?.currentFrame else { return nil }

        let depthMap: CVPixelBuffer?
        if let sourceDepthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap {
            depthMap = duplicatePixelBuffer(input: sourceDepthMap)
        } else {
            depthMap = nil
        }

        return ScanFusionFrameContext(
            depthMap: depthMap,
            cameraIntrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            imageSize: CGSize(
                width: CGFloat(frame.camera.imageResolution.width),
                height: CGFloat(frame.camera.imageResolution.height)
            )
        )
    }
}
