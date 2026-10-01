import XCTest
import CoreML
import CoreVideo
import simd
@testable import FruitTreeScanner

final class DetectionDebugStateTests: XCTestCase {

    @MainActor
    func testScanFruitConfigurationReportsCalibrationReadFailureAndUsesNeutralCorrection() {
        let configuration = ScanFruitConfiguration.capture(
            selectedCategory: .apple,
            settings: SettingsStore.shared,
            calibrationRecordsLoader: {
                throw CocoaError(.fileReadCorruptFile)
            }
        )

        XCTAssertEqual(configuration.calibrationWarning, .recordsUnavailable)
        XCTAssertEqual(configuration.calibrationCorrection, .neutral)
    }

    @MainActor
    func testScanFruitConfigurationAppliesVerifiedCalibrationWithoutWarning() throws {
        let settings = SettingsStore.shared
        let baseline = ScanFruitConfiguration.capture(
            selectedCategory: .apple,
            settings: settings,
            calibrationRecordsLoader: { [] }
        )
        let context = try XCTUnwrap(baseline.calibrationContext)
        var record = CalibrationRecord(
            id: UUID(),
            treeID: "T-verified",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: 10,
            manualFruitCount: 8,
            estimatedYieldKg: 5,
            actualYieldKg: 4,
            fruitType: FruitCategory.apple.rawValue
        )
        record.algorithmRevision = YieldAlgorithmRevision.current
        record.calibrationContext = context

        let configuration = ScanFruitConfiguration.capture(
            selectedCategory: .apple,
            settings: settings,
            calibrationRecordsLoader: { [record] }
        )

        XCTAssertNil(configuration.calibrationWarning)
        XCTAssertEqual(configuration.calibrationCorrection.countFactor, 0.8, accuracy: 0.001)
        XCTAssertEqual(configuration.calibrationCorrection.yieldFactor, 0.8, accuracy: 0.001)
    }

    @MainActor
    func testEmptyCalibrationSnapshotIsValidAndDoesNotWarn() {
        let configuration = ScanFruitConfiguration.capture(
            selectedCategory: .apple,
            settings: SettingsStore.shared,
            calibrationRecordsLoader: { [] }
        )

        XCTAssertNil(configuration.calibrationWarning)
        XCTAssertEqual(configuration.calibrationCorrection, .neutral)
    }

    @MainActor
    func testScanStartPublishesCalibrationWarningButContinuesWithNeutralCorrection() {
        var warnings: [ScanCalibrationWarning] = []
        let coordinator = ScanCoordinator(
            settings: SettingsStore.shared,
            calibrationRecordsLoader: {
                throw CocoaError(.fileReadCorruptFile)
            }
        )
        coordinator.onCalibrationWarning = { warnings.append($0) }

        coordinator.startRecording(selectedCategory: .apple)

        XCTAssertEqual(warnings, [.recordsUnavailable])
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        XCTAssertEqual(coordinator.activeFruitConfiguration?.calibrationCorrection, .neutral)
        XCTAssertEqual(coordinator.activeFruitConfiguration?.calibrationWarning, .recordsUnavailable)

        coordinator.teardown()
        XCTAssertNil(coordinator.onCalibrationWarning)
    }

    @MainActor
    func testScanFruitConfigurationRemainsStableWhenGlobalSettingChanges() {
        let settings = SettingsStore.shared
        let originalFruitType = settings.fruitType
        defer { settings.fruitType = originalFruitType }

        settings.fruitType = FruitCategory.apple.rawValue
        let coordinator = ScanCoordinator(settings: settings)
        coordinator.startRecording(selectedCategory: .apple)

        settings.fruitType = FruitCategory.pear.rawValue
        XCTAssertEqual(coordinator.activeFruitConfiguration?.selectedCategory, .apple)

        coordinator.resumeRecordingPreservingCapture()
        XCTAssertEqual(coordinator.activeFruitConfiguration?.selectedCategory, .apple)

        coordinator.startRecording(selectedCategory: .pear)
        XCTAssertEqual(coordinator.activeFruitConfiguration?.selectedCategory, .pear)
    }
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

