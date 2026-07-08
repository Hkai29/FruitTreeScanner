import SceneKit
import UIKit

enum SceneKitPointCloudNodeFactory {
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

    private static func makePointNode(
        positions: [SCNVector3],
        colors: [PointCloudColor],
        pointSize: CGFloat
    ) -> SCNNode {
        let source = SceneKitPointCloudGeometrySources.vertexSource(for: positions)
        let colorSource = SceneKitPointCloudGeometrySources.colorSource(
            for: colors,
            positionCount: positions.count
        )
        let element = SceneKitPointCloudGeometrySources.pointElement(positionCount: positions.count)
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
}
