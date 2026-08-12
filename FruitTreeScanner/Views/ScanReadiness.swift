import Foundation
import AVFoundation
import ARKit
import Metal

enum ScanReadiness: Equatable {
    case checking
    case ready
    case arUnsupported
    case metalUnavailable
    case lidarUnavailable
    case cameraDenied
    case cameraRestricted

    var blocksScanning: Bool {
        self != .ready
    }

    var title: String {
        title(in: .main)
    }

    func title(in bundle: Bundle) -> String {
        switch self {
        case .checking: return L10n.ScanReadiness.text(.checkingTitle, in: bundle)
        case .ready: return ""
        case .arUnsupported: return L10n.ScanReadiness.text(.arUnsupportedTitle, in: bundle)
        case .metalUnavailable: return L10n.ScanReadiness.text(.metalUnavailableTitle, in: bundle)
        case .lidarUnavailable: return L10n.ScanReadiness.text(.lidarUnavailableTitle, in: bundle)
        case .cameraDenied: return L10n.ScanReadiness.text(.cameraDeniedTitle, in: bundle)
        case .cameraRestricted: return L10n.ScanReadiness.text(.cameraRestrictedTitle, in: bundle)
        }
    }

    var message: String {
        message(in: .main)
    }

    func message(in bundle: Bundle) -> String {
        switch self {
        case .checking:
            return L10n.ScanReadiness.text(.checkingMessage, in: bundle)
        case .ready:
            return ""
        case .arUnsupported:
            return L10n.ScanReadiness.text(.arUnsupportedMessage, in: bundle)
        case .metalUnavailable:
            return L10n.ScanReadiness.text(.metalUnavailableMessage, in: bundle)
        case .lidarUnavailable:
            return L10n.ScanReadiness.text(.lidarUnavailableMessage, in: bundle)
        case .cameraDenied:
            return L10n.ScanReadiness.text(.cameraDeniedMessage, in: bundle)
        case .cameraRestricted:
            return L10n.ScanReadiness.text(.cameraRestrictedMessage, in: bundle)
        }
    }
}

extension ScanReadiness {
    static func determine() async -> ScanReadiness {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .arUnsupported
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            return .metalUnavailable
        }

        guard ScanSessionConfiguration.preferredDepthSemantics() != nil else {
            return .lidarUnavailable
        }

        return await cameraReadiness(
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video),
            requestAccess: { await AVCaptureDevice.requestAccess(for: .video) }
        )
    }

    static func cameraReadiness(
        authorizationStatus: AVAuthorizationStatus,
        requestAccess: () async -> Bool
    ) async -> ScanReadiness {
        switch authorizationStatus {
        case .authorized:
            return .ready
        case .notDetermined:
            let granted = await requestAccess()
            return granted ? .ready : .cameraDenied
        case .denied:
            return .cameraDenied
        case .restricted:
            return .cameraRestricted
        @unknown default:
            return .cameraDenied
        }
    }
}

@MainActor
final class ScanReadinessRequestController: ObservableObject {
    typealias Determiner = @Sendable () async -> ScanReadiness

    private let determine: Determiner
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    var isRunning: Bool { task != nil }

    init(
        determine: @escaping Determiner = {
            await ScanReadiness.determine()
        }
    ) {
        self.determine = determine
    }

    @discardableResult
    func start(
        onResult: @escaping @MainActor (ScanReadiness) -> Void
    ) -> Task<Void, Never>? {
        guard task == nil else { return nil }
        generation &+= 1
        let requestGeneration = generation
        let determine = determine
        let requestTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let readiness = await determine()
            guard !Task.isCancelled, let self else { return }
            guard self.generation == requestGeneration else { return }
            self.task = nil
            onResult(readiness)
        }
        task = requestTask
        return requestTask
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