    func testModelLabelDiagnosticsReportRuntimeMappingForWrongOrderLabels() {
        var labels = FruitCategory.customModelLabelOrder
        labels.swapAt(0, 1)

        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)

        XCTAssertTrue(diagnostics.runtimeModelLabelsAvailable)
        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "runtimeMapped")
        XCTAssertFalse(diagnostics.modelLabelCompatibilityWarnings.isEmpty)
        XCTAssertTrue(diagnostics.usesRuntimeLabelMapping)
        XCTAssertEqual(diagnostics.runtimeLabel(forClassIndex: 0), "orange")
    }

    func testModelLabelRuntimeMappingDoesNotRecordDebugFailureReason() {
        var labels = FruitCategory.customModelLabelOrder
        labels.swapAt(0, 1)
        let labelDiagnostics = ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)

        var recorder = ImageDetectorDiagnosticsRecorder()
        recorder.apply(modelStatus: .coreML(resourceName: "FruitsDetector", bundleExtension: "mlmodelc"))
        recorder.apply(labelDiagnostics: labelDiagnostics)
        XCTAssertEqual(recorder.snapshot.modelLabelCompatibilityStatus, "runtimeMapped")
        XCTAssertTrue(recorder.snapshot.modelFailureReason.isEmpty)

        var state = DetectionDebugState(currentThreshold: 0.5)
        state.markModelLoaded(
            modelName: "FruitsDetector",
            modelURLFound: true,
            supportedClasses: labelDiagnostics.runtimeModelLabels,
            labelDiagnostics: labelDiagnostics
        )
        XCTAssertEqual(state.modelLabelCompatibilityStatus, "runtimeMapped")
        XCTAssertNil(state.lastErrorMessage)
    }

    func testModelLabelDiagnosticsReportSubsetForSixSupportedFruitLabels() {
        let labels = ["apple", "orange", "pear", "persimmon", "grape", "strawberry"]

        let diagnostics = ImageDetectorModelLoader.labelDiagnostics(forRuntimeLabels: labels)

        XCTAssertTrue(diagnostics.runtimeModelLabelsAvailable)
        XCTAssertEqual(diagnostics.modelLabelCompatibilityStatus, "subset")
        XCTAssertTrue(diagnostics.usesRuntimeLabelMapping)
        XCTAssertTrue(diagnostics.modelLabelCompatibilityWarnings.contains {
            $0.contains("mapped by label string")
        })
    }

    func testModelLabelDiagnosticsParseUltralyticsNamesMetadata() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple', 1: 'orange', 2: 'mandarin'}"
        )

        XCTAssertEqual(labels, ["apple", "orange", "mandarin"])
    }

    func testModelLabelDiagnosticsSortCompleteUltralyticsNamesMetadata() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{2: 'mandarin', 0: 'apple', 1: 'orange'}"
        )

        XCTAssertEqual(labels, ["apple", "orange", "mandarin"])
    }

    func testModelLabelDiagnosticsRejectGappedUltralyticsNamesMetadata() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple', 2: 'orange'}"
        )

        XCTAssertTrue(labels.isEmpty)
    }

    func testModelLabelDiagnosticsRejectDuplicateUltralyticsNamesIndex() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple', 0: 'orange'}"
        )

        XCTAssertTrue(labels.isEmpty)
    }

    func testModelLabelDiagnosticsRejectMalformedUltralyticsNamesEntry() {
        let labels = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple', invalid, 1: 'orange'}"
        )
        let labelsWithEmptyEntry = ImageDetectorModelLoader.labels(
            fromNamesMetadata: "{0: 'apple',, 1: 'orange'}"
        )

        XCTAssertTrue(labels.isEmpty)
        XCTAssertTrue(labelsWithEmptyEntry.isEmpty)
    }

    func testRecognizedObjectLabelMappingRejectsUnconfirmedNumericIdentifiers() {
        let mapper = FruitCategoryMapper.standard

        XCTAssertNil(ImageDetectorInference.categoryForRecognizedObjectLabel(
            "0",
            categoryMapper: mapper
        ))
        XCTAssertNil(ImageDetectorInference.categoryForRecognizedObjectLabel(
            "77",
            categoryMapper: mapper
        ))
        XCTAssertEqual(
            ImageDetectorInference.categoryForRecognizedObjectLabel(
                " APPLE ",
                categoryMapper: mapper
            ),
            .apple
        )
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
        XCTAssertEqual(queuedFrame.depthConfidenceProvenance, .available)
        XCTAssertEqual(queuedFrame.timestamp, 12.5, accuracy: 0.001)
        XCTAssertEqual(queuedFrame.imageSize.width, 1920)
        XCTAssertEqual(queuedFrame.cameraIntrinsics[0][0], 500, accuracy: 0.001)
        XCTAssertEqual(queuedFrame.cameraIntrinsics[1][1], 480, accuracy: 0.001)
    }

    func testQueuedFrameDistinguishesUnavailableConfidenceFromCopyFailure() throws {
        let imageBuffer = try makePixelBuffer(width: 4, height: 4, pixelFormat: kCVPixelFormatType_32BGRA)
        let depthMap = try makeDepthMap(width: 4, height: 4, fillValue: 2.0)

        let result = ImageDetectorQueue.makeQueuedFrame(
            pixelBuffer: imageBuffer,
            timestamp: 1,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 4, height: 4),
            depthMap: depthMap,
            depthConfidenceMap: nil
        )

        XCTAssertEqual(result.queuedFrame?.depthConfidenceProvenance, .unavailable)
        XCTAssertFalse(result.droppedDepthConfidenceMap)
    }

    func testConfidenceCopyFailurePreservesDetectionButRejectsAlignedDepthContext() throws {
        let imageBuffer = try makePixelBuffer(width: 4, height: 4, pixelFormat: kCVPixelFormatType_32BGRA)
        let depthMap = try makeDepthMap(width: 4, height: 4, fillValue: 2.0)
        let confidenceMap = try makeConfidenceMap(width: 4, height: 4, fillValue: 2)
        let result = ImageDetectorQueue.makeQueuedFrame(
            pixelBuffer: imageBuffer,
            timestamp: 1,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 4, height: 4),
            depthMap: depthMap,
            depthConfidenceMap: confidenceMap,
            pixelBufferCopier: { buffer in
                buffer === confidenceMap ? nil : duplicatePixelBuffer(input: buffer)
            }
        )
        let frame = try XCTUnwrap(result.queuedFrame)
        let detections = ImageDetectorQueue.enrich(
            [DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.9)],
            with: frame
        )
        let detection = try XCTUnwrap(detections.first)

        XCTAssertTrue(result.droppedDepthConfidenceMap)
        XCTAssertEqual(frame.depthConfidenceProvenance, .copyFailed)
        XCTAssertNil(frame.depthConfidenceMap)
        XCTAssertEqual(detection.depthConfidenceProvenance, .copyFailed)
        XCTAssertFalse(detection.hasAlignedDepthContext)
    }

    func testEnrichedDetectionStoresBoundedFrameObservationInsteadOfPixelBuffers() throws {
        let imageBuffer = try makePixelBuffer(width: 8, height: 8, pixelFormat: kCVPixelFormatType_32BGRA)
        let depthMap = try makeDepthMap(width: 90, height: 90, fillValue: 2.25)
        let confidenceMap = try makeConfidenceMap(width: 90, height: 90, fillValue: 2)
        let packet = ImageDetectorQueue.makeQueuedFrame(
            pixelBuffer: imageBuffer,
            timestamp: 4.5,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 900, height: 900),
            depthMap: depthMap,
            depthConfidenceMap: confidenceMap
        )
        let frame = try XCTUnwrap(packet.queuedFrame)
        let detection = try XCTUnwrap(ImageDetectorQueue.enrich(
            [DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                confidence: 0.92,
                timestamp: 4.5
            )],
            with: frame
        ).first)
        let observation = try XCTUnwrap(detection.observation)

        XCTAssertEqual(observation.frameID, frame.frameID)
        XCTAssertEqual(observation.id, detection.id)
        XCTAssertEqual(observation.coordinateConvention, .visionNormalizedLowerLeft)
        XCTAssertTrue(observation.hasAlignedDepthContext)
        XCTAssertEqual(observation.roiDepthSamples.count, 81)
        XCTAssertEqual(
            observation.projectionDepthSamples.count,
            FruitScanExperimentConfig.default.depth.projectionSampleGrid * FruitScanExperimentConfig.default.depth.projectionSampleGrid
        )
        XCTAssertTrue(observation.roiDepthSamples.allSatisfy { abs($0.depthMeters - 2.25) < 0.001 })
        XCTAssertTrue(detection.hasAlignedDepthContext)
    }

    func testQueuedFrameKeepsDepthConfigurationAcrossDetectorUpdates() async throws {
        let image = try makePixelBuffer(width: 8, height: 8, pixelFormat: kCVPixelFormatType_32BGRA)
        let depth = try makeDepthMap(width: 90, height: 90, fillValue: 2)
        let confidence = try makeConfidenceMap(width: 90, height: 90, fillValue: 1)
        var config = FruitScanConfig.default
        config.imageDetectionInterval = 1
        let detector = ImageDetector(config: config)
        var depthConfig = DepthExperimentConfig.default
        depthConfig.minimumReliableConfidence = 2
        depthConfig.projectionSampleGrid = 3
        detector.updateConfig(config, depthConfiguration: depthConfig)
        detector.enqueueFrame(image, timestamp: 10, cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3, imageSize: CGSize(width: 900, height: 900),
            depthMap: depth, depthConfidenceMap: confidence)
        detector.updateConfig(config)
        let frames = await detector.drainPendingFrames()
        let frame = try XCTUnwrap(frames.first)
        XCTAssertEqual(frame.depthConfiguration, depthConfig)
        let fruit = DetectedFruit(category: .apple, boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), confidence: 0.9)
        let observation = try XCTUnwrap(ImageDetectorQueue.observations(from: [fruit], with: frame).first)
        XCTAssertEqual(observation.frameID, frame.frameID)
        XCTAssertTrue(observation.roiDepthSamples.isEmpty)
        XCTAssertTrue(observation.projectionDepthSamples.isEmpty)
        XCTAssertTrue(observation.rejectionReasons.contains(.noReliableDepthSamples))
    }

    func testCustomDepthSamplingGridIsBoundedAndCannotAdmitLowConfidence() throws {
        let depth = try makeDepthMap(width: 90, height: 90, fillValue: 2)
        let low = try makeConfidenceMap(width: 90, height: 90, fillValue: 0)
        let medium = try makeConfidenceMap(width: 90, height: 90, fillValue: 1)
        var config = DepthExperimentConfig.default
        config.minimumReliableConfidence = 0
        config.projectionSampleGrid = 3
        func capture(_ confidence: CVPixelBuffer) -> Observation {
            Observation.capture(id: UUID(), frameID: FrameID(), category: .apple,
                boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), confidence: 0.9, timestamp: 1,
                cameraTransform: matrix_identity_float4x4, cameraIntrinsics: matrix_identity_float3x3,
                imageSize: CGSize(width: 900, height: 900), depthMap: depth, depthConfidenceMap: confidence,
                depthConfidenceProvenance: .available, depthConfiguration: config)
        }
        XCTAssertTrue(capture(low).projectionDepthSamples.isEmpty)
        XCTAssertTrue(capture(low).roiDepthSamples.isEmpty)
        XCTAssertEqual(capture(medium).projectionDepthSamples.count, 9)
        XCTAssertEqual(capture(medium).roiDepthSamples.count, 81)
        config.projectionSampleGrid = Int.max
        XCTAssertEqual(capture(medium).projectionDepthSamples.count, 81)
        XCTAssertEqual(RendererScanSettings.reliableConfidenceThreshold(storedThreshold: 0, minimumReliableConfidence: 0), 1)
    }

    func testEnrichedObservationRecordsWhenConfidenceGateRejectsAllDepthSamples() throws {
        let imageBuffer = try makePixelBuffer(width: 8, height: 8, pixelFormat: kCVPixelFormatType_32BGRA)
        let depthMap = try makeDepthMap(width: 90, height: 90, fillValue: 2.0)
        let confidenceMap = try makeConfidenceMap(width: 90, height: 90, fillValue: 0)
        let packet = ImageDetectorQueue.makeQueuedFrame(
            pixelBuffer: imageBuffer,
            timestamp: 7,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 900, height: 900),
            depthMap: depthMap,
            depthConfidenceMap: confidenceMap
        )
        let frame = try XCTUnwrap(packet.queuedFrame)
        let detection = try XCTUnwrap(ImageDetectorQueue.enrich(
            [DetectedFruit(category: .apple, boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), confidence: 0.92)],
            with: frame
        ).first)
        let observation = try XCTUnwrap(detection.observation)

        XCTAssertTrue(observation.hasAlignedDepthContext)
        XCTAssertTrue(observation.roiDepthSamples.isEmpty)
        XCTAssertTrue(observation.projectionDepthSamples.isEmpty)
        XCTAssertTrue(observation.rejectionReasons.contains(.noReliableDepthSamples))
        XCTAssertTrue(DetectionDepthCandidateBuilder.makeCandidates(
            from: [detection],
            clusterConfig: .default
        ).isEmpty)
    }

    func testDrainReturnsImmediatelyWhenNoFrameIsBeingPrepared() async {
        let detector = ImageDetector()
        let frames = await detector.drainPendingFrames()
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(drainWaiterCount(detector), 0)
    }

    func testDrainWakesWhenPreparedFrameArrives() async throws {
        let detector = ImageDetector()
        let generation = beginPreparingFrame(detector)
        let frame = try makeDrainTestFrame(timestamp: 1)
        let task = Task { await detector.drainPendingFrames() }
        await waitForDrainRegistration(detector)
        detector.finishPreparingFrame(frame, generation: generation)
        let frames = await task.value
        XCTAssertEqual(frames.map(\.frameID), [frame.frameID])
        XCTAssertEqual(ImageDetectorQueue.attachedQueueGeneration(to: frames[0].pixelBuffer), generation)
        XCTAssertEqual(drainWaiterCount(detector), 0)
    }

    func testFailedFramePreparationWakesDrainWithoutEvidence() async {
        let detector = ImageDetector()
        let generation = beginPreparingFrame(detector)
        let task = Task { await detector.drainPendingFrames() }
        await waitForDrainRegistration(detector)
        detector.cancelPreparingFrame(generation: generation)
        let frames = await task.value
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(drainWaiterCount(detector), 0)
    }

    func testCancelledDrainLeavesLateFrameForAnotherConsumer() async throws {
        let detector = ImageDetector()
        let generation = beginPreparingFrame(detector)
        let frame = try makeDrainTestFrame(timestamp: 1)
        let task = Task { await detector.drainPendingFrames() }
        await waitForDrainRegistration(detector)
        task.cancel()
        let cancelledFrames = await task.value
        XCTAssertTrue(cancelledFrames.isEmpty)
        XCTAssertEqual(drainWaiterCount(detector), 0)
        detector.finishPreparingFrame(frame, generation: generation)
        let frames = await detector.drainPendingFrames()
        XCTAssertEqual(frames.map(\.frameID), [frame.frameID])
    }

    func testCancellationBeforeDrainRegistrationDoesNotWaitOrConsume() async throws {
        let detector = ImageDetector()
        let generation = beginPreparingFrame(detector)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await detector.drainPendingFrames()
        }
        let frames = await task.value
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(drainWaiterCount(detector), 0)
        let frame = try makeDrainTestFrame(timestamp: 1)
        detector.finishPreparingFrame(frame, generation: generation)
        let next = await detector.drainPendingFrames()
        XCTAssertEqual(next.map(\.frameID), [frame.frameID])
    }

    func testResetWakesOldDrainWithoutConsumingNewGeneration() async throws {
        let detector = ImageDetector()
        let originalGeneration = beginPreparingFrame(detector)
        let task = Task { await detector.drainPendingFrames() }
        await waitForDrainRegistration(detector)
        detector.clearQueue()
        let generation = beginPreparingFrame(detector)
        detector.finishPreparingFrame(try makeDrainTestFrame(timestamp: 1), generation: originalGeneration)
        let frame = try makeDrainTestFrame(timestamp: 2)
        detector.finishPreparingFrame(frame, generation: generation)
        let oldFrames = await task.value
        XCTAssertTrue(oldFrames.isEmpty)
        let newFrames = await detector.drainPendingFrames()
        XCTAssertEqual(newFrames.map(\.frameID), [frame.frameID])
        XCTAssertEqual(drainWaiterCount(detector), 0)
    }

    func testCancellingOneDrainDoesNotCancelAnotherWaitingConsumer() async throws {
        let detector = ImageDetector()
        let generation = beginPreparingFrame(detector)
        let first = Task { await detector.drainPendingFrames() }
        let second = Task { await detector.drainPendingFrames() }
        await waitForDrainRegistration(detector, count: 2)
        first.cancel()
        let cancelled = await first.value
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(drainWaiterCount(detector), 1)
        let frame = try makeDrainTestFrame(timestamp: 1)
        detector.finishPreparingFrame(frame, generation: generation)
        let frames = await second.value
        XCTAssertEqual(frames.map(\.frameID), [frame.frameID])
        XCTAssertEqual(drainWaiterCount(detector), 0)
    }

    private func beginPreparingFrame(_ detector: ImageDetector) -> Int {
        detector.lock.lock()
        defer { detector.lock.unlock() }
        detector.preparingFrameGeneration = detector.queueGeneration
        return detector.queueGeneration
    }

    private func drainWaiterCount(_ detector: ImageDetector) -> Int {
        detector.lock.lock()
        defer { detector.lock.unlock() }
        return detector.drainWaiters.count
    }

    private func waitForDrainRegistration(_ detector: ImageDetector, count: Int = 1) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if drainWaiterCount(detector) == count { return }
            await Task.yield()
        }
        XCTFail("Frame drain did not register before the deadline")
    }

    private func makeDrainTestFrame(timestamp: TimeInterval) throws -> ImageDetector.QueuedFrame {
        ImageDetector.QueuedFrame(
            pixelBuffer: try makePixelBuffer(width: 4, height: 4, pixelFormat: kCVPixelFormatType_32BGRA),
            depthMap: nil, depthConfidenceMap: nil, depthConfidenceProvenance: .unavailable,
            timestamp: timestamp, cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3, imageSize: CGSize(width: 4, height: 4)
        )
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
            depthConfidenceProvenance: .unavailable,
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

    func testStaleInferenceGenerationCannotMutateResetDiagnostics() async throws {
        let detector = ImageDetector(
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
        )
        let pixelBuffer = try makePixelBuffer(
            width: 4,
            height: 4,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        let staleGeneration = detector.queueGenerationSnapshot()
        ImageDetectorQueue.attachQueueGeneration(
            staleGeneration,
            to: pixelBuffer
        )
        detector.clearQueue()

        let fruits = await ImageDetectorInference().performDetection(
            detector: detector,
            pixelBuffer: pixelBuffer,
            timestamp: 1,
            imageSize: CGSize(width: 4, height: 4),
            queue: DispatchQueue(label: "test.stale-inference")
        )
        let diagnostics = detector.diagnosticsSnapshot()

        XCTAssertTrue(fruits.isEmpty)
        XCTAssertEqual(diagnostics.processedFrameCount, 0)
        XCTAssertEqual(diagnostics.observationCount, 0)
        XCTAssertEqual(diagnostics.mappedFruitCount, 0)
        XCTAssertTrue(diagnostics.lastDetectionError.isEmpty)
    }

    func testCurrentInferenceGenerationCanCommitDiagnostics() {
        let detector = ImageDetector(
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
        )
        let generation = detector.queueGenerationSnapshot()

        XCTAssertTrue(detector.recordCoreMLDetection(
            observationCount: 2,
            confidenceFilteredCount: 1,
            unmappedObservationCount: 0,
            mappedFruitCount: 1,
            rawDetectedLabels: ["apple"],
            mappedCategories: [FruitCategory.apple.rawValue],
            unmappedLabels: [],
            expectedQueueGeneration: generation
        ))

        let diagnostics = detector.diagnosticsSnapshot()
        XCTAssertEqual(diagnostics.processedFrameCount, 1)
        XCTAssertEqual(diagnostics.observationCount, 2)
        XCTAssertEqual(diagnostics.mappedFruitCount, 1)
    }

    func testDrainedFrameKeepsOriginalGenerationAcrossQueueReset() async throws {
        let detector = ImageDetector(
            config: FruitScanConfig(imageDetectionInterval: 1, minConfidence: 0.5)
        )
        let pixelBuffer = try makePixelBuffer(
            width: 4,
            height: 4,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        let queuedFrame = ImageDetector.QueuedFrame(
            pixelBuffer: pixelBuffer,
            depthMap: nil,
            depthConfidenceMap: nil,
            depthConfidenceProvenance: .unavailable,
            timestamp: 1,
            cameraTransform: matrix_identity_float4x4,
            cameraIntrinsics: matrix_identity_float3x3,
            imageSize: CGSize(width: 4, height: 4)
        )
        let originalGeneration = detector.queueGenerationSnapshot()
        detector.finishPreparingFrame(queuedFrame, generation: originalGeneration)
        let drainedFrame = try XCTUnwrap(
            detector.drainPendingFramesIfReady().frames.first
        )
        detector.clearQueue()

        let fruits = await ImageDetectorInference().performDetection(
            detector: detector,
            pixelBuffer: drainedFrame.pixelBuffer,
            timestamp: drainedFrame.timestamp,
            imageSize: drainedFrame.imageSize,
            queue: DispatchQueue(label: "test.drained-stale-inference")
        )
        let diagnostics = detector.diagnosticsSnapshot()

        XCTAssertTrue(fruits.isEmpty)
        XCTAssertEqual(diagnostics.processedFrameCount, 0)
        XCTAssertEqual(diagnostics.observationCount, 0)
        XCTAssertEqual(diagnostics.mappedFruitCount, 0)
        XCTAssertTrue(diagnostics.lastDetectionError.isEmpty)
    }

    @MainActor
    func testNativeObservationsKeepFrameEvidenceThroughArchiveTrimAndFreeze() async throws {
        let suite = "NativeObservationFreeze-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] },
            resourceBudget: ScanResourceBudget(retainedDetectionFrameLimit: 2))
        let plan = factory.makePlan(treeID: "native-freeze", season: .mature, selectedCategory: .apple, renderer: nil)
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.startRecording(plan: plan)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())
        let early = try [1.0, 1.6].map {
            try makeAlignedAppleDetection(timestamp: $0).resolvedObservation(frameID: FrameID())
        }
        await coordinator.appendObservations(early, evidenceToken: token)
        let late = [3.0, 4.0, 5.0].map {
            DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.95, timestamp: $0)
                .resolvedObservation(frameID: FrameID())
        }
        await coordinator.appendObservations(late, evidenceToken: token)
        XCTAssertEqual(coordinator.detectedFruits.map(\.id), Array(late.suffix(2)).map(\.id))
        XCTAssertEqual(coordinator.archivedFusionEvidenceDetections.map(\.id), early.map(\.id))

        XCTAssertTrue(coordinator.beginFinishingScan())
        let cloud = FinalPointCloud(identity: RendererSnapshotSignature(pointCount: 0, pointIndex: 0,
            voxelSize: 0.005, confidenceThreshold: 2), points: [], inputSampleCount: 0, retainedSampleCount: 0,
            buildDuration: 0, estimatedPeakPayloadBytes: 0)
        let snapshot = try await coordinator.prepareYieldEstimationSnapshot(season: .mature, finalPointCloud: cloud)
        let expected = early + Array(late.suffix(2))
        XCTAssertEqual(snapshot.input.observations.map(\.id), expected.map(\.id))
        XCTAssertEqual(snapshot.input.observations.map(\.frameID), expected.map(\.frameID))
        XCTAssertEqual(snapshot.input.observations.map(\.roiDepthSamples), expected.map(\.roiDepthSamples))
        XCTAssertEqual(snapshot.input.observations.map(\.projectionDepthSamples), expected.map(\.projectionDepthSamples))
        XCTAssertEqual(snapshot.input.observations.map(\.rejectionReasons), expected.map(\.rejectionReasons))
        XCTAssertEqual(snapshot.input.categoryVerification?.detectedCategoryCounts, ["apple": 4])
        XCTAssertTrue(coordinator.detectedFruits.isEmpty)
        XCTAssertTrue(coordinator.archivedFusionEvidenceDetections.isEmpty)
    }

    @MainActor
    func testLegacyCoordinatorSamplingUsesPlanWhileCapturedObservationStaysUnchanged() async throws {
        let suite = "LegacyObservationPlan-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var experiment = FruitScanExperimentConfig.default
        experiment.depth.minimumReliableConfidence = 2
        experiment.depth.projectionSampleGrid = 3
        let factory = ScanPlanFactory(settings: settings, calibrationRecordsLoader: { [] }, experimentConfiguration: experiment)
        let plan = factory.makePlan(treeID: "legacy-plan", season: .mature, selectedCategory: .apple, renderer: nil)
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        coordinator.startRecording(plan: plan)
        let token = try XCTUnwrap(coordinator.capturedEvidenceToken())
        let depth = try makeDepthMap(width: 16, height: 16, fillValue: 2)
        let confidence = try makeConfidenceMap(width: 16, height: 16, fillValue: 1)
        func detection(at time: TimeInterval) -> DetectedFruit {
            DetectedFruit(category: .apple, boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
                confidence: 0.95, timestamp: time, cameraTransform: matrix_identity_float4x4,
                cameraIntrinsics: matrix_identity_float3x3, imageSize: CGSize(width: 16, height: 16),
                depthMap: depth, depthConfidenceMap: confidence)
        }
        await coordinator.appendDetectedFruits([detection(at: 1)], evidenceToken: token)
        let sampled = try XCTUnwrap(coordinator.detectedFruits.first)
        XCTAssertTrue(sampled.projectionDepthSamples.isEmpty)
        XCTAssertTrue(sampled.rejectionReasons.contains(.noReliableDepthSamples))

        let captured = detection(at: 2).resolvedObservation(frameID: FrameID())
        XCTAssertFalse(captured.projectionDepthSamples.isEmpty)
        await coordinator.appendDetectedFruits([DetectedFruit(observation: captured)], evidenceToken: token)
        let retained = try XCTUnwrap(coordinator.detectedFruits.last)
        XCTAssertEqual(retained.id, captured.id)
        XCTAssertEqual(retained.frameID, captured.frameID)
        XCTAssertEqual(retained.projectionDepthSamples, captured.projectionDepthSamples)
        XCTAssertEqual(retained.rejectionReasons, captured.rejectionReasons)
    }

    @MainActor
    func testFusionEvidenceArchiveKeepsStableDetectionsAfterRuntimeRetentionTrimsWindow() async throws {
        let coordinator = ScanCoordinator()
        coordinator.imageDetector.updateConfig(
            FruitScanConfig(
                imageDetectionInterval: 1,
                minConfidence: 0.85,
                sizeTolerance: 0.2,
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
            observations: coordinator.archivedFusionEvidenceDetections.filter(\.hasAlignedDepthContext),
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
