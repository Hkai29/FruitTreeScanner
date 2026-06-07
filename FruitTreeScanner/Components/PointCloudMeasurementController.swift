import SceneKit
import SwiftUI

final class PointCloudMeasurementController: NSObject, ObservableObject {
    weak var sceneView: SCNView?

    @Published var isActive = false
    @Published var measuredDistance: Float?

    private var point1World: SCNVector3?
    private var point2World: SCNVector3?
    private var markerNode1: SCNNode?
    private var markerNode2: SCNNode?
    private var lineNode: SCNNode?
    private let startMarkerColor = UIColor(red: 184 / 255, green: 86 / 255, blue: 75 / 255, alpha: 1)
    private let endMarkerColor = UIColor(red: 77 / 255, green: 117 / 255, blue: 136 / 255, alpha: 1)

    func handleTap(at viewPoint: CGPoint) {
        guard isActive, let sceneView else { return }

        let hitResults = sceneView.hitTest(viewPoint, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.boundingBoxOnly: false
        ])

        guard let hit = hitResults.first(where: { $0.node.name == "pointCloud" || $0.node.parent?.name == "pointCloud" }) else {
            return
        }

        let worldPosition = hit.worldCoordinates
        if point1World == nil {
            point1World = worldPosition
            addMarker(at: worldPosition, isFirst: true)
        } else if point2World == nil {
            point2World = worldPosition
            addMarker(at: worldPosition, isFirst: false)
            calculateDistance()
        } else {
            clearMeasurements()
            point1World = worldPosition
            addMarker(at: worldPosition, isFirst: true)
        }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        clearMeasurements()
    }

    func deactivate() {
        guard isActive || measuredDistance != nil else { return }
        isActive = false
        clearMeasurements()
    }

    func toggleActive() {
        isActive ? deactivate() : activate()
    }

    func clearMeasurements() {
        point1World = nil
        point2World = nil
        measuredDistance = nil

        markerNode1?.removeFromParentNode()
        markerNode2?.removeFromParentNode()
        lineNode?.removeFromParentNode()

        markerNode1 = nil
        markerNode2 = nil
        lineNode = nil
    }

    private func addMarker(at position: SCNVector3, isFirst: Bool) {
        let sphere = SCNSphere(radius: 0.02)
        let color = isFirst ? startMarkerColor : endMarkerColor
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = isFirst
            ? startMarkerColor.withAlphaComponent(0.3)
            : endMarkerColor.withAlphaComponent(0.3)

        let marker = SCNNode(geometry: sphere)
        marker.position = position
        marker.name = isFirst ? "marker1" : "marker2"

        if isFirst {
            markerNode1?.removeFromParentNode()
            markerNode1 = marker
        } else {
            markerNode2?.removeFromParentNode()
            markerNode2 = marker
        }

        sceneView?.scene?.rootNode.addChildNode(marker)
    }

    private func calculateDistance() {
        guard let p1 = point1World, let p2 = point2World else { return }

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dz = p2.z - p1.z
        measuredDistance = sqrt(dx * dx + dy * dy + dz * dz)

        addLineBetween(p1, and: p2)
    }

    private func addLineBetween(_ p1: SCNVector3, and p2: SCNVector3) {
        lineNode?.removeFromParentNode()

        let vector = SCNVector3(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

        let cylinder = SCNCylinder(radius: 0.005, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.white
        cylinder.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.3)

        let line = SCNNode(geometry: cylinder)
        line.name = "measureLine"
        line.position = SCNVector3((p1.x + p2.x) / 2, (p1.y + p2.y) / 2, (p1.z + p2.z) / 2)

        let up = SCNVector3(0, 1, 0)
        let cross = SCNVector3(
            up.y * vector.z - up.z * vector.y,
            up.z * vector.x - up.x * vector.z,
            up.x * vector.y - up.y * vector.x
        )
        let crossLength = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)

        if crossLength > 0.001 {
            let dot = up.x * vector.x + up.y * vector.y + up.z * vector.z
            let angle = atan2(crossLength, dot)
            line.rotation = SCNVector4(cross.x / crossLength, cross.y / crossLength, cross.z / crossLength, angle)
        }

        lineNode = line
        sceneView?.scene?.rootNode.addChildNode(line)
    }
}

struct MeasurementToolbarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Design.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))

                Text(label)
                    .font(Design.Typography.caption)
            }
            .foregroundColor(isActive ? Design.Colors.harvest : .white)
            .frame(width: 60, height: 56)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(isActive ? Design.Colors.harvest.opacity(0.2) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
                    )
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
