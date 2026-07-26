// RendererFrameSupport.swift
// Per-frame camera, texture, and coverage helpers.

import ARKit
import CoreVideo
import Metal
import UIKit

extension Renderer {
    func updateOrientation() {
        let sceneOrientation = renderDestination.window?.windowScene?.interfaceOrientation
        let nextOrientation: UIInterfaceOrientation

        if let sceneOrientation, sceneOrientation != .unknown {
            nextOrientation = sceneOrientation
        } else if viewportSize.width > viewportSize.height {
            nextOrientation = .landscapeRight
        } else {
            nextOrientation = .portrait
        }

        orientation = nextOrientation
    }

    func updateCameraResolutionIfNeeded(frame: ARFrame) {
        let nextResolution = Float2(
            Float(frame.camera.imageResolution.width),
            Float(frame.camera.imageResolution.height)
        )

        guard abs(nextResolution.x - cameraResolution.x) > 0.5 ||
              abs(nextResolution.y - cameraResolution.y) > 0.5 else {
            return
        }

        cameraResolution = nextResolution
        pointCloudUniforms.cameraResolution = cameraResolution
        gridPointsBuffer = MetalBuffer<Float2>(
            device: device,
            array: RendererMetalHelpers.makeGridPoints(
                cameraResolution: cameraResolution,
                numGridPoints: numGridPoints
            ),
            index: kGridPoints.rawValue,
            options: []
        )
    }

    func updateCapturedImageTextures(frame: ARFrame) {
        let pb = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pb) >= 2,
              let nextY = RendererMetalHelpers.makeTexture(
                  fromPixelBuffer: pb,
                  pixelFormat: .r8Unorm,
                  planeIndex: 0,
                  textureCache: textureCache
              ),
              let nextCbCr = RendererMetalHelpers.makeTexture(
                  fromPixelBuffer: pb,
                  pixelFormat: .rg8Unorm,
                  planeIndex: 1,
                  textureCache: textureCache
              ) else {
            capturedImageTextureY = nil
            capturedImageTextureCbCr = nil
            return
        }
        capturedImageTextureY = nextY
        capturedImageTextureCbCr = nextCbCr
    }

    func updateDepthTextures(frame: ARFrame) -> Bool {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap,
              let nextTextures = RendererMetalHelpers.makeDepthTexturePair(
                  depthMap: depthMap,
                  confidenceMap: confidenceMap,
                  textureCache: textureCache
              ) else {
            depthTexture = nil
            confidenceTexture = nil
            return false
        }
        depthTexture = nextTextures.depth
        confidenceTexture = nextTextures.confidence
        return true
    }

    func updateCoverageVoxels(frame: ARFrame) {
        let newVoxels = RendererDepthCoverage.makeCoverageVoxels(
            frame: frame,
            orientation: orientation,
            viewportSize: viewportSize,
            minDepth: minDepth,
            maxDepth: maxDepth,
            confidenceThreshold: confidenceThreshold,
            voxelSize: coverageVoxelSize
        )
        guard !newVoxels.isEmpty else { return }

        if coverageVoxels.isEmpty {
            coverageVoxels = newVoxels
        } else {
            coverageVoxels.formUnion(newVoxels)
        }

        scanProgress.recordVoxelCount(coverageVoxels.count)
    }

    func makeViewToCameraMatrix(frame: ARFrame) -> matrix_float3x3 {
        let t = frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
        let a = Float(t.a)
        let b = Float(t.b)
        let c = Float(t.c)
        let d = Float(t.d)
        let tx = Float(t.tx)
        let ty = Float(t.ty)
        var result = matrix_float3x3()
        result[0] = simd_float3(a, b, 0)
        result[1] = simd_float3(c, d, 0)
        result[2] = simd_float3(tx, ty, 1)
        return result
    }

    static func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft: return 180
        case .portrait: return 90
        case .portraitUpsideDown: return -90
        default: return 0
        }
    }

    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        let flipYZ = matrix_float4x4([1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, 0], [0, 0, 0, 1])
        let angle = Float(cameraToDisplayRotation(orientation: orientation)) * Float.degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(angle, Float3(0, 0, 1)))
    }
}
