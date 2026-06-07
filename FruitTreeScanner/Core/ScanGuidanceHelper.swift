import ARKit
import CoreVideo

enum ScanGuidanceHelper {

    // MARK: - 速度/距离/追踪 → 引导提示
    static func evaluate(
        speed: Float,
        medianDepth: Float,
        trackingState: ARCamera.TrackingState,
        lightIntensity: CGFloat?
    ) -> ScanGuidanceHint {
        // 优先级：追踪丢失 > 光线 > 速度 > 距离 > 正常
        switch trackingState {
        case .notAvailable, .limited(.initializing):
            return .trackingLost
        case .limited(.excessiveMotion):
            return .tooFast
        case .limited(.insufficientFeatures):
            if let lux = lightIntensity, lux < 120 {
                return .lowLight
            }
            return .trackingLost
        default:
            break
        }

        if let lux = lightIntensity, lux < 120 {
            return .lowLight
        }

        if speed > 0.6 {
            return .tooFast
        }

        if medianDepth > 0 {
            if medianDepth < 0.25 {
                return .tooClose
            }
            if medianDepth > 4.0 {
                return .tooFar
            }
        }

        if speed > 0.01 && speed <= 0.35 {
            return .goodPace
        }

        return .none
    }

    // MARK: - 深度中值采样（轻量级，采 25 个点）
    static func sampleMedianDepth(_ depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard width > 0, height > 0 else { return nil }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let rowFloats = bytesPerRow / MemoryLayout<Float>.size

        var samples: [Float] = []
        samples.reserveCapacity(25)

        for row in stride(from: height / 6, to: height * 5 / 6, by: height / 5) {
            for col in stride(from: width / 6, to: width * 5 / 6, by: width / 5) {
                let d = floatBuffer[row * rowFloats + col]
                if d > 0.1 && d < 10.0 {
                    samples.append(d)
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}
