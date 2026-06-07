import Metal
import Foundation
import simd

/// Metal compute pipeline for GPU-accelerated point cloud processing.
final class MetalComputePipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let voxelKeysPipeline: MTLComputePipelineState
    private let neighborCountsPipeline: MTLComputePipelineState

    struct VoxelFilterUniforms {
        var voxelSize: Float
        var pointCount: Int32
        var maxPoints: Int32
        var confidenceThreshold: Int32
        var pointStartIndex: Int32
    }

    init?(device: MTLDevice) {
        self.device = device
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }
        self.commandQueue = commandQueue

        guard let voxelFn = library.makeFunction(name: "computeVoxelKeys"),
              let neighborFn = library.makeFunction(name: "computeNeighborCounts")
        else { return nil }

        do {
            voxelKeysPipeline = try device.makeComputePipelineState(function: voxelFn)
            neighborCountsPipeline = try device.makeComputePipelineState(function: neighborFn)
        } catch {
            return nil
        }
    }

    // MARK: - Voxel Key Computation (GPU)

    /// Compute voxel keys for all particles on the GPU.
    /// Returns an array of UInt32 voxel hashes (0 = invalid particle).
    func computeVoxelKeys(
        particlesBuffer: MTLBuffer,
        pointCount: Int,
        pointIndex: Int,
        maxPoints: Int,
        voxelSize: Float,
        confidenceThreshold: Int
    ) -> [UInt32]? {
        guard pointCount > 0 else { return nil }

        let outputSize = pointCount * MemoryLayout<UInt32>.stride
        guard let outputBuffer = device.makeBuffer(length: outputSize, options: .storageModeShared) else {
            return nil
        }

        var uniforms = VoxelFilterUniforms(
            voxelSize: voxelSize,
            pointCount: Int32(pointCount),
            maxPoints: Int32(maxPoints),
            confidenceThreshold: Int32(confidenceThreshold),
            pointStartIndex: Int32(pointIndex)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(voxelKeysPipeline)
        encoder.setBuffer(particlesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<VoxelFilterUniforms>.stride, index: 2)

        let threadGroupSize = min(voxelKeysPipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadGroups = (pointCount + threadGroupSize - 1) / threadGroupSize
        encoder.dispatchThreadgroups(
            MTLSize(width: threadGroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let ptr = outputBuffer.contents().bindMemory(to: UInt32.self, capacity: pointCount)
        return Array(UnsafeBufferPointer(start: ptr, count: pointCount))
    }

    /// Compute neighbor counts on GPU for SOR pre-filtering.
    func computeNeighborCounts(
        particlesBuffer: MTLBuffer,
        pointCount: Int,
        pointIndex: Int,
        maxPoints: Int,
        voxelSize: Float,
        confidenceThreshold: Int
    ) -> [UInt32]? {
        guard pointCount > 0 else { return nil }

        let outputSize = pointCount * MemoryLayout<UInt32>.stride
        guard let outputBuffer = device.makeBuffer(length: outputSize, options: .storageModeShared) else {
            return nil
        }

        var uniforms = VoxelFilterUniforms(
            voxelSize: voxelSize,
            pointCount: Int32(pointCount),
            maxPoints: Int32(maxPoints),
            confidenceThreshold: Int32(confidenceThreshold),
            pointStartIndex: Int32(pointIndex)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(neighborCountsPipeline)
        encoder.setBuffer(particlesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<VoxelFilterUniforms>.stride, index: 2)

        let threadGroupSize = min(neighborCountsPipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadGroups = (pointCount + threadGroupSize - 1) / threadGroupSize
        encoder.dispatchThreadgroups(
            MTLSize(width: threadGroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let ptr = outputBuffer.contents().bindMemory(to: UInt32.self, capacity: pointCount)
        return Array(UnsafeBufferPointer(start: ptr, count: pointCount))
    }
}
