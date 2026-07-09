import ARKit

enum ScanSessionConfiguration {
    static func preferredDepthSemantics(
        supports: (ARConfiguration.FrameSemantics) -> Bool = {
            ARWorldTrackingConfiguration.supportsFrameSemantics($0)
        }
    ) -> ARConfiguration.FrameSemantics? {
        if supports(.smoothedSceneDepth) {
            return .smoothedSceneDepth
        }
        if supports(.sceneDepth) {
            return .sceneDepth
        }
        return nil
    }

    static func preferredVideoFormat(settings: SettingsStore = .shared) -> ARConfiguration.VideoFormat? {
        let targetFPS = requestedFrameRate(from: settings.cameraFrameRate)
        let targetWidth = requestedResolutionWidth(from: settings.cameraResolution)

        return ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.framesPerSecond <= targetFPS }
            .sorted { lhs, rhs in
                let lhsScore = videoFormatScore(lhs, targetFPS: targetFPS, targetWidth: targetWidth)
                let rhsScore = videoFormatScore(rhs, targetFPS: targetFPS, targetWidth: targetWidth)
                return lhsScore < rhsScore
            }
            .first
    }

    private static func requestedFrameRate(from option: String) -> Int {
        switch option {
        case "30fps": return 30
        case "120fps": return 120
        default: return 60
        }
    }

    private static func requestedResolutionWidth(from option: String) -> Int {
        switch option {
        case "720p": return 1280
        case "4K": return 3840
        default: return 1920
        }
    }

    private static func videoFormatScore(
        _ format: ARConfiguration.VideoFormat,
        targetFPS: Int,
        targetWidth: Int
    ) -> Int {
        let resolution = format.imageResolution
        let width = Int(max(resolution.width, resolution.height))
        return abs(format.framesPerSecond - targetFPS) * 10_000 + abs(width - targetWidth)
    }
}
