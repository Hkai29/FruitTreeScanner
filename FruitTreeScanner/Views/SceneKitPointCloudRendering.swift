import SceneKit
import UIKit

enum SceneKitPointCloudColorRenderer {
    static func apply(colorMode: PointCloudColorMode, to pointCloudNode: SCNNode) -> Bool {
        guard let geometry = pointCloudNode.geometry,
              let colorSource = geometry.sources(for: .color).first else { return false }

        let vertexCount = colorSource.vectorCount
        let positions = positions(from: geometry, vertexCount: vertexCount)
        let bounds = heightBounds(for: positions)
        let newColorData = colors(
            for: colorMode,
            originalColorData: colorSource.data,
            vertexCount: vertexCount,
            positions: positions,
            minY: bounds.minY,
            yRange: bounds.yRange
        )

        guard newColorData.count == vertexCount * 4 else { return false }

        let newSource = SCNGeometrySource(
            data: Data(bytes: newColorData, count: newColorData.count * MemoryLayout<Float>.size),
            semantic: .color,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        var newSources = geometry.sources
        newSources.removeAll { $0.semantic == .color }
        newSources.append(newSource)

        let newGeometry = SCNGeometry(sources: newSources, elements: geometry.elements)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        newGeometry.materials = [material]

        if let pointSize = geometry.value(forKey: "pointSize") as? CGFloat {
            newGeometry.setValue(pointSize, forKey: "pointSize")
            newGeometry.setValue(1, forKey: "pointSizeMode")
        }

        pointCloudNode.geometry = newGeometry
        return true
    }

    private static func positions(from geometry: SCNGeometry, vertexCount: Int) -> [SCNVector3] {
        guard let posSource = geometry.sources(for: .vertex).first else { return [] }
        return posSource.data.withUnsafeBytes { ptr -> [SCNVector3] in
            let buffer = ptr.bindMemory(to: Float.self)
            var result: [SCNVector3] = []
            result.reserveCapacity(vertexCount)
            for i in 0..<vertexCount {
                let idx = i * 3
                if idx + 2 < buffer.count {
                    result.append(SCNVector3(buffer[idx], buffer[idx + 1], buffer[idx + 2]))
                }
            }
            return result
        }
    }

    private static func heightBounds(for positions: [SCNVector3]) -> (minY: Float, yRange: Float) {
        guard !positions.isEmpty else { return (0, 0.001) }
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        for position in positions {
            minY = min(minY, position.y)
            maxY = max(maxY, position.y)
        }
        return (minY, max(maxY - minY, 0.001))
    }

    private static func colors(
        for colorMode: PointCloudColorMode,
        originalColorData: Data,
        vertexCount: Int,
        positions: [SCNVector3],
        minY: Float,
        yRange: Float
    ) -> [Float] {
        var newColorData = [Float]()
        newColorData.reserveCapacity(vertexCount * 4)

        originalColorData.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Float.self)
            for i in 0..<vertexCount {
                let baseIdx = i * 4
                guard baseIdx + 3 < buffer.count else { continue }
                let rgb = adjustedRGB(
                    for: colorMode,
                    index: i,
                    positions: positions,
                    minY: minY,
                    yRange: yRange,
                    originalR: buffer[baseIdx],
                    originalG: buffer[baseIdx + 1],
                    originalB: buffer[baseIdx + 2]
                )
                newColorData.append(contentsOf: [rgb.r, rgb.g, rgb.b, 1.0])
            }
        }

        return newColorData
    }

    private static func adjustedRGB(
        for colorMode: PointCloudColorMode,
        index: Int,
        positions: [SCNVector3],
        minY: Float,
        yRange: Float,
        originalR: Float,
        originalG: Float,
        originalB: Float
    ) -> (r: Float, g: Float, b: Float) {
        switch colorMode {
        case .height:
            let t = index < positions.count ? (positions[index].y - minY) / yRange : 0.5
            let midGlow = 1 - abs(t - 0.5) * 2
            return (
                0.24 + 0.76 * t,
                0.28 + 0.44 * midGlow,
                0.30 + 0.70 * (1 - t)
            )
        case .density:
            let brightness = (originalR + originalG + originalB) / 3
            return (
                0.16 + brightness * 0.45,
                0.22 + brightness * 0.58,
                0.30 + brightness * 0.68
            )
        case .fruit:
            let isFruitLike = originalR > 0.4 && originalG < 0.5
            return (
                isFruitLike ? 1.0 : originalR * 0.42,
                isFruitLike ? 0.58 : originalG * 0.42,
                isFruitLike ? 0.04 : originalB * 0.42
            )
        case .uniform:
            return (0.48, 0.88, 0.46)
        }
    }
}

enum SceneKitPointCloudGeometry {
    static func bounds(for vertices: [SCNVector3]) -> PointCloudBounds? {
        PointCloudBounds(vertices: vertices)
    }

