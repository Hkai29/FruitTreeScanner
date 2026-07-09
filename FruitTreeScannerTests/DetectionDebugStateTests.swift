import XCTest
import CoreML
import CoreVideo
import simd
@testable import FruitTreeScanner

final class DetectionDebugStateTests: XCTestCase {
    func testDebugThresholdKeepsConfiguredThreshold() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: 0.5, debugEnabled: true)

        XCTAssertEqual(threshold, 0.5, accuracy: 0.0001)
    }

    func testDebugThresholdKeepsLowerConfiguredThreshold() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: 0.1, debugEnabled: true)

        XCTAssertEqual(threshold, 0.1, accuracy: 0.0001)
    }

    func testReleaseThresholdKeepsConfiguredThreshold() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: 0.7, debugEnabled: false)

        XCTAssertEqual(threshold, 0.7, accuracy: 0.0001)
    }

    func testThresholdBelowZeroClampsToZero() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: -0.2, debugEnabled: true)

        XCTAssertEqual(threshold, 0, accuracy: 0.0001)
    }

    func testThresholdAboveOneClampsToOneInReleaseMode() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: 1.5, debugEnabled: false)

        XCTAssertEqual(threshold, 1, accuracy: 0.0001)
    }

    func testThresholdHintWhenRawDetectionsAreFilteredOut() {
        var state = DetectionDebugState(currentThreshold: 0.7)
        state.markInferenceCompleted(
            elapsedMs: 12,
            rawObservationCount: 2,
            filteredObservationCount: 0,
            rawPredictions: [
                DetectionPredictionDebug(
                    label: "apple",
                    confidence: 0.3,
                    boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
                )
            ],
            filteredPredictions: [],
            threshold: 0.7
        )

        XCTAssertEqual(
            state.diagnosticHint,
            "Raw detections exist but are filtered by confidence threshold. Try lowering threshold."
        )
    }

    func testModelLoadFailureRecordsErrorMessage() {
        var state = DetectionDebugState(currentThreshold: 0.5)
        state.markModelLoadFailure(
            modelName: "FruitsDetector",
            modelURLFound: false,
            errorMessage: "Model file not found"
        )

        XCTAssertFalse(state.modelLoaded)
        XCTAssertEqual(state.lastErrorMessage, "Model file not found")
    }

    func testModelLabelDiagnosticsReportCompatibleRuntimeLabels() {
        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(
            forRuntimeLabels: FruitCategory.customModelLabelOrder
        )

        XCTAssertTrue(diagnostics.runtimeModelLabelsAvailable)
        XCTAssertEqual(diagnostics.runtimeModelLabels, FruitCategory.customModelLabelOrder)
        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "compatible")
        XCTAssertTrue(diagnostics.modelLabelCompatibilityWarnings.isEmpty)
    }

    func testModelLabelDiagnosticsReportMismatchWithoutFailing() {
        var labels = FruitCategory.customModelLabelOrder
        labels.swapAt(0, 1)

        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)

        XCTAssertTrue(diagnostics.runtimeModelLabelsAvailable)
        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "mismatch")
        XCTAssertFalse(diagnostics.modelLabelCompatibilityWarnings.isEmpty)
    }

    func testModelLabelDiagnosticsParseUltralyticsNamesMetadata() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple', 1: 'orange', 2: 'mandarin'}"
        )

        XCTAssertEqual(labels, ["apple", "orange", "mandarin"])
    }

    func testDebugStateStoresModelLabelDiagnostics() {
        var state = DetectionDebugState(currentThreshold: 0.5)
        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(
            forRuntimeLabels: FruitCategory.customModelLabelOrder
        )

        state.markModelLoaded(
            modelName: "FruitsDetector",
            modelURLFound: true,
            supportedClasses: diagnostics.runtimeModelLabels,
            labelDiagnostics: diagnostics
        )

        XCTAssertTrue(state.runtimeModelLabelsAvailable)
        XCTAssertEqual(state.modelLabelCompatibilityStatus, "compatible")
        XCTAssertEqual(state.runtimeModelLabels, FruitCategory.customModelLabelOrder)
    }

    func testImageDetectionDiagnosticsRecordsLabelSummaries() {
        var recorder = ImageDetectorDiagnosticsRecorder()

        recorder.recordCoreMLDetection(
            observationCount: 3,
            confidenceFilteredCount: 1,
            unmappedObservationCount: 1,
            mappedFruitCount: 1,
            rawDetectedLabels: ["apple", "unknown fruit"],
            mappedCategories: ["apple"],
            unmappedLabels: ["unknown fruit"]
        )

        XCTAssertEqual(recorder.snapshot.rawDetectedLabels, ["apple", "unknown fruit"])
        XCTAssertEqual(recorder.snapshot.mappedCategories, ["apple"])
        XCTAssertEqual(recorder.snapshot.unmappedLabels, ["unknown fruit"])
        XCTAssertEqual(recorder.snapshot.unmappedObservationCount, 1)
    }

    func testProductionModelMetadataLabelsMatchCustomModelOrder() throws {
        let loadState = ImageDetectorModelLoader.loadModelState(named: "FruitsDetector")
        let diagnostics = try XCTUnwrap(loadState.loadedModel?.labelDiagnostics)

        XCTAssertTrue(diagnostics.runtimeModelLabelsAvailable)
        XCTAssertEqual(diagnostics.runtimeModelLabels, FruitCategory.customModelLabelOrder)
        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "compatible")
    }

    func testTopPredictionsSortByConfidence() {
        let predictions = [
            DetectionPredictionDebug(label: "pear", confidence: 0.4, boundingBox: .zero),
            DetectionPredictionDebug(label: "apple", confidence: 0.9, boundingBox: .zero),
            DetectionPredictionDebug(label: "orange", confidence: 0.7, boundingBox: .zero)
        ]

        let sorted = DetectionDebugState.sortedTopPredictions(predictions)

        XCTAssertEqual(sorted.map(\.label), ["apple", "orange", "pear"])
    }

    // MARK: - Codable round-trip

    func testDetectionPredictionDebugCodableRoundTrip() throws {
        let original = DetectionPredictionDebug(
            label: "apple",
            confidence: 0.85,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DetectionPredictionDebug.self, from: data)

        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.confidence, original.confidence, accuracy: 0.0001)
        XCTAssertEqual(decoded.boundingBox.origin.x, original.boundingBox.origin.x, accuracy: 0.0001)
        XCTAssertEqual(decoded.boundingBox.origin.y, original.boundingBox.origin.y, accuracy: 0.0001)
        XCTAssertEqual(decoded.boundingBox.size.width, original.boundingBox.size.width, accuracy: 0.0001)
        XCTAssertEqual(decoded.boundingBox.size.height, original.boundingBox.size.height, accuracy: 0.0001)
    }

    func testDetectionFailureSampleCodableRoundTrip() throws {
        let predictions = [
            DetectionPredictionDebug(label: "apple", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        ]
        let timestamp = Date(timeIntervalSince1970: 1718000000)
        let original = DetectionFailureSample(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            timestamp: timestamp,
            modelName: "FruitsDetector",
            threshold: 0.5,
            topPredictions: predictions,
            rawObservationCount: 5,
            filteredObservationCount: 0,
            note: "All below threshold",
            fruitCategoryExpected: "apple"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DetectionFailureSample.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.modelName, original.modelName)
        XCTAssertEqual(decoded.threshold, original.threshold, accuracy: 0.0001)
        XCTAssertEqual(decoded.rawObservationCount, original.rawObservationCount)
        XCTAssertEqual(decoded.filteredObservationCount, original.filteredObservationCount)
        XCTAssertEqual(decoded.note, original.note)
        XCTAssertEqual(decoded.fruitCategoryExpected, original.fruitCategoryExpected)
        XCTAssertEqual(decoded.topPredictions.count, original.topPredictions.count)
        XCTAssertEqual(decoded.topPredictions[0].label, original.topPredictions[0].label)
    }

    func testDetectionFailureSampleCodingPreservesNilOptionalFields() throws {
        let original = DetectionFailureSample(
            timestamp: Date(),
            modelName: "TestModel",
            threshold: 0.5,
            topPredictions: [],
            rawObservationCount: 0,
            filteredObservationCount: 0,
            note: nil,
            fruitCategoryExpected: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectionFailureSample.self, from: data)

        XCTAssertNil(decoded.note)
        XCTAssertNil(decoded.fruitCategoryExpected)
    }

    // MARK: - Failure sample collection

    func testDetectionFailureSamplesPreserveInsertionOrder() {
        let detector = ImageDetector(config: .default)
        let state = DetectionDebugState(currentThreshold: 0.5)
        detector.detectionDebugState = state

        let notes = ["first", "second", "third"]
        for note in notes {
            detector.captureDetectionFailureSample(note: note)
        }

        let samples = detector.detectionFailureSamplesSnapshot()
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.note), notes)
    }

    func testDetectionFailureSamplesEnforceMaxCount() {
        let detector = ImageDetector(config: .default)
        let state = DetectionDebugState(currentThreshold: 0.5)
        detector.detectionDebugState = state

        for i in 0..<25 {
            detector.captureDetectionFailureSample(note: "sample \(i)")
        }

        let samples = detector.detectionFailureSamplesSnapshot()
        XCTAssertEqual(samples.count, 20)
        XCTAssertEqual(samples.first?.note, "sample 5")
        XCTAssertEqual(samples.last?.note, "sample 24")
    }

    @MainActor
    func testResumePreservesPendingDetectionWork() {
        let coordinator = ScanCoordinator()
        let detector = coordinator.imageDetector
        let queueGeneration = detector.queueGeneration
        let pendingTask = Task<Void, Never> {}
        coordinator.detectionTask = pendingTask

        coordinator.resumeRecordingPreservingCapture()

        XCTAssertNotNil(coordinator.detectionTask)
        XCTAssertEqual(detector.queueGeneration, queueGeneration)
        pendingTask.cancel()
    }

    func testQueuedFramePreservesCopiedDepthContext() async throws {
        let detector = ImageDetector(
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
        )
        let imageBuffer = try makePixelBuffer(width: 4, height: 4, pixelFormat: kCVPixelFormatType_32BGRA)
        let depthMap = try makeDepthMap(width: 4, height: 4, fillValue: 2.0)
        let confidenceMap = try makeConfidenceMap(width: 4, height: 4, fillValue: 2)
        let transform = matrix_identity_float4x4
        var intrinsics = matrix_identity_float3x3
        intrinsics[0][0] = 500
        intrinsics[1][1] = 480

        detector.enqueueFrame(
            imageBuffer,
            timestamp: 12.5,
            cameraTransform: transform,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap,
            depthConfidenceMap: confidenceMap
        )
        fillDepth(depthMap, value: 9.0)
        fillConfidence(confidenceMap, value: 0)

        let frames = await detector.drainPendingFrames()
        let queuedFrame = try XCTUnwrap(frames.first)
        let copiedDepth = try XCTUnwrap(queuedFrame.depthMap)
        let copiedConfidence = try XCTUnwrap(queuedFrame.depthConfidenceMap)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(depthValue(depthMap), 9.0, accuracy: 0.001)
        XCTAssertEqual(depthValue(copiedDepth), 2.0, accuracy: 0.001)
        XCTAssertEqual(confidenceValue(confidenceMap), 0)
        XCTAssertEqual(confidenceValue(copiedConfidence), 2)
        XCTAssertEqual(queuedFrame.timestamp, 12.5, accuracy: 0.001)
        XCTAssertEqual(queuedFrame.imageSize.width, 1920)
        XCTAssertEqual(queuedFrame.cameraIntrinsics[0][0], 500, accuracy: 0.001)
        XCTAssertEqual(queuedFrame.cameraIntrinsics[1][1], 480, accuracy: 0.001)
    }

    func testClearQueueDropsFramePreparedForPreviousGeneration() throws {
        let detector = ImageDetector(
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
        )
        let generation = detector.queueGeneration
        let queuedFrame = ImageDetector.QueuedFrame(
            pixelBuffer: try makePixelBuffer(width: 4, height: 4, pixelFormat: kCVPixelFormatType_32BGRA),
            depthMap: nil,
            depthConfidenceMap: nil,
            timestamp: 1,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 4, height: 4)
        )

        detector.lock.lock()
        detector.preparingFrameGeneration = generation
        detector.lock.unlock()
        detector.clearQueue()
        detector.finishPreparingFrame(queuedFrame, generation: generation)

        let frames = detector.drainPendingFramesIfReady().frames

        XCTAssertTrue(frames.isEmpty)
    }

    @MainActor
    func testFusionEvidenceArchiveKeepsStableDetectionsAfterRuntimeRetentionTrimsWindow() async throws {
        let coordinator = ScanCoordinator()
        coordinator.imageDetector.updateConfig(
            FruitScanConfig(
                imageDetectionInterval: 1,
                minConfidence: 0.85,
                sizeTolerance: 0.2,
                sphericityThreshold: 0.5,
                minimumStableDetectionsForYield: 2,
                stableDetectionTimeWindow: 4.0
            )
        )
        let earlyStableDetections = [
            try makeAlignedAppleDetection(timestamp: 1.0),
            try makeAlignedAppleDetection(timestamp: 1.6)
        ]
        await coordinator.appendDetectedFruits(earlyStableDetections)

        let laterUnalignedDetections = (0..<(DetectionRetentionPolicy.defaultMaxFrameCount + 2)).map { index in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.08, height: 0.08),
                confidence: 0.95,
                timestamp: 10 + TimeInterval(index)
            )
        }
        await coordinator.appendDetectedFruits(laterUnalignedDetections)

        let earlyIDs = Set(earlyStableDetections.map(\.id))
        let runtimeIDs = Set(coordinator.detectedFruits.map(\.id))
        let estimateIDs = Set(coordinator.fusionEstimateDetectionsSnapshot().map(\.id))

        XCTAssertTrue(
            earlyIDs.isDisjoint(with: runtimeIDs),
            "运行时窗口可以裁掉早期帧以控制深度图内存"
        )
        XCTAssertTrue(
            earlyIDs.isSubset(of: estimateIDs),
            "已形成稳定轨迹的早期果实证据仍应进入最终融合估算"
        )
    }

    @MainActor
    func testFusionEvidenceArchiveCompactsLongStableTrack() async throws {
        let coordinator = ScanCoordinator()
        let config = FruitScanConfig(
            imageDetectionInterval: 1,
            minConfidence: 0.85,
            sizeTolerance: 0.2,
            sphericityThreshold: 0.5,
            minimumStableDetectionsForYield: 2,
            stableDetectionTimeWindow: 4.0
        )
        coordinator.imageDetector.updateConfig(config)

        let frameCount = DetectionRetentionPolicy.defaultMaxFrameCount + 40
        let batchSize = 20
        for batchStart in stride(from: 0, to: frameCount, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, frameCount)
            let detections = try (batchStart..<batchEnd).map { index in
                try makeAlignedAppleDetection(timestamp: TimeInterval(index) * 0.5)
            }
            await coordinator.appendDetectedFruits(detections)
        }

        XCTAssertLessThanOrEqual(
            coordinator.archivedFusionEvidenceDetections.count,
            max(config.minimumStableDetectionsForYield, 3),
            "同一稳定果实的归档证据应压缩为少量观测，避免长扫时长期保留大量深度图副本"
        )

        let stableEvidence = DetectionDeduplicator.stableEvidenceDetections(
            coordinator.archivedFusionEvidenceDetections.filter(\.hasAlignedDepthContext),
            minimumObservations: max(config.minimumStableDetectionsForYield, 2),
            minimumConfidence: max(config.minConfidence, 0.85),
            timeWindow: config.stableDetectionTimeWindow
        )
        XCTAssertFalse(stableEvidence.isEmpty, "压缩后的归档证据仍应能证明稳定轨迹")
    }

    private func makeDepthMap(width: Int, height: Int, fillValue: Float) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_DepthFloat32
        )
        fillDepth(buffer, value: fillValue)
        return buffer
    }

    private func makeConfidenceMap(width: Int, height: Int, fillValue: UInt8) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_OneComponent8
        )
        fillConfidence(buffer, value: fillValue)
        return buffer
    }

    private func makePixelBuffer(width: Int, height: Int, pixelFormat: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func fillDepth(_ depthMap: CVPixelBuffer, value: Float) {
        CVPixelBufferLockBaseAddress(depthMap, [])
        defer { CVPixelBufferUnlockBaseAddress(depthMap, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        for row in 0..<height {
            let rowPointer = baseAddress
                .advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for col in 0..<width {
                rowPointer[col] = value
            }
        }
    }

    private func depthValue(_ depthMap: CVPixelBuffer, x: Int = 0, y: Int = 0) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return .nan }
        let clampedX = min(max(x, 0), CVPixelBufferGetWidth(depthMap) - 1)
        let clampedY = min(max(y, 0), CVPixelBufferGetHeight(depthMap) - 1)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        return baseAddress
            .advanced(by: clampedY * bytesPerRow)
            .assumingMemoryBound(to: Float.self)[clampedX]
    }

    private func fillConfidence(_ confidenceMap: CVPixelBuffer, value: UInt8) {
        CVPixelBufferLockBaseAddress(confidenceMap, [])
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else { return }
        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)

        for row in 0..<height {
            let rowPointer = baseAddress
                .advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                rowPointer[col] = value
            }
        }
    }

    private func confidenceValue(_ confidenceMap: CVPixelBuffer, x: Int = 0, y: Int = 0) -> UInt8 {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else { return 0 }
        let clampedX = min(max(x, 0), CVPixelBufferGetWidth(confidenceMap) - 1)
        let clampedY = min(max(y, 0), CVPixelBufferGetHeight(confidenceMap) - 1)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        return baseAddress
            .advanced(by: clampedY * bytesPerRow)
            .assumingMemoryBound(to: UInt8.self)[clampedX]
    }

    private func makeAlignedAppleDetection(timestamp: TimeInterval) throws -> DetectedFruit {
        var intrinsics = matrix_identity_float3x3
        intrinsics[0][0] = 500
        intrinsics[1][1] = 500
        intrinsics[2][0] = 960
        intrinsics[2][1] = 540

        return DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.95,
            timestamp: timestamp,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: try makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        )
    }

