import ARKit
import Foundation

final class ScanMeshExportService {
    static let shared = ScanMeshExportService()

    private init() {}

    func exportOBJ(treeID: String, anchors: [ARMeshAnchor], completion: @escaping (String?) -> Void) {
        guard !anchors.isEmpty else {
            completion(nil)
            return
        }

        Task(priority: .utility) {
            do {
                let objContent = makeOBJContent(treeID: treeID, anchors: anchors)
                let filename = makeTreeFileName(treeID: treeID, lat: 0, lon: 0)
                    .replacingOccurrences(of: ".ply", with: ".obj")
                try await saveFile(data: Data(objContent.utf8), filename: filename, folder: "scans")

                #if DEBUG
                print("✅ OBJ 导出成功: \(filename)")
                #endif
                await MainActor.run { completion(filename) }
            } catch {
                #if DEBUG
                print("❌ OBJ 导出失败: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(nil) }
            }
        }
    }

    func exportUSDZ(treeID: String, anchors: [ARMeshAnchor], completion: @escaping (URL?) -> Void) {
        guard !anchors.isEmpty else {
            completion(nil)
            return
        }

        USDZExporter.shared.export(anchors: anchors, treeID: treeID) { result in
            switch result {
            case .success(let url):
                completion(url)
            case .failure(let error):
                #if DEBUG
                print("❌ USDZ 导出失败: \(error.localizedDescription)")
                #endif
                completion(nil)
            }
        }
    }

    func exportPointCloudUSDZ(treeID: String, points: [ColoredPoint], completion: @escaping (URL?) -> Void) {
        guard !points.isEmpty else {
            completion(nil)
            return
        }

        USDZExporter.shared.exportPointCloud(points: points, treeID: treeID) { result in
            switch result {
            case .success(let url):
                completion(url)
            case .failure(let error):
                #if DEBUG
                print("❌ 点云 USDZ 导出失败: \(error.localizedDescription)")
                #endif
                completion(nil)
            }
        }
    }

    private func makeOBJContent(treeID: String, anchors: [ARMeshAnchor]) -> String {
        var objContent = "# FruitTreeScanner OBJ Export\n"
        objContent += "# tree_id: \(treeID)\n"
        objContent += "# mesh_anchors: \(anchors.count)\n\n"

        var globalVertexOffset = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            let transform = anchor.transform

            let vertexBufferPointer = vertices.buffer.contents()
            let vertexStride = vertices.stride

            for index in 0..<vertices.count {
                let localVertex = vertexBufferPointer
                    .advanced(by: index * vertexStride)
                    .assumingMemoryBound(to: SIMD3<Float>.self)
                    .pointee
                let worldVertex = transform * SIMD4<Float>(localVertex, 1)
                objContent += "v \(worldVertex.x) \(worldVertex.y) \(worldVertex.z)\n"
            }

            for faceIndex in 0..<faces.count {
                let indices = faceIndices(at: faceIndex, in: faces)
                guard indices.count == 3 else { continue }
                let i0 = indices[0] + globalVertexOffset + 1
                let i1 = indices[1] + globalVertexOffset + 1
                let i2 = indices[2] + globalVertexOffset + 1
                objContent += "f \(i0) \(i1) \(i2)\n"
            }

            globalVertexOffset += vertices.count
        }

        return objContent
    }

    private func faceIndices(at faceIndex: Int, in faces: ARGeometryElement) -> [Int] {
        let indexCount = faces.indexCountPerPrimitive
        let bytesPerIndex = faces.bytesPerIndex
        let baseOffset = faceIndex * indexCount * bytesPerIndex
        let pointer = faces.buffer.contents()

        return (0..<indexCount).map { indexOffset in
            let byteOffset = baseOffset + indexOffset * bytesPerIndex
            if bytesPerIndex == MemoryLayout<UInt32>.size {
                return Int(pointer.load(fromByteOffset: byteOffset, as: UInt32.self))
            }
            return Int(pointer.load(fromByteOffset: byteOffset, as: UInt16.self))
        }
    }
}
