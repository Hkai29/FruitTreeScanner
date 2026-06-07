import ARKit
import CoreGraphics

enum ScanQualitySampler {
    static func makeSample(from frame: ARFrame) -> ScanQualitySample {
        ScanQualitySample(
            pointDensity: calculatePointDensity(from: frame.rawFeaturePoints),
            trackingState: frame.camera.trackingState,
            scanAngle: abs(frame.camera.eulerAngles.x * 180 / .pi),
            ambientIntensity: frame.lightEstimate?.ambientIntensity
        )
    }

    private static func calculatePointDensity(from pointCloud: ARPointCloud?) -> Float {
        guard let points = pointCloud?.points, !points.isEmpty else { return 0 }

        let maxSamples = 240
        let step = max(points.count / maxSamples, 1)
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude
        var sampledCount = 0

        var index = 0
        while index < points.count {
            let point = points[index]
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
            sampledCount += 1
            index += step
        }

        guard sampledCount > 0 else { return 0 }
        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)
        guard volume > 0 else { return 0 }
        return Float(points.count) / volume
    }
}
