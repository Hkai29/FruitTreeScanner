// RendererFrameRendering.swift
// Per-frame Metal rendering and point accumulation.

import ARKit
import CoreVideo
import Metal
import MetalKit
import UIKit

extension Renderer {
    func renderFrame() {
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let drawable = renderDestination.currentDrawable
        else { return }

        guard inFlightSemaphore.wait(timeout: .now() + .milliseconds(16)) == .success else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor)
        else {
            inFlightSemaphore.signal()
            return
        }

        let framePointBuffer = pointBufferSnapshot()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            self.inFlightSemaphore.signal()
            if self.isRecording {
                self.updateSnapshot()
            }
        }
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms

        if shouldAccumulate(frame: currentFrame, pointCount: framePointBuffer.count), updateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder, pointIndex: framePointBuffer.index)
        }

        if rgbUniforms.radius > 0, let texY = capturedImageTextureY, let texCbCr = capturedImageTextureCbCr {
            var retaining = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
            rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
            renderEncoder.setDepthStencilState(relaxedStencilState)
            renderEncoder.setRenderPipelineState(rgbPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(texY), index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(texCbCr), index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: framePointBuffer.count)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func update(frame: ARFrame) {
        hasReceivedFirstFrame = true
        updateOrientation()
        updateCameraResolutionIfNeeded(frame: frame)

        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: orientation)
        let projMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        pointCloudUniforms.viewProjectionMatrix = projMatrix * viewMatrix
        pointCloudUniforms.localToWorld = viewMatrix.inverse * Self.makeRotateToARCameraMatrix(orientation: orientation)
        pointCloudUniforms.cameraIntrinsicsInversed = camera.intrinsics.inverse
        rgbUniforms.viewToCamera = makeViewToCameraMatrix(frame: frame)
        rgbUniforms.viewRatio = Float(viewportSize.width / max(viewportSize.height, 1))
    }

    func shouldAccumulate(frame: ARFrame, pointCount currentCount: Int) -> Bool {
        guard isRecording else { return false }
        let ct = frame.camera.transform

        let cameraMoved = Self.shouldAccumulateCameraMotion(
            currentTransform: ct,
            lastTransform: lastCameraTransform,
            currentPointCount: currentCount,
            rotationCosineThreshold: cameraRotationThreshold,
            translationSquaredThreshold: cameraTranslationThreshold
        )

        guard cameraMoved else { return false }

        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap else { return false }

        let depthQuality = RendererDepthCoverage.sampleDepthQuality(
            from: depthMap,
            confidenceMap: confidenceMap,
            minDepth: minDepth,
            maxDepth: maxDepth,
            confidenceThreshold: confidenceThreshold
        )
        guard depthQuality.validRatio >= RendererDepthCoverage.minimumDepthQualityRatio(
            confidenceThreshold: confidenceThreshold
        ) else { return false }
        guard depthQuality.medianDepth >= minDepth && depthQuality.medianDepth <= maxDepth else { return false }

        let cameraRegion = RendererDepthCoverage.makeCameraRegionKey(frame: frame)
        if scannedRegions.contains(cameraRegion) && currentCount > 5000 {
            return false
        }
        scannedRegions.insert(cameraRegion)

        return true
    }

    static func shouldAccumulateCameraMotion(
        currentTransform: simd_float4x4,
        lastTransform: simd_float4x4,
        currentPointCount: Int,
        rotationCosineThreshold: Float,
        translationSquaredThreshold: Float
    ) -> Bool {
        currentPointCount == 0
            || dot(currentTransform.columns.2, lastTransform.columns.2) <= rotationCosineThreshold
            || distance_squared(currentTransform.columns.3, lastTransform.columns.3) >= translationSquaredThreshold
    }

    func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder, pointIndex: Int) {
        guard let texY = capturedImageTextureY,
              let texCbCr = capturedImageTextureCbCr,
              let texDepth = depthTexture,
              let texConf = confidenceTexture else { return }

        pointCloudUniforms.pointCloudCurrentIndex = Int32(pointIndex)
        var retaining = [capturedImageTextureY, capturedImageTextureCbCr, depthTexture, confidenceTexture]
        commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texY), index: Int(kTextureY.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texCbCr), index: Int(kTextureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texDepth), index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texConf), index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        pointBufferLock.lock()
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        pointBufferLock.unlock()
        lastCameraTransform = frame.camera.transform
        updateCoverageVoxels(frame: frame)
    }

}
