import Combine
import Foundation

struct ScanHUDSnapshot: Equatable {
    var pointCount: Int = 0
    var coveragePercent: Int = 0
    var scanCompletion: ScanCompletion = ScanCompletion()
    var visionModelStatus: String = "--"
    var visionModelDetail: String = "--"
    var depthRuntimeStatus: String = "--"
    var exportablePointStatus: String = "NoCloud"
    var processedImageFrames: Int = 0
    var detectedFruitCount: Int = 0
    var fusionStatus: String = "等待扫描"
    var cameraSpeed: Float = 0
    var medianDepth: Float = 0
    var guidanceHint: ScanGuidanceHint = .none
}

enum ScanGuidanceHint: Equatable, Sendable {
    case none
    case tooFast
    case tooClose
    case tooFar
    case trackingLost
    case lowLight
    case sparseDepth
    case goodPace
}

@MainActor
final class ScanHUDState: ObservableObject {
    @Published private(set) var snapshot = ScanHUDSnapshot()

    var pointCount: Int { snapshot.pointCount }
    var coveragePercent: Int { snapshot.coveragePercent }
    var scanCompletion: ScanCompletion { snapshot.scanCompletion }
    var visionModelStatus: String { snapshot.visionModelStatus }
    var visionModelDetail: String { snapshot.visionModelDetail }
    var depthRuntimeStatus: String { snapshot.depthRuntimeStatus }
    var exportablePointStatus: String { snapshot.exportablePointStatus }
    var processedImageFrames: Int { snapshot.processedImageFrames }
    var detectedFruitCount: Int { snapshot.detectedFruitCount }
    var fusionStatus: String { snapshot.fusionStatus }
    var cameraSpeed: Float { snapshot.cameraSpeed }
    var medianDepth: Float { snapshot.medianDepth }
    var guidanceHint: ScanGuidanceHint { snapshot.guidanceHint }

    func resetForNewScan() {
        update(to: ScanHUDSnapshot())
    }

    func update(
        pointCount: Int? = nil,
        coveragePercent: Int? = nil,
        scanCompletion: ScanCompletion? = nil,
        visionModelStatus: String? = nil,
        visionModelDetail: String? = nil,
        depthRuntimeStatus: String? = nil,
        exportablePointStatus: String? = nil,
        processedImageFrames: Int? = nil,
        detectedFruitCount: Int? = nil,
        fusionStatus: String? = nil,
        cameraSpeed: Float? = nil,
        medianDepth: Float? = nil,
        guidanceHint: ScanGuidanceHint? = nil
    ) {
        var next = snapshot
        if let pointCount { next.pointCount = pointCount }
        if let coveragePercent { next.coveragePercent = coveragePercent }
        if let scanCompletion { next.scanCompletion = scanCompletion }
        if let visionModelStatus { next.visionModelStatus = visionModelStatus }
        if let visionModelDetail { next.visionModelDetail = visionModelDetail }
        if let depthRuntimeStatus { next.depthRuntimeStatus = depthRuntimeStatus }
        if let exportablePointStatus { next.exportablePointStatus = exportablePointStatus }
        if let processedImageFrames { next.processedImageFrames = processedImageFrames }
        if let detectedFruitCount { next.detectedFruitCount = detectedFruitCount }
        if let fusionStatus { next.fusionStatus = fusionStatus }
        if let cameraSpeed { next.cameraSpeed = cameraSpeed }
        if let medianDepth { next.medianDepth = medianDepth }
        if let guidanceHint { next.guidanceHint = guidanceHint }
        update(to: next)
    }

    private func update(to next: ScanHUDSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
    }
}

enum ScanHUDValueFormatter {
    static func pointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }

    static func pointDensity(_ density: Float) -> String {
        String(format: "%.0f", density)
    }
}
