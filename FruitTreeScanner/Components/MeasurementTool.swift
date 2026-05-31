import SwiftUI
import SceneKit

struct MeasurementTool: View {
    @Binding var isActive: Bool
    @Binding var measuredDistance: Float?
    let onMeasure: (CGPoint) -> Void
    
    @State private var point1: CGPoint?
    @State private var point2: CGPoint?
    @State private var distanceIn3D: Float?
    
    var body: some View {
        ZStack {
            if isActive {
                measurementOverlay
            }
        }
    }
    
    private var measurementOverlay: some View {
        GeometryReader { geo in
            ZStack {
                if let p1 = point1 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                        .position(p1)
                        .shadow(color: .red.opacity(0.5), radius: 4)
                }
                
                if let p1 = point1, let p2 = point2 {
                    LineBetweenPoints(from: p1, to: p2)
                    
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .position(p2)
                        .shadow(color: .blue.opacity(0.5), radius: 4)
                    
                    distanceLabel(at: midPoint(p1, p2), distance: distanceIn3D)
                }
                
                instructionBanner
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handleTap(at: value.location)
                    }
            )
        }
    }
    
    private var instructionBanner: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(point1 == nil ? "点击第1个点" : (point2 == nil ? "点击第2个点" : "测量完成"))
                        .font(.system(size: 12, weight: .medium))
                    Text(point1 == nil ? "开始测量" : (point2 == nil ? "确定终点" : "点击任意处重置"))
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
            Spacer()
        }
    }
    
    private func handleTap(at location: CGPoint) {
        if point1 == nil {
            point1 = location
            onMeasure(location)
        } else if point2 == nil {
            point2 = location
            onMeasure(location)
        } else {
            point1 = location
            point2 = nil
            distanceIn3D = nil
            onMeasure(location)
        }
    }
    
    private func midPoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
    
    private func distanceLabel(at point: CGPoint, distance: Float?) -> some View {
        VStack(spacing: 2) {
            if let dist = distance {
                Text(String(format: "%.2f m", dist))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            } else {
                Text("计算中...")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
        )
        .position(point)
    }
    
    func updateDistance(_ dist: Float?) {
        distanceIn3D = dist
        measuredDistance = dist
    }
    
    func reset() {
        point1 = nil
        point2 = nil
        distanceIn3D = nil
    }
}

struct LineBetweenPoints: View {
    let from: CGPoint
    let to: CGPoint
    
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.white), lineWidth: 2)
            
            let angle = atan2(to.y - from.y, to.x - from.x)
            let arrowLength: CGFloat = 10
            
            var arrowPath = Path()
            arrowPath.move(to: to)
            arrowPath.addLine(to: CGPoint(
                x: to.x - arrowLength * cos(angle - .pi / 6),
                y: to.y - arrowLength * sin(angle - .pi / 6)
            ))
            arrowPath.move(to: to)
            arrowPath.addLine(to: CGPoint(
                x: to.x - arrowLength * cos(angle + .pi / 6),
                y: to.y - arrowLength * sin(angle + .pi / 6)
            ))
            context.stroke(arrowPath, with: .color(.white), lineWidth: 2)
        }
    }
}

class PointCloudMeasurementController: NSObject, ObservableObject {
    weak var sceneView: SCNView?
    
    @Published var isActive = false
    @Published var measuredDistance: Float?
    
    private var point1World: SCNVector3?
    private var point2World: SCNVector3?
    private var markerNode1: SCNNode?
    private var markerNode2: SCNNode?
    private var lineNode: SCNNode?
    
    override init() {
        super.init()
    }
    
    func handleTap(at viewPoint: CGPoint) {
        guard isActive, let sceneView = sceneView else { return }
        
        let hitResults = sceneView.hitTest(viewPoint, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.boundingBoxOnly: false
        ])
        
        if let hit = hitResults.first(where: { $0.node.name == "pointCloud" || $0.node.parent?.name == "pointCloud" }) {
            let worldPos = hit.worldCoordinates
            
            if point1World == nil {
                point1World = worldPos
                addMarker(at: worldPos, isFirst: true)
            } else if point2World == nil {
                point2World = worldPos
                addMarker(at: worldPos, isFirst: false)
                calculateDistance()
            } else {
                clearMeasurements()
                point1World = worldPos
                addMarker(at: worldPos, isFirst: true)
            }
        }
    }
    
    private func addMarker(at position: SCNVector3, isFirst: Bool) {
        let sphere = SCNSphere(radius: 0.02)
        sphere.firstMaterial?.diffuse.contents = isFirst ? UIColor.red : UIColor.blue
        sphere.firstMaterial?.emission.contents = isFirst ? UIColor.red.withAlphaComponent(0.3) : UIColor.blue.withAlphaComponent(0.3)
        
        let marker = SCNNode(geometry: sphere)
        marker.position = position
        marker.name = isFirst ? "marker1" : "marker2"
        
        if isFirst {
            markerNode1?.removeFromParentNode()
            markerNode1 = marker
            sceneView?.scene?.rootNode.addChildNode(marker)
        } else {
            markerNode2?.removeFromParentNode()
            markerNode2 = marker
            sceneView?.scene?.rootNode.addChildNode(marker)
        }
    }
    
    private func calculateDistance() {
        guard let p1 = point1World, let p2 = point2World else { return }
        
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dz = p2.z - p1.z
        let distance = sqrt(dx*dx + dy*dy + dz*dz)
        
        measuredDistance = distance
        addLineBetween(p1, and: p2)
    }
    
    private func addLineBetween(_ p1: SCNVector3, and p2: SCNVector3) {
        lineNode?.removeFromParentNode()
        
        let vector = SCNVector3(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
        let distance = sqrt(vector.x*vector.x + vector.y*vector.y + vector.z*vector.z)
        
        let cylinder = SCNCylinder(radius: 0.005, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.white
        cylinder.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.3)
        
        let line = SCNNode(geometry: cylinder)
        line.name = "measureLine"
        
        let midpoint = SCNVector3((p1.x + p2.x) / 2, (p1.y + p2.y) / 2, (p1.z + p2.z) / 2)
        line.position = midpoint
        
        let up = SCNVector3(0, 1, 0)
        let cross = SCNVector3(
            up.y * vector.z - up.z * vector.y,
            up.z * vector.x - up.x * vector.z,
            up.x * vector.y - up.y * vector.x
        )
        let crossLength = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z)
        
        if crossLength > 0.001 {
            let dot = up.x * vector.x + up.y * vector.y + up.z * vector.z
            let angle = atan2(crossLength, dot)
            
            let axis = SCNVector3(cross.x / crossLength, cross.y / crossLength, cross.z / crossLength)
            line.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }
        
        lineNode = line
        sceneView?.scene?.rootNode.addChildNode(line)
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
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }
}

struct MeasurementToolbarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
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
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}
