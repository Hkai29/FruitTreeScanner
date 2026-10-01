import simd

/// Raw image pixels use right/down/forward axes; ARKit cameras use
/// right/up/backward axes. Depth is the optical Z distance in meters.
enum ImageCameraCoordinateSpace {
    static func cameraPoint(
        imagePoint: SIMD3<Float>,
        depth: Float,
        inverseIntrinsics: simd_float3x3
    ) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0 else { return nil }
        let ray = inverseIntrinsics * imagePoint
        guard ray.x.isFinite, ray.y.isFinite, ray.z.isFinite,
              abs(ray.z) > 1e-6 else { return nil }
        let opticalPoint = ray * (depth / ray.z)
        guard opticalPoint.x.isFinite, opticalPoint.y.isFinite,
              opticalPoint.z.isFinite, opticalPoint.z > 0 else { return nil }
        return SIMD3<Float>(opticalPoint.x, -opticalPoint.y, -opticalPoint.z)
    }

    static func worldPoint(cameraPoint: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float>? {
        let point = transform * SIMD4<Float>(cameraPoint, 1)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              point.w.isFinite, abs(point.w) > 1e-6 else { return nil }
        let world = SIMD3<Float>(point.x, point.y, point.z) / point.w
        guard world.x.isFinite, world.y.isFinite, world.z.isFinite else { return nil }
        return world
    }
}
