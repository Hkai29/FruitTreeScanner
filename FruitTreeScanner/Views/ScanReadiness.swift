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
        switch self {
        case .checking: return "正在检查设备能力"
        case .ready: return ""
        case .arUnsupported: return "当前设备不支持 AR 扫描"
        case .metalUnavailable: return "图形渲染不可用"
        case .lidarUnavailable: return "当前设备没有 LiDAR 深度"
        case .cameraDenied: return "相机权限未开启"
        case .cameraRestricted: return "相机权限受限"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "正在确认相机、ARKit 和深度扫描链路。"
        case .ready:
            return ""
        case .arUnsupported:
            return "FruitTreeScanner 需要 ARKit 才能采集点云。请使用支持 ARKit 的 iPhone 或 iPad。"
        case .metalUnavailable:
            return "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。"
        case .lidarUnavailable:
            return "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。"
        case .cameraDenied:
            return "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。"
        case .cameraRestricted:
            return "系统限制了相机访问，当前无法开始扫描。"
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

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
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
