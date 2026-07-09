import Foundation

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
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
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
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
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

    /// 多模态融合产量估算（新 pipeline）
    @MainActor
    func runMultiModalYieldEstimate(
        season: Season = .mature,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
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
            let calibrationRecords = (try? CalibrationRecordPersistence.load()) ?? []
            let calibrationCorrection = YieldCalibrationCorrector.correction(
                from: calibrationRecords,
                fruitCategory: fruitCat,
                fruitType: fruitType
            )
            guard !Task.isCancelled else { return }

            let savedDetections: [DetectedFruit] = await MainActor.run {
                guard !self.isTornDown else { return [] as [DetectedFruit] }
                self.archiveStableFusionEvidence(detectorConfig: fusionConfig)
                let saved = self.fusionEstimateDetectionsSnapshot()
                self.detectedFruits.removeAll()
                self.archivedFusionEvidenceDetections.removeAll()
                return saved
            }
            guard !Task.isCancelled else { return }

            Log.fusion.info("Starting yield estimation: \(points.count) points, \(savedDetections.count) detections")
            let (finalResult, countResult) = await ScanFusionYieldBuilder.build(
                from: .init(
                    points: points,
                    savedDetections: savedDetections,
                    imageDiagnostics: imageDiagnostics,
                    fruitType: fruitType,
                    fruitCategory: fruitCat,
                    paramsSnapshot: paramsSnapshot,
                    defaultParams: defaultParams,
                    clusterConfig: clusterConfig,
                    fusionConfig: fusionConfig,
                    colorFilter: colorFilter,
                    season: season,
                    calibrationCorrection: calibrationCorrection
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

}
