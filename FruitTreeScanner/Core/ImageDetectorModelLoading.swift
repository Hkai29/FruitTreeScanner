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
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlmodelc",
                supportedClasses: supportedClasses(from: mlModel)
            )
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlmodel",
                supportedClasses: supportedClasses(from: mlModel)
            )
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            return ImageDetectorLoadedModel(
                model: model,
                resourceName: name,
                bundleExtension: "mlpackage",
                supportedClasses: supportedClasses(from: mlModel)
            )
        }

        throw NSError(
            domain: "ImageDetector",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(name)"]
        )
    }

    private static func supportedClasses(from mlModel: MLModel) -> [String] {
        if let labels = mlModel.modelDescription.classLabels, !labels.isEmpty {
            return labels.map { "\($0)" }
        }

        // TODO: Read a bundled labels file when the model exporter includes one.
        return []
    }
}
