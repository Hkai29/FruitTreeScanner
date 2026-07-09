// ImageDetectorModelLoading.swift
// CoreML model loading support for image detection.

import CoreML
import Foundation
import Vision

enum ImageDetectorModelStatus: Equatable {
    case coreML(resourceName: String, bundleExtension: String)
    case fallback(reason: String)

    var hudLabel: String {
        switch self {
        case .coreML:
            return "CoreML"
        case .fallback:
            return "Fallback"
        }
    }

    var hudDetail: String {
        switch self {
        case let .coreML(resourceName, bundleExtension):
            return "\(resourceName).\(bundleExtension)"
        case .fallback:
            return "No model"
        }
    }
}

struct ImageDetectorLoadedModel {
    let model: VNCoreMLModel
    let resourceName: String
    let bundleExtension: String
    let supportedClasses: [String]
    let labelDiagnostics: ModelLabelCompatibilityDiagnostics

    var displayName: String {
        "\(resourceName).\(bundleExtension)"
    }
}

struct ImageDetectorModelLoadState {
    let model: VNCoreMLModel?
    let status: ImageDetectorModelStatus
    let loadedModel: ImageDetectorLoadedModel?
    let failureModelName: String?
    let failureModelURLFound: Bool
    let failureMessage: String?
}

enum ImageDetectorModelLoader {
    static func loadModelState(named name: String) -> ImageDetectorModelLoadState {
        do {
            let loadedModel = try loadModel(named: name)
            return ImageDetectorModelLoadState(
                model: loadedModel.model,
                status: .coreML(
                    resourceName: loadedModel.resourceName,
                    bundleExtension: loadedModel.bundleExtension
                ),
                loadedModel: loadedModel,
                failureModelName: nil,
                failureModelURLFound: false,
                failureMessage: nil
            )
        } catch {
            let modelResource = modelURL(named: name)
            let modelName = modelResource.map { "\(name).\($0.bundleExtension)" } ?? name
            return ImageDetectorModelLoadState(
                model: nil,
                status: .fallback(reason: error.localizedDescription),
                loadedModel: nil,
                failureModelName: modelName,
                failureModelURLFound: modelResource != nil,
                failureMessage: error.localizedDescription
            )
        }
    }

    static func modelURL(named name: String) -> (url: URL, bundleExtension: String)? {
        for bundleExtension in ["mlmodelc", "mlmodel", "mlpackage"] {
            if let modelURL = Bundle.main.url(forResource: name, withExtension: bundleExtension) {
                return (modelURL, bundleExtension)
            }
        }

        return nil
    }

    static func loadModel(named name: String) throws -> ImageDetectorLoadedModel {
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            let mlModel = try MLModel(contentsOf: modelURL)
            let model = try VNCoreMLModel(for: mlModel)
            let labelDiagnostics = labelDiagnostics(from: mlModel)
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlmodelc",
                supportedClasses: labelDiagnostics.runtimeModelLabels,
                labelDiagnostics: labelDiagnostics
            )
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            let labelDiagnostics = labelDiagnostics(from: mlModel)
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlmodel",
                supportedClasses: labelDiagnostics.runtimeModelLabels,
                labelDiagnostics: labelDiagnostics
            )
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            let labelDiagnostics = labelDiagnostics(from: mlModel)
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlpackage",
                supportedClasses: labelDiagnostics.runtimeModelLabels,
                labelDiagnostics: labelDiagnostics
            )
        }

        throw NSError(
            domain: "ImageDetector",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(name)"]
        )
    }

    static func labelDiagnostics(from mlModel: MLModel) -> ModelLabelCompatibilityDiagnostics {
        let labels = supportedClasses(from: mlModel)
        return labelDiagnostics(forRuntimeLabels: labels)
    }

    static func labelDiagnostics(forRuntimeLabels labels: [String]) -> ModelLabelCompatibilityDiagnostics {
        guard !labels.isEmpty else {
            return .unavailable
        }

        let expectedLabels = FruitCategory.customModelLabelOrder
        guard labels == expectedLabels else {
            return ModelLabelCompatibilityDiagnostics(
                runtimeModelLabels: labels,
                runtimeModelLabelsAvailable: true,
                modelLabelCompatibilityStatus: "mismatch",
                modelLabelCompatibilityWarnings: compatibilityWarnings(
                    runtimeLabels: labels,
                    expectedLabels: expectedLabels
                )
            )
        }

        return ModelLabelCompatibilityDiagnostics(
            runtimeModelLabels: labels,
            runtimeModelLabelsAvailable: true,
            modelLabelCompatibilityStatus: "compatible",
            modelLabelCompatibilityWarnings: []
        )
    }

    static func labels(fromNamesMetadata names: String) -> [String] {
        let trimmed = names.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let pairs: [(index: Int, label: String)] = body
            .split(separator: ",")
            .compactMap { component in
                let pieces = component.split(separator: ":", maxSplits: 1)
                guard pieces.count == 2 else { return nil }
                let indexText = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let labelText = pieces[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                guard let index = Int(indexText), !labelText.isEmpty else { return nil }
                return (index, labelText)
            }
        return pairs.sorted { $0.index < $1.index }.map(\.label)
    }

    private static func supportedClasses(from mlModel: MLModel) -> [String] {
        if let labels = mlModel.modelDescription.classLabels, !labels.isEmpty {
            return labels.map { "\($0)" }
        }

        if let labels = labelsFromUserDefinedMetadata(mlModel), !labels.isEmpty {
            return labels
        }

        return []
    }

    private static func labelsFromUserDefinedMetadata(_ mlModel: MLModel) -> [String]? {
        guard let metadata = mlModel.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
              let names = metadata["names"] else {
            return nil
        }
        return labels(fromNamesMetadata: names)
    }

    private static func compatibilityWarnings(
        runtimeLabels: [String],
        expectedLabels: [String]
    ) -> [String] {
        var warnings: [String] = []
        if runtimeLabels.count != expectedLabels.count {
            warnings.append("Runtime model label count \(runtimeLabels.count) does not match expected count \(expectedLabels.count).")
        }

        for index in 0..<min(runtimeLabels.count, expectedLabels.count) {
            guard runtimeLabels[index] != expectedLabels[index] else { continue }
            warnings.append("Label \(index) runtime=\(runtimeLabels[index]) expected=\(expectedLabels[index]).")
            if warnings.count >= 5 { break }
        }

        if warnings.isEmpty {
            warnings.append("Runtime model labels are present but do not match the expected custom fruit label order.")
        }
        return warnings
    }
}
