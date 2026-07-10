import Foundation

private struct ScanYieldEstimationSnapshot: @unchecked Sendable {
    var input: ScanFusionYieldBuilder.Input
}

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
        detectorConfig.minConfidence = DetectionDebugConfiguration.effectiveThreshold(for: detectorConfig.minConfidence)
        imageDetector.updateConfig(detectorConfig)
        publishImageDetectorStatus()
        renderer?.applyScanQualitySettings()
    }

    func publishImageDetectorStatus() {
        let modelStatus = imageDetector.modelStatus
        let status = modelStatus.hudLabel
        let detail = modelStatus.hudDetail
        let diagnostics = imageDetector.diagnosticsSnapshot()
        let detectorConfig = imageDetector.configSnapshot()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            let stableFruitCount = self.confirmedLiveFruitCount(detectorConfig: detectorConfig)
            self.hudState?.update(
                visionModelStatus: status,
                visionModelDetail: detail,
                processedImageFrames: diagnostics.processedFrameCount,
                detectedFruitCount: stableFruitCount
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
        let detectorConfig = imageDetector.configSnapshot()

        await MainActor.run {
            guard !self.isTornDown else { return }
            self.detectedFruits.append(contentsOf: detected)
            self.archiveStableFusionEvidence(detectorConfig: detectorConfig)
            self.detectedFruits = DetectionRetentionPolicy.trimmedByFrameLimit(self.detectedFruits)
        }
    }

    func archiveStableFusionEvidence(detectorConfig: FruitScanConfig) {
        let minimumObservations = max(detectorConfig.minimumStableDetectionsForYield, 2)
        let minimumConfidence = max(detectorConfig.minConfidence, 0.85)
        let stableEvidence = DetectionDeduplicator.stableEvidenceDetections(
            detectedFruits.filter(\.hasAlignedDepthContext),
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: detectorConfig.stableDetectionTimeWindow
        )
        guard !stableEvidence.isEmpty else { return }

        var archivedIDs = Set(archivedFusionEvidenceDetections.map(\.id))
        for detection in stableEvidence where archivedIDs.insert(detection.id).inserted {
            archivedFusionEvidenceDetections.append(detection)
        }
        archivedFusionEvidenceDetections = DetectionDeduplicator.compactStableEvidenceDetections(
            archivedFusionEvidenceDetections,
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: detectorConfig.stableDetectionTimeWindow,
            maxObservationsPerTrack: max(minimumObservations, 3)
        )
    }

    func fusionEstimateDetectionsSnapshot() -> [DetectedFruit] {
        var seenIDs = Set<UUID>()
        var snapshot: [DetectedFruit] = []
        snapshot.reserveCapacity(archivedFusionEvidenceDetections.count + detectedFruits.count)

        for detection in archivedFusionEvidenceDetections + detectedFruits
            where seenIDs.insert(detection.id).inserted {
            snapshot.append(detection)
        }
        return snapshot
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

    @MainActor
    func startRecording() {
        detectionTask?.cancel()
        detectionTask = nil
        invalidateYieldEstimationRequest()
        imageDetector.clearQueue()
        createDirectory(folder: "scans")
        pointCount = 0
        scannedRegionCount = 0
        coveragePercent = 0
        coverageVoxelCount = 0
        scanCompletion = ScanCompletion()
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
        hudState?.resetForNewScan()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "扫描中")
        lastCameraPosition = nil
        lastCameraSpeedTime = 0
        smoothedCameraSpeed = 0
        renderer?.currentFolder = "scans"
        renderer?.isRecording = true
    }

    @MainActor
    func resumeRecordingPreservingCapture() {
        // This is the same logical scan. Keep the in-flight detection task and
        // queued frames so stopping briefly does not discard image evidence
        // that still needs to be fused with the preserved point cloud.
        invalidateYieldEstimationRequest()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "补扫中")
        renderer?.currentFolder = "scans"
        renderer?.resumeRecordingPreservingPointCloud()
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

    func beginYieldEstimationRequest() -> UInt64 {
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
        return yieldEstimationRequestGate.beginRequest()
    }

    func invalidateYieldEstimationRequest() {
        yieldEstimationRequestGate.invalidate()
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
    }

    @MainActor
    private func makeYieldEstimationSnapshot(season: Season) -> ScanYieldEstimationSnapshot? {
        guard !isTornDown else { return nil }

        let fruitType = settings.fruitType
        let fruitCategory = FruitCategory(rawValue: fruitType)
        let paramsSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = fruitCategory.flatMap { paramsSnapshot[$0.rawValue] }
            ?? FruitVarietyParams(category: fruitCategory ?? .apple)
        let clusterConfig = settings.clusterConfig(for: defaultParams)
        let fusionConfig = settings.fruitScanConfig
        let colorFilter = fruitCategory.map { settings.colorFilter(for: $0) }

        archiveStableFusionEvidence(detectorConfig: fusionConfig)
        let savedDetections = fusionEstimateDetectionsSnapshot()
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()

        return ScanYieldEstimationSnapshot(
            input: .init(
                points: extractColoredPoints(),
                savedDetections: savedDetections,
                imageDiagnostics: imageDetector.diagnosticsSnapshot(),
                fruitType: fruitType,
                fruitCategory: fruitCategory,
                paramsSnapshot: paramsSnapshot,
                defaultParams: defaultParams,
                clusterConfig: clusterConfig,
                fusionConfig: fusionConfig,
                colorFilter: colorFilter,
                season: season
            )
        )
    }

    @MainActor
    func commitYieldEstimationResult(
        _ result: YieldResult,
        countResult: FruitCountResult,
        generation: UInt64,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
        guard yieldEstimationRequestGate.accepts(generation), !isTornDown else { return }

        fusionEstimateTask = nil
        hudState?.update(
            detectedFruitCount: result.diagnostics.fusedFruitCount,
            fusionStatus: result.diagnostics.fusedFruitCount > 0 ? "OK" : "0kg"
        )
        completion(result, countResult)
    }

    /// 多模态融合产量估算（新 pipeline）
    @MainActor
    func runMultiModalYieldEstimate(
        season: Season = .mature,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
        let generation = beginYieldEstimationRequest()

        fusionEstimateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.flushPendingDetections()
            guard !Task.isCancelled,
                  self.yieldEstimationRequestGate.accepts(generation),
                  let snapshot = self.makeYieldEstimationSnapshot(season: season) else {
                return
            }

            let estimateTask = Task.detached(priority: .userInitiated) { [weak self, snapshot] in
                let calibrationRecords = (try? CalibrationRecordPersistence.load()) ?? []
                var input = snapshot.input
                input.calibrationCorrection = YieldCalibrationCorrector.correction(
                    from: calibrationRecords,
                    fruitCategory: input.fruitCategory,
                    fruitType: input.fruitType
                )
                guard !Task.isCancelled else { return }

                Log.fusion.info("Starting yield estimation: \(input.points.count) points, \(input.savedDetections.count) detections")
                let (result, countResult) = await ScanFusionYieldBuilder.build(from: input)
                guard !Task.isCancelled else { return }

                Log.fusion.info("Yield estimate complete: \(result.yieldFinalKg, format: .fixed(precision: 2))kg, confidence=\(result.confidence), method=\(result.methodUsed)")
                await self?.commitYieldEstimationResult(
                    result,
                    countResult: countResult,
                    generation: generation,
                    completion: completion
                )
            }

            guard self.yieldEstimationRequestGate.accepts(generation) else {
                estimateTask.cancel()
                return
            }
            self.fusionEstimateTask = estimateTask
        }
    }

}
