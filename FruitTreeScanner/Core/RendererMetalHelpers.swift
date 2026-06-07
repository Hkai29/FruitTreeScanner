import CoreVideo
import Metal
import MetalKit

enum RendererMetalHelpers {
    static func makeUnprojectionPipelineState(
        library: MTLLibrary,
        renderDestination: MTKView,
        device: MTLDevice
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeRGBPipelineState(
        library: MTLLibrary,
        renderDestination: MTKView,
        device: MTLDevice
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "rgbVertex"),
              let fragmentFunction = library.makeFunction(name: "rgbFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeParticlePipelineState(
        library: MTLLibrary,
        renderDestination: MTKView,
        device: MTLDevice
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "particleVertex"),
              let fragmentFunction = library.makeFunction(name: "particleFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeGridPoints(cameraResolution: Float2, numGridPoints: Int) -> [Float2] {
        let area = cameraResolution.x * cameraResolution.y
        let spacing = sqrt(area / Float(numGridPoints))
        let dx = Int(round(cameraResolution.x / spacing))
        let dy = Int(round(cameraResolution.y / spacing))
        var points = [Float2]()
        for gridY in 0 ..< dy {
            let offsetX = Float(gridY % 2) * spacing / 2
            for gridX in 0 ..< dx {
                points.append(
                    Float2(
                        offsetX + (Float(gridX) + 0.5) * spacing,
                        (Float(gridY) + 0.5) * spacing
                    )
                )
            }
        }
        return points
    }

    static func makeTextureCache(device: MTLDevice) -> CVMetalTextureCache {
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        return cache
    }

    static func makeTexture(
        fromPixelBuffer pixelBuffer: CVPixelBuffer,
        pixelFormat: MTLPixelFormat,
        planeIndex: Int,
        textureCache: CVMetalTextureCache
    ) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &texture
        )
        return texture
    }
}
