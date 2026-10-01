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
        var detectorConfig = activeScanPlan?.fruitConfiguration.fusionConfig ?? settings.fruitScanConfig
        detectorConfig.minConfidence = DetectionDebugConfiguration.effectiveThreshold(for: detectorConfig.minConfidence)
        imageDetector.updateConfig(detectorConfig, depthConfiguration: activeScanPlan?.experimentConfiguration.depth ?? .default)
        publishImageDetectorStatus()
        if let plan = activeScanPlan {
            renderer?.applyScanQualitySettings(plan.rendererSettings, resourceBudget: plan.resourceBudget)
        } else {
            renderer?.applyScanQualitySettings()
        }
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
            let detected = await self.imageDetector.processObservations()
            guard !Task.isCancelled else { return }

            await self.appendObservations(detected, evidenceToken: evidenceToken)
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

        let detected = await imageDetector.processObservations()
        guard !Task.isCancelled,
              lifecycleSnapshot().state == .finishing else { return }
        await appendObservations(detected, evidenceToken: nil)
    }

    /// Compatibility entry point used by existing diagnostics tests. Production
    /// frame paths always pass a captured-evidence token below.
    func appendDetectedFruits(_ detected: [DetectedFruit]) async {
        let observations = await resolveLegacyObservations(detected)
        await appendObservations(observations, evidenceToken: nil, enforceLifecycle: false)
    }

    func appendDetectedFruits(
        _ detected: [DetectedFruit],
        evidenceToken: ScanCapturedEvidenceToken?
    ) async {
        let observations = await resolveLegacyObservations(detected)
        await appendObservations(
            observations,
            evidenceToken: evidenceToken
        )
    }

    /// This nonisolated async boundary samples legacy buffers off the main
    /// actor using the scan's depth configuration. Captured observations pass
    /// through unchanged, including their original frame configuration.
    private func resolveLegacyObservations(_ detected: [DetectedFruit]) async -> [Observation] {
        let depthConfiguration = await MainActor.run {
            activeScanPlan?.experimentConfiguration.depth ?? .default
        }
        return detected.map { $0.resolvedObservation(depthConfiguration: depthConfiguration) }
    }

    func appendObservations(
        _ observations: [Observation],
        evidenceToken: ScanCapturedEvidenceToken?
    ) async {
        await appendObservations(
            observations,
            evidenceToken: evidenceToken,
            enforceLifecycle: true
        )
    }

    @MainActor
    private func appendObservations(
        _ detected: [Observation],
        evidenceToken: ScanCapturedEvidenceToken?,
        enforceLifecycle: Bool
    ) async {
        guard !detected.isEmpty else { return }
        let detectorConfig = imageDetector.configSnapshot()

        guard !isTornDown, !Task.isCancelled else { return }
        if enforceLifecycle {
            if let evidenceToken {
                guard acceptsCapturedEvidence(evidenceToken) else { return }
            } else {
                guard lifecycleSnapshot().state == .finishing else { return }
            }
        }
        detectedFruits.append(contentsOf: detected)
        publishFruitCategoryMismatchIfNeeded()
        evidenceArchiveRevision &+= 1
        let revision = evidenceArchiveRevision
        let scanIdentity = lifecycleSnapshot().scanIdentity
        let activeDetections = detectedFruits
        let previousArchive = archivedFusionEvidenceDetections
        let worker = Task.detached(priority: .utility) {
            Self.makeArchivedEvidence(
                observations: activeDetections,
                archive: previousArchive,
                detectorConfig: detectorConfig
            )
        }
        let archived = await withTaskCancellationHandler(
            operation: { await worker.value },
            onCancel: { worker.cancel() }
        )
        guard !isTornDown, !Task.isCancelled,
              scanIdentity == lifecycleSnapshot().scanIdentity,
              revision == evidenceArchiveRevision else { return }
        if enforceLifecycle {
            if let evidenceToken {
                guard acceptsCapturedEvidence(evidenceToken) else { return }
            } else {
                guard lifecycleSnapshot().state == .finishing else { return }
            }
        }
        archivedFusionEvidenceDetections = archived
        detectedFruits = DetectionRetentionPolicy.trimmedByFrameLimit(
            observations: detectedFruits,
            maxFrameCount: activeScanPlan?.resourceBudget.retainedDetectionFrameLimit ?? DetectionRetentionPolicy.defaultMaxFrameCount
        )
    }

    static func makeArchivedEvidence(
        observations: [Observation],
        archive: [Observation],
        detectorConfig: FruitScanConfig
    ) -> [Observation] {
        // 只归档具有对齐深度且跨帧稳定的检测，单帧命中不进入可靠产量。
        let minimumObservations = max(detectorConfig.minimumStableDetectionsForYield, 2)
        let minimumConfidence = max(detectorConfig.minConfidence, 0.85)
        let stableEvidence = DetectionDeduplicator.stableEvidenceDetections(
            observations: observations.filter(\.hasAlignedDepthContext),
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: detectorConfig.stableDetectionTimeWindow
        )
        guard !stableEvidence.isEmpty, !Task.isCancelled else { return archive }

        var archivedFusionEvidenceDetections = archive
        var archivedIDs = Set(archivedFusionEvidenceDetections.map(\.id))
        for detection in stableEvidence where archivedIDs.insert(detection.id).inserted {
            archivedFusionEvidenceDetections.append(detection)
        }
        return DetectionDeduplicator.compactStableEvidenceDetections(
            observations: archivedFusionEvidenceDetections,
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: detectorConfig.stableDetectionTimeWindow,
            maxObservationsPerTrack: max(minimumObservations, 3)
        )
    }

    func fusionEstimateDetectionsSnapshot() -> [DetectedFruit] {
        fusionEstimateObservationsSnapshot().map(DetectedFruit.init(observation:))
    }

    func fusionEstimateObservationsSnapshot() -> [Observation] {
        var seenIDs = Set<UUID>()
        var snapshot: [Observation] = []
        snapshot.reserveCapacity(archivedFusionEvidenceDetections.count + detectedFruits.count)

        for evidence in [archivedFusionEvidenceDetections, detectedFruits] {
            for observation in evidence where seenIDs.insert(observation.id).inserted {
                snapshot.append(observation)
            }
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
        let snapshot = ScanFruitConfigurationSnapshot.capture(
            selectedCategory: selectedCategory,
            settings: settings,
            calibrationRecordsLoader: calibrationRecordsLoader
        )
        beginRecording(
            configuration: snapshot.makeConfiguration(modelIdentity: YieldCalibrationContext.bundledModelIdentity),
            plan: nil
        )
    }

    @MainActor
    func startRecording(plan: ScanPlan) {
        beginRecording(configuration: plan.fruitConfiguration, plan: plan)
    }

    @MainActor
    private func beginRecording(configuration: ScanFruitConfiguration, plan: ScanPlan?) {
        // 新扫描必须清空上一任务的点云计数、检测证据和异步估算状态。
        invalidateReliableEvidenceGate()
        renderer?.isRecording = false
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
        let lifecycle = scanSession.startNewScan(
            plan: plan,
            compatibilityConfiguration: plan == nil ? configuration : nil
        )
        if let plan {
            loadSettings()
            guard applyCameraRequestForNewScan(plan.cameraRequest) else {
                publishLifecycleSnapshot(scanSession.fail(.sessionFailed("AR session unavailable at scan start")))
                return
            }
        }
        if let warning = configuration.calibrationWarning {
            onCalibrationWarning?(warning)
        }
        hasPublishedCategoryMismatch = false
        hudState?.resetForNewScan()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "扫描中")
        lastCameraPosition = nil
        lastCameraSpeedTime = 0
        smoothedCameraSpeed = 0
        renderer?.currentFolder = "scans"
        _ = activateCaptureWhenCameraTrackingAllows(
            lifecycle: lifecycle,
            resetPointCloud: true
        )
        publishLifecycleSnapshot(lifecycle)
    }

    @MainActor
    func resumeRecordingPreservingCapture() {
        // This is the same logical scan. Keep the in-flight detection task and
        // queued frames so stopping briefly does not discard image evidence
        // that still needs to be fused with the preserved point cloud.
        let lifecycle = scanSession.resumeUserPaused()
        guard lifecycle.state == .recording else { return }
        yieldEstimationController.cancel()
        publishImageDetectorStatus()
        hudState?.update(fusionStatus: "补扫中")
        renderer?.currentFolder = "scans"
        _ = activateCaptureWhenCameraTrackingAllows(
            lifecycle: lifecycle,
            resetPointCloud: false
        )
        publishLifecycleSnapshot(lifecycle)
    }

    func stopRecording() {
        Log.scan.info("Stopping recording, flushing detection queue")
        let lifecycle = scanSession.userPaused()
        _ = setReliableEvidenceAcceptance(false)
        renderer?.isRecording = false
        clearCameraTrackingSuspension()
        publishLifecycleSnapshot(lifecycle)
    }

    @discardableResult
    func beginFinishingScan() -> Bool {
        let lifecycle = scanSession.beginFinishing()
        guard lifecycle.state == .finishing else { return false }
        // 先关闭证据门，再冻结采集；之后仅允许显式 flush 的结果进入快照。
        _ = setReliableEvidenceAcceptance(false)
        renderer?.isRecording = false
        clearCameraTrackingSuspension()
        publishLifecycleSnapshot(lifecycle)
        return true
    }

    func markScanCompleted() {
        publishLifecycleSnapshot(scanSession.complete())
    }

    @MainActor
    func handleSystemInterruption(_ reason: ScanInterruptionReason) {
        guard !isTornDown else { return }
        invalidateReliableEvidenceImmediately()
        clearCameraTrackingSuspension()
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        hudState?.update(fusionStatus: "Interrupted")
        publishLifecycleSnapshot(scanSession.interrupt(reason))
    }

    @MainActor
    func handleSessionInterruptionEnded() {
        guard !isTornDown else { return }
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        publishLifecycleSnapshot(scanSession.interruptionEnded())
    }

    @MainActor
    func handleSessionFailure(_ error: Error) {
        guard !isTornDown else { return }
        invalidateReliableEvidenceImmediately()
        clearCameraTrackingSuspension()
        session?.pause()
        publishDepthRuntimeStatus(requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth)
        hudState?.update(fusionStatus: "Failed")
        publishLifecycleSnapshot(
            scanSession.fail(ScanSessionFailureClassifier.reason(for: error))
        )
    }

    @MainActor
    @discardableResult
    func restartInterruptedScan(selectedCategory: FruitCategory) -> Bool {
        restartInterruptedScan(cameraRequest: currentCameraRequest()) {
            startRecording(selectedCategory: selectedCategory)
        }
    }

    @MainActor
    @discardableResult
    func restartInterruptedScan(plan: ScanPlan) -> Bool {
        restartInterruptedScan(cameraRequest: plan.cameraRequest) {
            startRecording(plan: plan)
        }
    }

    @MainActor
    @discardableResult
    private func restartInterruptedScan(cameraRequest: ScanCameraRequest, startNewScan: () -> Void) -> Bool {
        guard !isTornDown else { return false }
        switch lifecycleSnapshot().state {
        case .systemInterrupted, .recovering, .failed:
            break
        default:
            return false
        }

        invalidateReliableEvidenceImmediately()
        guard restartBoundSessionWithResetTracking(cameraRequest: cameraRequest) else {
            let failed = scanSession.fail(
                .sessionFailed("AR session unavailable during restart")
            )
            publishLifecycleSnapshot(failed)
            return false
        }

        startNewScan()
        let restarted = lifecycleSnapshot()
        return restarted.state == .recording
            && (acceptsReliableEvidence()
                || isCaptureSuspendedForCameraTracking(
                    scanIdentity: restarted.scanIdentity
                ))
    }

    @MainActor
    func discardInterruptedScan() {
        invalidateReliableEvidenceImmediately()
        clearCameraTrackingSuspension()
        publishLifecycleSnapshot(scanSession.cancel())
    }

    func exportPLY(treeID: String, lat: Double, lon: Double,
                   completion: @escaping (String?) -> Void) {
        stagePointCloud(treeID: treeID, lat: lat, lon: lon) {
            completion($0?.draft.sourceFilename)
        }
    }

    func stagePointCloud(treeID: String, lat: Double, lon: Double,
                         completion: @escaping (StagedPointCloud?) -> Void) {
        guard let renderer else {
            Log.export.error("Export failed: renderer is nil")
            completion(nil)
            return
        }

        Log.export.info("Exporting PLY for tree \(treeID)")
        renderer.stagePointCloud(treeID: treeID, gpsLat: lat, gpsLon: lon) { staged in
            if let staged {
                Log.export.info("PLY exported: \(staged.draft.sourceFilename)")
            } else {
                Log.export.error("PLY export failed: file write error")
            }
            completion(staged)
        }
    }

    @MainActor
    func stagePointCloud(plan: ScanPlan, lat: Double, lon: Double,
                         repository: ScanRepository = .shared) async throws -> StagedPointCloud {
        guard activeScanPlan?.id == plan.id, lifecycleSnapshot().state == .finishing else {
            throw ScanEvidenceError.mismatchedInput
        }
        guard let renderer else { throw PointCloudExportError.rendererUnavailable }
        let context = ScanContext(scanID: lifecycleSnapshot().scanIdentity, planID: plan.id)
        return try await renderer.stagePointCloud(treeID: plan.treeID, gpsLat: lat, gpsLon: lon,
                                                 context: context, repository: repository)
    }

    func extractFinalPointCloud() -> FinalPointCloud? {
        renderer?.makeFinalPointCloudSnapshot()
    }

    @MainActor
    func prepareYieldEstimationSnapshot(
        season: Season,
        finalPointCloud: FinalPointCloud
    ) async throws -> ScanYieldEstimationController.Snapshot {
        let lifecycle = lifecycleSnapshot()
        guard lifecycle.state == .finishing else { throw CancellationError() }
        await flushPendingDetections()
        try Task.checkCancellation()
        guard lifecycleSnapshot().scanIdentity == lifecycle.scanIdentity,
              lifecycleSnapshot().generation == lifecycle.generation,
              lifecycleSnapshot().state == .finishing else { throw CancellationError() }
        guard let snapshot = makeYieldEstimationSnapshot(season: season, finalPointCloud: finalPointCloud) else {
            throw ScanYieldEstimationController.PreparationError.snapshotUnavailable
        }
        return snapshot
    }

    @MainActor
    private func makeYieldEstimationSnapshot(
        season: Season,
        finalPointCloud: FinalPointCloud? = nil
    ) -> ScanYieldEstimationController.Snapshot? {
        guard !isTornDown, let scanConfiguration = activeFruitConfiguration else { return nil }

        // 检测追加任务已等待后台归档完成；快照保留活动窗口作为最终证据。
        let observations = fusionEstimateObservationsSnapshot()
        let categoryVerification = FruitCategoryVerificationSummary.make(
            selectedCategory: scanConfiguration.selectedCategory,
            observations: observations
        )
        let finalPointCloud = finalPointCloud ?? extractFinalPointCloud()
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()

        return ScanYieldEstimationController.Snapshot(
            context: activeScanPlan.map { ScanContext(scanID: lifecycleSnapshot().scanIdentity, planID: $0.id) },
            input: .init(
                points: finalPointCloud?.points ?? [],
                observations: observations,
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
                categoryVerification: categoryVerification,
                finalPointCloudIdentity: finalPointCloud?.identity,
                experimentConfiguration: activeScanPlan?.experimentConfiguration ?? .default,
                calibrationIdentity: ScanCalibrationIdentity(
                    algorithmRevision: activeScanPlan?.algorithmRevision ?? YieldAlgorithmRevision.current,
                    context: scanConfiguration.calibrationContext
                )
            )
        )
    }

    @MainActor
    private func publishFruitCategoryMismatchIfNeeded() {
        guard !hasPublishedCategoryMismatch,
              let selectedCategory = activeFruitConfiguration?.selectedCategory,
              let mismatch = FruitCategoryVerification.mismatch(
                selectedCategory: selectedCategory,
                observations: detectedFruits
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
        finalPointCloud: FinalPointCloud? = nil,
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
                self?.makeYieldEstimationSnapshot(season: season, finalPointCloud: finalPointCloud)
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
