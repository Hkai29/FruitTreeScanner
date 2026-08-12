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
