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
        guard renderer?.isRecording == true,
              let evidenceToken = capturedEvidenceToken() else { return }
        guard beginDetectionProcessing() else { return }

        // 推理可跨越多个 AR 帧；提交结果前必须再次验证扫描代次。
        detectionTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.finishDetectionProcessing() }
            let detected = await self.imageDetector.processQueue()
            guard !Task.isCancelled else { return }

            await self.appendDetectedFruits(detected, evidenceToken: evidenceToken)
        }
    }

    func flushPendingDetections() async {
        // 完成扫描前排空最后一帧，避免用户点击完成时丢失有效证据。
        if let detectionTask {
            await detectionTask.value
        }
        guard !Task.isCancelled, !isTornDown,
              lifecycleSnapshot().state == .finishing else { return }
        guard beginDetectionProcessing() else { return }
        defer { finishDetectionProcessing() }

        let detected = await imageDetector.processQueue()
        guard !Task.isCancelled,
              lifecycleSnapshot().state == .finishing else { return }
        await appendDetectedFruits(detected, evidenceToken: nil)
    }

    /// Compatibility entry point used by existing diagnostics tests. Production
    /// frame paths always pass a captured-evidence token below.
    func appendDetectedFruits(_ detected: [DetectedFruit]) async {
        await appendDetectedFruits(detected, evidenceToken: nil, enforceLifecycle: false)
    }

    func appendDetectedFruits(
        _ detected: [DetectedFruit],
        evidenceToken: ScanCapturedEvidenceToken?
    ) async {
        await appendDetectedFruits(
            detected,
            evidenceToken: evidenceToken,
            enforceLifecycle: true
        )
    }

    private func appendDetectedFruits(
        _ detected: [DetectedFruit],
        evidenceToken: ScanCapturedEvidenceToken?,
        enforceLifecycle: Bool
    ) async {
        guard !detected.isEmpty else { return }
        let detectorConfig = imageDetector.configSnapshot()

        await MainActor.run {
            guard !self.isTornDown else { return }
            guard enforceLifecycle else {
                self.detectedFruits.append(contentsOf: detected)
                self.publishFruitCategoryMismatchIfNeeded()
                self.archiveStableFusionEvidence(detectorConfig: detectorConfig)
                self.detectedFruits = DetectionRetentionPolicy.trimmedByFrameLimit(self.detectedFruits)
                return
            }
            if let evidenceToken {
                guard self.acceptsCapturedEvidence(evidenceToken) else { return }
            } else {
                guard self.lifecycleSnapshot().state == .finishing else { return }
            }
            self.detectedFruits.append(contentsOf: detected)
            self.publishFruitCategoryMismatchIfNeeded()
            self.archiveStableFusionEvidence(detectorConfig: detectorConfig)
            self.detectedFruits = DetectionRetentionPolicy.trimmedByFrameLimit(self.detectedFruits)
        }
    }

    func archiveStableFusionEvidence(detectorConfig: FruitScanConfig) {
        // 只归档具有对齐深度且跨帧稳定的检测，单帧命中不进入可靠产量。
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
    func startRecording(selectedCategory: FruitCategory = .apple) {
        // 新扫描必须清空上一任务的点云计数、检测证据和异步估算状态。
        detectionTask?.cancel()
        detectionTask = nil
        yieldEstimationController.cancel()
        imageDetector.clearQueue()
        createDirectory(folder: "scans")
        pointCount = 0
        scannedRegionCount = 0
        coveragePercent = 0
        coverageVoxelCount = 0
        scanCompletion = ScanCompletion()
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
        activeFruitConfiguration = ScanFruitConfiguration.capture(
            selectedCategory: selectedCategory,
            settings: settings
        )
        hasPublishedCategoryMismatch = false
        hudState?.resetForNewScan()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "扫描中")
        lastCameraPosition = nil
        lastCameraSpeedTime = 0
        smoothedCameraSpeed = 0
        renderer?.currentFolder = "scans"
        let lifecycle = scanLifecycle.startNewScan()
        _ = setReliableEvidenceAcceptance(true)
        renderer?.isRecording = true
        publishLifecycleSnapshot(lifecycle)
    }

    @MainActor
    func resumeRecordingPreservingCapture() {
        // This is the same logical scan. Keep the in-flight detection task and
        // queued frames so stopping briefly does not discard image evidence
        // that still needs to be fused with the preserved point cloud.
        let lifecycle = scanLifecycle.resumeUserPaused()
        guard lifecycle.state == .recording else { return }
        yieldEstimationController.cancel()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "补扫中")
        renderer?.currentFolder = "scans"
        _ = setReliableEvidenceAcceptance(true)
        renderer?.resumeRecordingPreservingPointCloud()
        publishLifecycleSnapshot(lifecycle)
    }

    func stopRecording() {
        Log.scan.info("Stopping recording, flushing detection queue")
        let lifecycle = scanLifecycle.userPaused()
        _ = setReliableEvidenceAcceptance(false)
        renderer?.isRecording = false
        publishLifecycleSnapshot(lifecycle)
    }

    @discardableResult
    func beginFinishingScan() -> Bool {
        let lifecycle = scanLifecycle.beginFinishing()
        guard lifecycle.state == .finishing else { return false }
        // 先关闭证据门，再冻结采集；之后仅允许显式 flush 的结果进入快照。
        _ = setReliableEvidenceAcceptance(false)
        renderer?.isRecording = false
        publishLifecycleSnapshot(lifecycle)
        return true
    }

    func markScanCompleted() {
        publishLifecycleSnapshot(scanLifecycle.complete())
    }

    @MainActor
    func handleSystemInterruption(_ reason: ScanInterruptionReason) {
        guard !isTornDown else { return }
        invalidateReliableEvidenceImmediately()
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        hudState?.update(fusionStatus: "Interrupted")
        publishLifecycleSnapshot(scanLifecycle.interrupt(reason))
    }

    @MainActor
    func handleSessionInterruptionEnded() {
        guard !isTornDown else { return }
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        publishLifecycleSnapshot(scanLifecycle.interruptionEnded())
    }

    @MainActor
    func handleSessionFailure(_ error: Error) {
        guard !isTornDown else { return }
        invalidateReliableEvidenceImmediately()
        session?.pause()
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        hudState?.update(fusionStatus: "Failed")
        publishLifecycleSnapshot(scanLifecycle.fail(.sessionFailed(error.localizedDescription)))
    }

    @MainActor
    @discardableResult
    func restartInterruptedScan(selectedCategory: FruitCategory) -> Bool {
        guard !isTornDown else { return false }
        switch lifecycleSnapshot().state {
        case .systemInterrupted, .recovering, .failed:
            break
        default:
            return false
        }

        invalidateReliableEvidenceImmediately()
        guard restartBoundSessionWithResetTracking() else {
            let failed = scanLifecycle.fail(
                .sessionFailed("AR session unavailable during restart")
            )
            publishLifecycleSnapshot(failed)
            return false
        }

        startRecording(selectedCategory: selectedCategory)
        let restarted = lifecycleSnapshot()
        return restarted.state == .recording && acceptsReliableEvidence()
    }

    @MainActor
    func discardInterruptedScan() {
        invalidateReliableEvidenceImmediately()
        publishLifecycleSnapshot(scanLifecycle.cancel())
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

    @MainActor
    private func makeYieldEstimationSnapshot(season: Season) -> ScanYieldEstimationController.Snapshot? {
        guard !isTornDown, let scanConfiguration = activeFruitConfiguration else { return nil }

        // 快照建立后清空活动缓存，确保一次扫描只消费一次证据集合。
        archiveStableFusionEvidence(detectorConfig: scanConfiguration.fusionConfig)
        let savedDetections = fusionEstimateDetectionsSnapshot()
        let categoryVerification = FruitCategoryVerificationSummary.make(
            selectedCategory: scanConfiguration.selectedCategory,
            detections: savedDetections
        )
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()

        return ScanYieldEstimationController.Snapshot(
            input: .init(
                points: extractColoredPoints(),
                savedDetections: savedDetections,
                imageDiagnostics: imageDetector.diagnosticsSnapshot(),
                fruitType: scanConfiguration.selectedCategory.rawValue,
                fruitCategory: scanConfiguration.selectedCategory,
                paramsSnapshot: scanConfiguration.parametersSnapshot,
                defaultParams: scanConfiguration.defaultParams,
                clusterConfig: scanConfiguration.clusterConfig,
                fusionConfig: scanConfiguration.fusionConfig,
                colorFilter: scanConfiguration.colorFilter,
                season: season,
                calibrationCorrection: scanConfiguration.calibrationCorrection,
                categoryVerification: categoryVerification
            )
        )
    }

    @MainActor
    private func publishFruitCategoryMismatchIfNeeded() {
        guard !hasPublishedCategoryMismatch,
              let selectedCategory = activeFruitConfiguration?.selectedCategory,
              let mismatch = FruitCategoryVerification.mismatch(
                selectedCategory: selectedCategory,
                detections: detectedFruits
              ) else {
            return
        }
        hasPublishedCategoryMismatch = true
        onFruitCategoryMismatch?(mismatch)
    }

    /// 多模态融合产量估算（新 pipeline）
    @MainActor
    func runMultiModalYieldEstimate(
        season: Season = .mature,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
        let lifecycle = lifecycleSnapshot()
        guard lifecycle.state == .finishing else { return }
        yieldEstimationController.start(
            season: season,
            flushPendingDetections: { [weak self] in
                await self?.flushPendingDetections()
            },
            makeSnapshot: { [weak self] season in
                self?.makeYieldEstimationSnapshot(season: season)
            },
            completion: { [weak self] result, countResult in
                guard let self, !self.isTornDown,
                      self.lifecycleSnapshot().generation == lifecycle.generation,
                      self.lifecycleSnapshot().state == .finishing else { return }
                self.hudState?.update(
                    detectedFruitCount: result.diagnostics.fusedFruitCount,
                    fusionStatus: result.diagnostics.fusedFruitCount > 0 ? "OK" : "0kg"
                )
                completion(result, countResult)
            }
        )
    }

}
