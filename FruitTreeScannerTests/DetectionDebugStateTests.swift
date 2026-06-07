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

    func testLabelsTextParserIgnoresTrailingNewline() {
        let labels = ImageDetectorModelLoader.parseLabelsText("apple\norange\nfruit\n")

        XCTAssertEqual(labels, ["apple", "orange", "fruit"])
    }

    func testClassesJSONParserReadsSimpleArray() throws {
        let data = Data(#"["apple","orange","fruit"]"#.utf8)

        let labels = try ImageDetectorModelLoader.parseLabelsJSON(data)

        XCTAssertEqual(labels, ["apple", "orange", "fruit"])
    }

    func testGenericFruitLabelMapsToSelectedFruitType() {
        let mapping = FruitCategoryMapper.standard.categoryMapping(
            for: "fruit",
            selectedFruitType: "persimmon"
        )

        XCTAssertEqual(mapping?.category, .persimmon)
        XCTAssertTrue(mapping?.usedGenericFallback == true)
        XCTAssertEqual(mapping?.debugWarning, FruitCategoryMapper.genericFruitMappingWarning)
    }

    func testPreviewDetectionAllowedInDebugWhenNotRecording() {
        XCTAssertTrue(ScanCoordinator.allowsDetectionProcessing(
            isRecording: false,
            debugRunDetectionWhilePreviewing: true,
            debugBuild: true
        ))
    }

    func testPreviewDetectionDisabledPreservesRecordingGate() {
        XCTAssertFalse(ScanCoordinator.allowsDetectionProcessing(
            isRecording: false,
            debugRunDetectionWhilePreviewing: false,
            debugBuild: true
        ))
    }

    func testReleaseDetectionPreservesRecordingGate() {
        XCTAssertFalse(ScanCoordinator.allowsDetectionProcessing(
            isRecording: false,
            debugRunDetectionWhilePreviewing: true,
            debugBuild: false
        ))
        XCTAssertTrue(ScanCoordinator.allowsDetectionProcessing(
            isRecording: true,
            debugRunDetectionWhilePreviewing: false,
            debugBuild: false
        ))
    }

}
