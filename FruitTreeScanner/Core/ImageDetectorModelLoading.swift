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
