import XCTest
@testable import FruitTreeScanner

final class DetectionDebugStateTests: XCTestCase {
    func testDebugThresholdUsesDefaultWhenConfiguredThresholdIsHigher() {
        let threshold = DetectionDebugConfiguration.effectiveThreshold(for: 0.5, debugEnabled: true)

        XCTAssertEqual(threshold, 0.25, accuracy: 0.0001)
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
