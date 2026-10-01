import ARKit

struct ScanVideoFormatDescriptor: Equatable {
    let framesPerSecond: Int
    let imageWidth: Int
}

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
        preferredVideoFormat(request: ScanCameraRequest(resolution: settings.cameraResolution, frameRate: settings.cameraFrameRate))
    }

    static func preferredVideoFormat(request: ScanCameraRequest) -> ARConfiguration.VideoFormat? {
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        let descriptions = formats.map { format in
            ScanVideoFormatDescriptor(framesPerSecond: format.framesPerSecond,
                imageWidth: Int(max(format.imageResolution.width, format.imageResolution.height)))
        }
        guard let index = preferredVideoFormatIndex(in: descriptions, request: request) else { return nil }
        return formats[index]
    }

    /// Preserve the established policy: respect the FPS ceiling, prioritize FPS,
    /// then choose the closest resolution. nil leaves ARKit's default unchanged.
    static func preferredVideoFormatIndex(in formats: [ScanVideoFormatDescriptor], request: ScanCameraRequest) -> Int? {
        let candidates = formats.indices.filter { formats[$0].framesPerSecond <= request.targetFramesPerSecond }
        return candidates.min { lhs, rhs in
            videoFormatScore(formats[lhs], request: request) < videoFormatScore(formats[rhs], request: request)
        }
    }

    private static func videoFormatScore(_ format: ScanVideoFormatDescriptor, request: ScanCameraRequest) -> Int {
        abs(format.framesPerSecond - request.targetFramesPerSecond) * 10_000 + abs(format.imageWidth - request.targetImageWidth)
    }
}
