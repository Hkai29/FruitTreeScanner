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
}

enum ImageDetectorModelLoader {
    static func loadModel(named name: String) throws -> ImageDetectorLoadedModel {
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            let mlModel = try MLModel(contentsOf: modelURL)
            let model = try VNCoreMLModel(for: mlModel)
            return ImageDetectorLoadedModel(model: model, resourceName: name, bundleExtension: "mlmodelc")
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            return ImageDetectorLoadedModel(model: model, resourceName: name, bundleExtension: "mlmodel")
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)
            let model = try VNCoreMLModel(for: mlModel)
            return ImageDetectorLoadedModel(model: model, resourceName: name, bundleExtension: "mlpackage")
        }

        throw NSError(
            domain: "ImageDetector",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(name)"]
        )
    }
}
