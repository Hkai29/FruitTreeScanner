import Foundation
import SceneKit
import ARKit
import UIKit

final class MeshExporter {
    static let shared = MeshExporter()
    
    private init() {}
    
    enum MeshFormat: String, CaseIterable {
        case usdz = "USDZ"
        case obj = "OBJ"
        case ply = "PLY"
        case stl = "STL"
        
        var fileExtension: String { rawValue.lowercased() }
        
        var icon: String {
            switch self {
            case .usdz: return "cube.transparent"
            case .obj: return "cube"
            case .ply: return "cube.fill"
            case .stl: return "3d.circle"
            }
        }
        
        var description: String {
            switch self {
            case .usdz: return "Apple AR Quick Look 格式"
            case .obj: return "通用 3D 模型格式"
            case .ply: return "点云/网格数据格式"
            case .stl: return "3D 打印常用格式"
            }
        }
    }
    
    func export(
        anchors: [ARMeshAnchor],
        treeID: String,
        format: MeshFormat,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task(priority: .utility) {
            do {
                let vertices = collectVertices(from: anchors)
                let triangles = collectTriangles(from: anchors)
                
                guard !vertices.isEmpty else {
                    throw MeshExportError.noMeshData
                }
                
                let timestamp = Int(Date().timeIntervalSince1970)
                let filename = "\(treeID)_\(timestamp).\(format.fileExtension)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                
                switch format {
                case .usdz:
                    try exportUSDZ(vertices: vertices, to: tempURL)
                case .obj:
                    try exportOBJ(vertices: vertices, triangles: triangles, to: tempURL)
                case .ply:
                    try exportPLY(vertices: vertices, to: tempURL)
                case .stl:
                    try exportSTL(vertices: vertices, triangles: triangles, to: tempURL)
                }
                
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
    
    private func collectVertices(from anchors: [ARMeshAnchor]) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        
        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vertexBuffer = geometry.vertices
            
            let count = vertexBuffer.count
            let stride = vertexBuffer.stride
            let bufferPtr = vertexBuffer.buffer.contents()
            
            for i in 0..<count {
                let offset = i * stride
                let local = bufferPtr
                    .advanced(by: offset)
                    .assumingMemoryBound(to: SIMD3<Float>.self)
                    .pointee
                let world = transform * SIMD4<Float>(local, 1)
                vertices.append(world.xyz)
            }
        }
        
        return vertices
    }
    
    private func collectTriangles(from anchors: [ARMeshAnchor]) -> [(Int, Int, Int)] {
        var triangles: [(Int, Int, Int)] = []
        var vertexOffset = 0
        
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertexBuffer = geometry.vertices
            let faceBuffer = geometry.faces
            
            let vertexCount = vertexBuffer.count
            let faceCount = faceBuffer.count
            let primitiveIndexCount = faceBuffer.indexCountPerPrimitive
            let indexStride = faceBuffer.bytesPerIndex
            guard primitiveIndexCount == 3 else {
                vertexOffset += vertexCount
                continue
            }
            
            let facePtr = faceBuffer.buffer.contents()
            
            for faceIndex in 0..<faceCount {
                var indices: [Int] = []
                
                for j in 0..<primitiveIndexCount {
                    let offset = (faceIndex * primitiveIndexCount + j) * indexStride
                    let index: Int
                    if indexStride == 4 {
                        index = Int(facePtr.load(fromByteOffset: offset, as: UInt32.self))
                    } else {
                        index = Int(facePtr.load(fromByteOffset: offset, as: UInt16.self))
                    }
                    guard index >= 0, index < vertexCount else { continue }
                    indices.append(vertexOffset + index)
                }
                
                if indices.count == 3 {
                    triangles.append((indices[0], indices[1], indices[2]))
                }
            }
            
            vertexOffset += vertexCount
        }
        
        return triangles
    }
    
    private func exportUSDZ(vertices: [SIMD3<Float>], to url: URL) throws {
        let scene = SCNScene()
        
        let scnVertices = vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let vertexSource = SCNGeometrySource(vertices: scnVertices)
        
        let indices = (0..<vertices.count).map { Int32($0) }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1.0)
        geometry.materials = [material]
        
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        
        scene.write(to: url, options: nil, delegate: nil)
    }
    
    private func exportOBJ(vertices: [SIMD3<Float>], triangles: [(Int, Int, Int)], to url: URL) throws {
        var content = "# Wavefront OBJ file\n"
        content += "# Generated by FruitTreeScanner\n\n"
        
        for v in vertices {
            content += "v \(v.x) \(v.y) \(v.z)\n"
        }
        
        content += "\n"
        
        for tri in triangles {
            content += "f \(tri.0 + 1) \(tri.1 + 1) \(tri.2 + 1)\n"
        }
        
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func exportPLY(vertices: [SIMD3<Float>], to url: URL) throws {
        var content = "ply\n"
        content += "format ascii 1.0\n"
        content += "element vertex \(vertices.count)\n"
        content += "property float x\n"
        content += "property float y\n"
        content += "property float z\n"
        content += "end_header\n"
        
        for v in vertices {
            content += "\(v.x) \(v.y) \(v.z)\n"
        }
        
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func exportSTL(vertices: [SIMD3<Float>], triangles: [(Int, Int, Int)], to url: URL) throws {
        var content = "solid mesh\n"
        
        for tri in triangles {
            guard tri.0 < vertices.count, tri.1 < vertices.count, tri.2 < vertices.count else { continue }
            let v0 = vertices[tri.0]
            let v1 = vertices[tri.1]
            let v2 = vertices[tri.2]
            
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))
            
            content += "  facet normal \(normal.x) \(normal.y) \(normal.z)\n"
            content += "    outer loop\n"
            content += "      vertex \(v0.x) \(v0.y) \(v0.z)\n"
            content += "      vertex \(v1.x) \(v1.y) \(v1.z)\n"
            content += "      vertex \(v2.x) \(v2.y) \(v2.z)\n"
            content += "    endloop\n"
            content += "  endfacet\n"
        }
        
        content += "endsolid mesh\n"
        
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum MeshExportError: LocalizedError {
    case noMeshData
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noMeshData: return "没有可导出的网格数据"
        case .exportFailed: return "网格导出失败"
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
