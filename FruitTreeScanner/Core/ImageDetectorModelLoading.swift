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
    let diagnostics: ModelResourceDiagnostics

    var displayName: String {
        "\(resourceName).\(bundleExtension)"
    }
}

struct ImageDetectorModelLoadFailure: LocalizedError {
    let diagnostics: ModelResourceDiagnostics

    var errorDescription: String? {
        diagnostics.loadErrorMessage
    }
}

enum ImageDetectorModelLoader {
    static func modelURL(named name: String) -> (url: URL, bundleExtension: String)? {
        for bundleExtension in ["mlmodelc", "mlmodel", "mlpackage"] {
            if let modelURL = Bundle.main.url(forResource: name, withExtension: bundleExtension) {
                return (modelURL, bundleExtension)
            }
        }

        return nil
    }

    static func loadModel(named name: String) throws -> ImageDetectorLoadedModel {
        guard let modelResource = modelURL(named: name) else {
            throw ImageDetectorModelLoadFailure(
                diagnostics: ModelResourceDiagnostics(
                    expectedModelName: name,
                    foundModelURL: false,
                    foundExtension: nil,
                    bundlePath: nil,
                    loadedSuccessfully: false,
                    loadErrorMessage: "No \(name) model found. Add \(name).mlmodel, .mlmodelc, or .mlpackage to the app target.",
                    supportedClasses: [],
                    labelsSource: "none"
                )
            )
        }

        do {
            let mlModel: MLModel
            if modelResource.bundleExtension == "mlmodelc" {
                mlModel = try MLModel(contentsOf: modelResource.url)
            } else {
                let compiledURL = try MLModel.compileModel(at: modelResource.url)
                mlModel = try MLModel(contentsOf: compiledURL)
            }

            let classLabels = supportedClasses(from: mlModel, modelName: name)
            let model = try VNCoreMLModel(for: mlModel)
            let diagnostics = ModelResourceDiagnostics(
                expectedModelName: name,
                foundModelURL: true,
                foundExtension: modelResource.bundleExtension,
                bundlePath: modelResource.url.path,
                loadedSuccessfully: true,
                loadErrorMessage: nil,
                supportedClasses: classLabels.labels,
                labelsSource: classLabels.source
            )
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: modelResource.bundleExtension,
                supportedClasses: classLabels.labels,
                diagnostics: diagnostics
            )
        } catch {
            let labels = bundledLabels(named: name)
            throw ImageDetectorModelLoadFailure(
                diagnostics: ModelResourceDiagnostics(
                    expectedModelName: name,
                    foundModelURL: true,
                    foundExtension: modelResource.bundleExtension,
                    bundlePath: modelResource.url.path,
                    loadedSuccessfully: false,
                    loadErrorMessage: error.localizedDescription,
                    supportedClasses: labels.labels,
                    labelsSource: labels.source
                )
            )
        }
    }

    static func failureDiagnostics(named name: String, error: Error) -> ModelResourceDiagnostics {
        if let failure = error as? ImageDetectorModelLoadFailure {
            return failure.diagnostics
        }

        let modelResource = modelURL(named: name)
        let labels = bundledLabels(named: name)
        return ModelResourceDiagnostics(
            expectedModelName: name,
            foundModelURL: modelResource != nil,
            foundExtension: modelResource?.bundleExtension,
            bundlePath: modelResource?.url.path,
            loadedSuccessfully: false,
            loadErrorMessage: error.localizedDescription,
            supportedClasses: labels.labels,
            labelsSource: labels.source
        )
    }

    static func parseLabelsText(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseLabelsJSON(_ data: Data) throws -> [String] {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let labels = decoded as? [String] else { return [] }
        return labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func supportedClasses(from mlModel: MLModel, modelName: String) -> (labels: [String], source: String) {
        if let labels = mlModel.modelDescription.classLabels, !labels.isEmpty {
            return (labels.map { "\($0)" }, "coremlMetadata")
        }

        return bundledLabels(named: modelName)
    }

    private static func bundledLabels(named modelName: String) -> (labels: [String], source: String) {
        let candidates: [(resource: String, fileExtension: String, source: String, isJSON: Bool)] = [
            ("\(modelName).labels", "txt", "\(modelName).labels.txt", false),
            ("\(modelName).classes", "txt", "\(modelName).classes.txt", false),
            ("\(modelName).classes", "json", "\(modelName).classes.json", true),
            ("labels", "txt", "labels.txt", false),
        ]

        for candidate in candidates {
            guard let url = Bundle.main.url(
                forResource: candidate.resource,
                withExtension: candidate.fileExtension
            ) else { continue }

            do {
                let labels: [String]
                if candidate.isJSON {
                    labels = try parseLabelsJSON(Data(contentsOf: url))
                } else {
                    labels = parseLabelsText(try String(contentsOf: url, encoding: .utf8))
                }
                if !labels.isEmpty {
                    return (labels, candidate.source)
                }
            } catch {
                continue
            }
        }

        return ([], "none")
    }
}
