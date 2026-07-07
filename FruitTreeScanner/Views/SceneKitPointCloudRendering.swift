import SceneKit
import UIKit

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
        SceneKitPointCloudNodeFactory.makePointCloudNode(
            vertices: vertices,
            colors: colors,
            pointSize: pointSize,
            bounds: bounds
        )
    }

    static func makeReferenceNode(bounds: PointCloudBounds) -> SCNNode {
        SceneKitPointCloudReferenceGeometry.makeReferenceNode(bounds: bounds)
    }
}
