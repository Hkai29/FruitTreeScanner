import QuartzCore

extension ScanCoordinator {
    @MainActor
    @objc func updatePointCount() {
        let now = CACurrentMediaTime()
        let hudInterval = renderer?.isRecording == true ? activeHUDUpdateInterval : idleHUDUpdateInterval
        guard now - lastHUDUpdateTime >= hudInterval else { return }
        lastHUDUpdateTime = now

        var hudPointCount: Int?
        var hudCoveragePercent: Int?

        if let renderer {
            let exportableCount = renderer.exportablePointCountPublic
            let nextPointCount = exportableCount > 0 ? exportableCount : renderer.currentPointCountPublic
            if pointCount != nextPointCount {
                pointCount = nextPointCount
                hudPointCount = nextPointCount
            }
        } else if pointCount != 0 {
            pointCount = 0
            hudPointCount = 0
        }

        let regionCount = renderer?.scannedRegionCountPublic ?? 0
        if scannedRegionCount != regionCount {
            scannedRegionCount = regionCount
        }

        let maxRegions = 600
        let nextCoveragePercent = min(Int(Double(regionCount) / Double(maxRegions) * 100), 100)
        if coveragePercent != nextCoveragePercent {
            coveragePercent = nextCoveragePercent
            hudCoveragePercent = nextCoveragePercent
            onCoveragePercentChange?(nextCoveragePercent)
        }

        let nextCoverageVoxelCount = renderer?.coverageVoxelCount ?? 0
        if coverageVoxelCount != nextCoverageVoxelCount {
            coverageVoxelCount = nextCoverageVoxelCount
        }

        let imageDiagnostics = imageDetector.diagnosticsSnapshot()
        #if DEBUG
        onDetectionDebugStateChange?(imageDetector.detectionDebugSnapshot())
        #endif
        hudState?.update(
            pointCount: hudPointCount,
            coveragePercent: hudCoveragePercent,
            exportablePointStatus: (renderer?.exportablePointCountPublic ?? 0) > 0 ? "Ready" : "NoCloud",
            processedImageFrames: imageDiagnostics.processedFrameCount,
            detectedFruitCount: max(detectedFruits.count, imageDiagnostics.mappedFruitCount)
        )

        updateScanCompletion()
    }

    @MainActor
    func updateScanCompletion() {
        guard let renderer = renderer else { return }
        let now = CACurrentMediaTime()
        let completionInterval = renderer.isRecording ? activeCompletionUpdateInterval : idleCompletionUpdateInterval
        guard now - lastCompletionUpdateTime >= completionInterval else { return }
        lastCompletionUpdateTime = now

        let completion = completionEvaluator.evaluate(
            .init(
                voxelCount: renderer.coverageVoxelCount,
                scanDuration: renderer.scanDuration,
                angleCoverage: renderer.coverageAngleRatioPublic,
                angleUniformity: renderer.coverageAngleUniformityPublic,
                oppositeSideCoverage: renderer.coverageOppositeSideRatioPublic,
                verticalCoverage: renderer.coverageVerticalRatioPublic,
                discoveryTrend: renderer.voxelDiscoveryTrendPublic,
                discoveryRate: renderer.voxelDiscoveryRatePublic
            )
        )

        scanCompletion = completion
        hudState?.update(scanCompletion: completion)
    }
}