    static func makePointCloudNode(
        vertices: [SCNVector3],
        colors: [PointCloudColor],
        pointSize: CGFloat,
        bounds: PointCloudBounds? = nil
    ) -> SCNNode? {
        guard !vertices.isEmpty else { return nil }
        let pointBounds = bounds ?? PointCloudBounds(vertices: vertices)
        guard let pointBounds else { return nil }
        let positions = vertices.map {
            SCNVector3(
                $0.x - pointBounds.center.x,
                $0.y - pointBounds.center.y,
                $0.z - pointBounds.center.z
            )
        }
        return makePointNode(positions: positions, colors: colors, pointSize: pointSize)
    }

    static func makeReferenceNode(bounds: PointCloudBounds) -> SCNNode {
        let root = SCNNode()
        root.name = "pointCloudReference"

        let groundY = bounds.min.y - bounds.center.y
        let topY = bounds.max.y - bounds.center.y
        let halfX = max(bounds.size.x / 2, 0.25)
        let halfZ = max(bounds.size.z / 2, 0.25)
        let margin: Float = max(max(bounds.size.x, bounds.size.z) * 0.12, 0.18)
        let minX = -halfX - margin
        let maxX = halfX + margin
        let minZ = -halfZ - margin
        let maxZ = halfZ + margin

        root.addChildNode(makeGridNode(
            minX: minX,
            maxX: maxX,
            minZ: minZ,
            maxZ: maxZ,
            y: groundY
        ))

        root.addChildNode(makeLineNode(
            points: [
                SCNVector3(minX, groundY, minZ),
                SCNVector3(minX, topY, minZ)
            ],
            color: UIColor(Design.Colors.harvest),
            name: "heightRuler",
            width: 2
        ))

        root.addChildNode(makeLineNode(
            points: [
                SCNVector3(minX - 0.04, groundY, minZ),
                SCNVector3(minX + 0.18, groundY, minZ),
                SCNVector3(minX - 0.04, topY, minZ),
                SCNVector3(minX + 0.18, topY, minZ)
            ],
            color: UIColor(Design.Colors.harvest),
            name: "heightTicks",
            width: 2
        ))

        root.addChildNode(makeLineNode(
            points: [
                SCNVector3(0, groundY, 0),
                SCNVector3(0, topY, 0)
            ],
            color: UIColor.white.withAlphaComponent(0.22),
            name: "verticalAxis",
            width: 1
        ))

        return root
    }

    private static func makePointNode(
        positions: [SCNVector3],
        colors: [PointCloudColor],
        pointSize: CGFloat
    ) -> SCNNode {
        let source = vertexSource(for: positions)
        let colorSource = colorSource(for: colors, positionCount: positions.count)
        let element = pointElement(positionCount: positions.count)
        let geometry = SCNGeometry(sources: [source, colorSource], elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        geometry.setValue(pointSize, forKey: "pointSize")
        geometry.setValue(1, forKey: "pointSizeMode")

        let node = SCNNode(geometry: geometry)
        node.name = "pointCloud"
        return node
    }

    private static func makeGridNode(
        minX: Float,
        maxX: Float,
        minZ: Float,
        maxZ: Float,
        y: Float
    ) -> SCNNode {
        let lineCount = 8
        var points: [SCNVector3] = []
        points.reserveCapacity((lineCount + 1) * 4)

        for index in 0...lineCount {
            let t = Float(index) / Float(lineCount)
            let x = minX + (maxX - minX) * t
            let z = minZ + (maxZ - minZ) * t
            points.append(SCNVector3(x, y, minZ))
            points.append(SCNVector3(x, y, maxZ))
            points.append(SCNVector3(minX, y, z))
            points.append(SCNVector3(maxX, y, z))
        }

        return makeLineNode(
            points: points,
            color: UIColor.white.withAlphaComponent(0.16),
            name: "groundGrid",
            width: 1
        )
    }

    private static func makeLineNode(
        points: [SCNVector3],
        color: UIColor,
        name: String,
        width: CGFloat
    ) -> SCNNode {
        let source = vertexSource(for: points)
        let indices = (0..<points.count).map { Int32($0) }
        let element = SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size),
            primitiveType: .line,
            primitiveCount: points.count / 2,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        geometry.materials = [material]
        geometry.setValue(width, forKey: "lineWidth")

        let node = SCNNode(geometry: geometry)
        node.name = name
        return node
    }

    private static func vertexSource(for positions: [SCNVector3]) -> SCNGeometrySource {
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

    private static func colorSource(
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

    private static func pointElement(positionCount: Int) -> SCNGeometryElement {
        let indices = (0..<positionCount).map { Int32($0) }
        return SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size),
            primitiveType: .point,
            primitiveCount: positionCount,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
    }
}
