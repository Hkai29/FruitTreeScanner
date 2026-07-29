import SceneKit
import UIKit

enum SceneKitPointCloudColorRenderer {
    static func apply(
        colorMode: PointCloudColorMode,
        to pointCloudNode: SCNNode,
        sourceVertices: [SCNVector3],
        sourceColors: [PointCloudColor]
    ) -> Bool {
        guard let geometry = pointCloudNode.geometry,
              let vertexSource = geometry.sources(for: .vertex).first,
              let colorSource = geometry.sources(for: .color).first else { return false }

        let vertexCount = vertexSource.vectorCount
        guard colorSource.vectorCount == vertexCount,
              sourceVertices.count == vertexCount,
              sourceColors.count == vertexCount else { return false }

        let bounds = heightBounds(for: sourceVertices)
        let newColorData = colors(
            for: colorMode,
            originalColors: sourceColors,
            vertexCount: vertexCount,
            positions: sourceVertices,
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
        originalColors: [PointCloudColor],
        vertexCount: Int,
        positions: [SCNVector3],
        minY: Float,
        yRange: Float
    ) -> [Float] {
        var newColorData = [Float]()
        newColorData.reserveCapacity(vertexCount * 4)

        for i in 0..<vertexCount {
            let originalColor = originalColors[i]
            let rgb = adjustedRGB(
                for: colorMode,
                index: i,
                positions: positions,
                minY: minY,
                yRange: yRange,
                originalR: originalColor.r,
                originalG: originalColor.g,
                originalB: originalColor.b
            )
            newColorData.append(contentsOf: [rgb.r, rgb.g, rgb.b, 1.0])
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
