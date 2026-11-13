extension PointCloudDenoiser {
    static func statisticalOutlierRemoval(
        samples: [RendererPointSample],
        k: Int = 12,
        stdMultiplier: Float = 1.5
    ) -> [RendererPointSample] {
        statisticalOutlierRemovalDetailed(
            samples: samples,
            k: k,
            stdMultiplier: stdMultiplier
        ).samples
    }

    static func statisticalOutlierRemovalDetailed(
        samples: [RendererPointSample],
        k: Int = 12,
        stdMultiplier: Float = 1.5
    ) -> PointCloudDenoisingResult<RendererPointSample> {
        statisticalOutlierRemovalDetailed(
            samples: samples,
            k: k,
            stdMultiplier: stdMultiplier,
            position: { $0.position }
        )
    }

}
