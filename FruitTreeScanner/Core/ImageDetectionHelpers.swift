import Foundation

struct FruitCategoryMapper {
    static let standard = FruitCategoryMapper()

    private let customModelCategoryMapping: [Int: FruitCategory] = [
        0:  .apple,
        1:  .orange,
        2:  .mandarin,
        3:  .pomelo,
        4:  .pear,
        5:  .peach,
        6:  .cherry,
        7:  .grape,
        8:  .persimmon,
        9:  .mango,
        10: .kiwi,
        11: .plum,
        12: .pomegranate,
        13: .loquat,
        14: .lychee,
        15: .longan,
        16: .bayberry,
        17: .jujube,
        18: .hawthorn,
        19: .fig,
        20: .papaya,
        21: .chestnut,
        22: .mulberry,
        23: .blueberry,
        24: .strawberry,
        25: .coconut,
    ]

    private let cocoCategoryMapping: [Int: FruitCategory] = [
        77: .apple,
        78: .orange,
        52: .pear,
    ]

    private let stringCategoryMapping: [String: FruitCategory] = [
        "apple": .apple,
        "orange": .orange,
        "mandarin": .mandarin,
        "tangerine": .mandarin,
        "clementine": .mandarin,
        "pomelo": .pomelo,
        "pear": .pear,
        "peach": .peach,
        "cherry": .cherry,
        "grape": .grape,
        "persimmon": .persimmon,
        "mango": .mango,
        "kiwi": .kiwi,
        "kiwifruit": .kiwi,
        "plum": .plum,
        "pomegranate": .pomegranate,
        "loquat": .loquat,
        "lychee": .lychee,
        "lichee": .lychee,
        "longan": .longan,
        "bayberry": .bayberry,
        "waxberry": .bayberry,
        "jujube": .jujube,
        "hawthorn": .hawthorn,
        "fig": .fig,
        "papaya": .papaya,
        "chestnut": .chestnut,
        "mulberry": .mulberry,
        "blueberry": .blueberry,
        "strawberry": .strawberry,
        "coconut": .coconut,
        "banana": .pear,
    ]

    func category(for identifier: String) -> FruitCategory? {
        if let customID = Int(identifier),
           let mapped = customModelCategoryMapping[customID] {
            return mapped
        }

        if let mapped = stringCategoryMapping[identifier.lowercased()] {
            return mapped
        }

        if let cocoID = Int(identifier),
           let mapped = cocoCategoryMapping[cocoID] {
            return mapped
        }

        return nil
    }
}

struct ImageDetectionDiagnostics: Sendable, Equatable {
    var modelStatus: String = "--"
    var modelName: String = "--"
    var modelFailureReason: String = ""
    var queuedFrameCount: Int = 0
    var processedFrameCount: Int = 0
    var observationCount: Int = 0
    var confidenceFilteredCount: Int = 0
    var unmappedObservationCount: Int = 0
    var mappedFruitCount: Int = 0
    var fallbackFrameCount: Int = 0
    var lastDetectionError: String = ""

    var effectiveFailureReason: String {
        lastDetectionError.isEmpty ? modelFailureReason : lastDetectionError
    }
}

struct ImageDetectionDiagnosticsRecorder {
    private(set) var snapshot = ImageDetectionDiagnostics()

    mutating func apply(modelStatus: ImageDetectorModelStatus) {
        snapshot.modelStatus = modelStatus.hudLabel
        snapshot.modelName = modelStatus.hudDetail
        if case let .fallback(reason) = modelStatus {
            snapshot.modelFailureReason = reason
        } else {
            snapshot.modelFailureReason = ""
        }
    }

    mutating func reset(modelStatus: ImageDetectorModelStatus) {
        snapshot = ImageDetectionDiagnostics()
        apply(modelStatus: modelStatus)
    }

    mutating func recordQueuedFrame() {
        snapshot.queuedFrameCount += 1
    }

    mutating func recordCoreMLDetection(
        observationCount: Int,
        confidenceFilteredCount: Int,
        unmappedObservationCount: Int,
        mappedFruitCount: Int
    ) {
        snapshot.processedFrameCount += 1
        snapshot.observationCount += observationCount
        snapshot.confidenceFilteredCount += confidenceFilteredCount
        snapshot.unmappedObservationCount += unmappedObservationCount
        snapshot.mappedFruitCount += mappedFruitCount
        snapshot.lastDetectionError = ""
    }

    mutating func recordDetectionFailure(_ reason: String) {
        snapshot.processedFrameCount += 1
        snapshot.lastDetectionError = reason
    }

    mutating func recordFallbackFrame(reason: String) {
        snapshot.processedFrameCount += 1
        snapshot.fallbackFrameCount += 1
        snapshot.lastDetectionError = "Fallback 无 2D 边界框，无法参与融合"
        if snapshot.modelFailureReason.isEmpty {
            snapshot.modelFailureReason = reason
        }
    }
}