#if DEBUG
    // MARK: - Export JSON

    func testExportJSONContainsExpectedMetadataFields() throws {
        let predictions = [
            DetectionPredictionDebug(label: "apple", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        ]
        let sample = DetectionFailureSample(
            timestamp: Date(timeIntervalSince1970: 1718000000),
            modelName: "FruitsDetector",
            threshold: 0.5,
            topPredictions: predictions,
            rawObservationCount: 5,
            filteredObservationCount: 2,
            note: "Test note",
            fruitCategoryExpected: "apple"
        )
        var debugState = DetectionDebugState(currentThreshold: 0.5)
        debugState.markModelLoaded(modelName: "FruitsDetector", modelURLFound: true, supportedClasses: ["apple", "pear"])
        debugState.markInferenceCompleted(
            elapsedMs: 42.0,
            rawObservationCount: 5,
            filteredObservationCount: 2,
            rawPredictions: predictions,
            filteredPredictions: predictions,
            threshold: 0.5
        )

        guard let json = DetectionFailureExportService.exportJSON(from: [sample], debugState: debugState) else {
            XCTFail("exportJSON returned nil")
            return
        }

        let data = try XCTUnwrap(json.data(using: .utf8))
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let unwrapped = try XCTUnwrap(dict)

        XCTAssertNotNil(unwrapped["exportTimestamp"])
        XCTAssertNotNil(unwrapped["appVersion"])
        XCTAssertEqual(unwrapped["sampleCount"] as? Int, 1)

        let samples = try XCTUnwrap(unwrapped["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 1)
        let s = samples[0]
        XCTAssertEqual(s["modelName"] as? String, "FruitsDetector")
        XCTAssertEqual(s["threshold"] as? Double, 0.5)
        XCTAssertEqual(s["rawObservationCount"] as? Int, 5)
        XCTAssertEqual(s["filteredObservationCount"] as? Int, 2)
        XCTAssertEqual(s["note"] as? String, "Test note")
        XCTAssertEqual(s["fruitCategoryExpected"] as? String, "apple")
        XCTAssertNotNil(s["timestamp"])
        XCTAssertNotNil(s["id"])

        let topPreds = try XCTUnwrap(s["topPredictions"] as? [[String: Any]])
        XCTAssertEqual(topPreds.count, 1)
        XCTAssertEqual(topPreds[0]["label"] as? String, "apple")
        let confidence = try XCTUnwrap(topPreds[0]["confidence"] as? Double)
        XCTAssertEqual(confidence, 0.9, accuracy: 0.001)
    }

    func testExportJSONWithEmptySamples() throws {
        var debugState = DetectionDebugState(currentThreshold: 0.25)
        debugState.markModelLoaded(modelName: "FruitsDetector", modelURLFound: true, supportedClasses: [])

        guard let json = DetectionFailureExportService.exportJSON(from: [], debugState: debugState) else {
            XCTFail("exportJSON returned nil")
            return
        }

        let data = try XCTUnwrap(json.data(using: .utf8))
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let unwrapped = try XCTUnwrap(dict)

        XCTAssertEqual(unwrapped["sampleCount"] as? Int, 0)
        let samples = try XCTUnwrap(unwrapped["samples"] as? [Any])
        XCTAssertTrue(samples.isEmpty)

        let debug = try XCTUnwrap(unwrapped["debugState"] as? [String: Any])
        XCTAssertEqual(debug["modelName"] as? String, "FruitsDetector")
        XCTAssertEqual(debug["currentThreshold"] as? Double, 0.25)
    }

    func testImageDetectorExportConvenienceMethod() {
        let detector = ImageDetector(config: .default)
        let state = DetectionDebugState(currentThreshold: 0.5)
        detector.detectionDebugState = state
        detector.captureDetectionFailureSample(note: "convenience test")

        let json = detector.exportFailureSamplesJSON()
        XCTAssertNotNil(json)

        let data = detector.exportFailureSamplesData()
        XCTAssertNotNil(data)
    }

    func testExportFileWritesShareableJSON() throws {
        let sample = DetectionFailureSample(
            timestamp: Date(timeIntervalSince1970: 1718000000),
            modelName: "FruitsDetector",
            threshold: 0.5,
            topPredictions: [],
            rawObservationCount: 1,
            filteredObservationCount: 0,
            note: "file export",
            fruitCategoryExpected: nil
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetectionDebugStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = try DetectionFailureExportService.exportFile(
            from: [sample],
            debugState: DetectionDebugState(currentThreshold: 0.5),
            directory: directory
        )

        XCTAssertEqual(fileURL.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["sampleCount"] as? Int, 1)
    }

    func testExportFileUsesUniqueFilenameForRapidConsecutiveExports() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetectionDebugStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let state = DetectionDebugState(currentThreshold: 0.5)
        let firstURL = try DetectionFailureExportService.exportFile(
            from: [],
            debugState: state,
            directory: directory
        )
        let secondURL = try DetectionFailureExportService.exportFile(
            from: [],
            debugState: state,
            directory: directory
        )

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testExportPayloadDebugStateSnapshotMirrorsSource() {
        var state = DetectionDebugState(currentThreshold: 0.42)
        state.markModelLoaded(modelName: "TestModel", modelURLFound: true, supportedClasses: ["a"])
        state.markModelLoadFailure(modelName: "TestModel", modelURLFound: false, errorMessage: "oops")

        let snapshot = DetectionDebugStateSnapshot(from: state)
        XCTAssertEqual(snapshot.modelName, state.modelName)
        XCTAssertEqual(snapshot.currentThreshold, state.currentThreshold)
        XCTAssertEqual(snapshot.lastErrorMessage, state.lastErrorMessage)
        XCTAssertTrue(snapshot.modelLoaded == state.modelLoaded)
    }
#endif

}
