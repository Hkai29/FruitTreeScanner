import SceneKit
import UIKit

enum SceneKitPointCloudReferenceGeometry {
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
        let source = SceneKitPointCloudGeometrySources.vertexSource(for: points)
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
}
