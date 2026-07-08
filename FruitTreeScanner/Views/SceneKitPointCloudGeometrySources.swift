import SceneKit

enum SceneKitPointCloudGeometrySources {
    static func vertexSource(for positions: [SCNVector3]) -> SCNGeometrySource {
        var vertexData = [Float]()
        vertexData.reserveCapacity(positions.count * 3)
        for position in positions {
            vertexData.append(contentsOf: [position.x, position.y, position.z])
        }
        return SCNGeometrySource(
            data: Data(bytes: vertexData, count: vertexData.count * MemoryLayout<Float>.size),
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
    }

    static func colorSource(
        for colors: [PointCloudColor],
        positionCount: Int
    ) -> SCNGeometrySource {
        var colorData = [Float]()
        colorData.reserveCapacity(positionCount * 4)
        for i in 0..<positionCount {
            if i < colors.count {
                let color = colors[i]
                colorData.append(contentsOf: [color.r, color.g, color.b, color.a])
            } else {
                colorData.append(contentsOf: [0.5, 0.5, 0.5, 1.0])
            }
        }
        return SCNGeometrySource(
            data: Data(bytes: colorData, count: colorData.count * MemoryLayout<Float>.size),
            semantic: .color,
            vectorCount: positionCount,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
    }

    static func pointElement(positionCount: Int) -> SCNGeometryElement {
        let indices = (0..<positionCount).map { Int32($0) }
        return SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size),
            primitiveType: .point,
            primitiveCount: positionCount,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
    }
}
