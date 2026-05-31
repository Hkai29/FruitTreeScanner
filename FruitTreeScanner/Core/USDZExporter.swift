import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO
import QuickLook
import ARKit
import MetalKit

final class USDZExporter {
    static let shared = USDZExporter()
    
    private init() {}
    
    func export(
        anchors: [ARMeshAnchor],
        treeID: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task(priority: .utility) {
            do {
                let scene = SCNScene()
                
                for (index, anchor) in anchors.enumerated() {
                    let meshNode = createNode(from: anchor.geometry, transform: anchor.transform)
                    meshNode.name = "mesh_\(index)"
                    scene.rootNode.addChildNode(meshNode)
                }
                
                guard !scene.rootNode.childNodes.isEmpty else {
                    throw USDZExportError.noMeshData
                }
                
                let filename = "\(treeID)_\(Int(Date().timeIntervalSince1970)).usdz"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                
                scene.write(to: tempURL, options: nil, delegate: nil)
                
                await MainActor.run {
                    completion(.success(tempURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func exportPointCloud(
        points: [ColoredPoint],
        treeID: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task(priority: .utility) {
            do {
                let scene = SCNScene()
                
                let geometry = createPointCloudGeometry(from: points)
                let pointNode = SCNNode(geometry: geometry)
                pointNode.name = "pointCloud"
                scene.rootNode.addChildNode(pointNode)
                
                let filename = "\(treeID)_points_\(Int(Date().timeIntervalSince1970)).usdz"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                
                scene.write(to: tempURL, options: nil, delegate: nil)
                
                await MainActor.run {
                    completion(.success(tempURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func createNode(from geometry: ARMeshGeometry, transform: simd_float4x4) -> SCNNode {
        let node = SCNNode()
        
        let vertices = geometry.vertices
        let faces = geometry.faces
        let normals = geometry.normals
        
        let vertexCount = vertices.count
        let faceCount = faces.count
        
        guard vertexCount > 0, faceCount > 0 else { return node }
        
        var scnVertices: [SCNVector3] = []
        var scnNormals: [SCNVector3] = []
        var scnIndices: [Int32] = []
        
        let vertexBufferPtr = vertices.buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
        let vertexStride = vertices.stride
        
        for i in 0..<vertexCount {
            let localV = vertexBufferPtr[i * vertexStride / MemoryLayout<SIMD3<Float>>.stride]
            let worldV = transform * SIMD4<Float>(localV, 1)
            scnVertices.append(SCNVector3(worldV.x, worldV.y, worldV.z))
        }
        
        let normalBufferPtr = normals.buffer.contents()
        let normalStride = normals.stride
        
        for i in 0..<vertexCount {
            let localN = normalBufferPtr.load(fromByteOffset: i * normalStride, as: SIMD3<Float>.self)
            let rotationMatrix = extractRotation(from: transform)
            let worldN = rotationMatrix * localN
            scnNormals.append(SCNVector3(worldN.x, worldN.y, worldN.z))
        }
        
        let indexPointer = faces.buffer.contents()
        let indexCountPerPrimitive = faces.indexCountPerPrimitive
        let bytesPerIndex = faces.bytesPerIndex

        for i in 0..<faceCount {
            for j in 0..<indexCountPerPrimitive {
                let offset = (i * indexCountPerPrimitive + j) * bytesPerIndex
                let index: Int32
                if bytesPerIndex == MemoryLayout<UInt32>.size {
                    index = Int32(indexPointer.load(fromByteOffset: offset, as: UInt32.self))
                } else {
                    index = Int32(indexPointer.load(fromByteOffset: offset, as: UInt16.self))
                }
                scnIndices.append(index)
            }
        }
        
        let vertexSource = SCNGeometrySource(vertices: scnVertices)
        let normalSource = SCNGeometrySource(normals: scnNormals)
        
        let indexData = Data(bytes: scnIndices, count: scnIndices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        let scnGeometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 0.8)
        material.isDoubleSided = true
        scnGeometry.materials = [material]
        
        node.geometry = scnGeometry
        return node
    }
    
    private func createPointCloudGeometry(from points: [ColoredPoint]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var colors: [UInt8] = []
        
        for point in points {
            vertices.append(SCNVector3(point.pos.x, point.pos.y, point.pos.z))
            colors.append(UInt8(point.r * 255))
            colors.append(UInt8(point.g * 255))
            colors.append(UInt8(point.b * 255))
            colors.append(255)
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        let colorData = Data(colors)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertices.count,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: 1,
            dataOffset: 0,
            dataStride: 4
        )
        
        let indices = (0..<vertices.count).map { Int32($0) }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        return SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
    }
    
    private func extractRotation(from matrix: simd_float4x4) -> simd_float3x3 {
        return simd_float3x3(
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
    }
}

enum USDZExportError: LocalizedError {
    case noMeshData
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noMeshData:
            return "没有可导出的网格数据"
        case .exportFailed:
            return "USDZ 导出失败"
        }
    }
}
