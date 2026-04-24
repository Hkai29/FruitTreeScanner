// PointCloudView.swift
// 3D Point Cloud Visualization using SceneKit

import SwiftUI
import SceneKit

// MARK: - Point Cloud Color Mode
enum PointCloudColorMode: String, CaseIterable {
    case height = "高度"
    case density = "密度"
    case fruit = "果实"
    case uniform = "统一"

    var icon: String {
        switch self {
        case .height: return "arrow.up.arrow.down"
        case .density: return "circle.grid.3x3"
        case .fruit: return "leaf.fill"
        case .uniform: return "paintpalette"
        }
    }
}

// MARK: - PointCloudView
struct PointCloudView: View {
    let plyFileURL: URL?

    @State private var pointCount: Int = 0
    @State private var colorMode: PointCloudColorMode = .height
    @State private var showExportSheet = false
    @State private var isLoading = true
    @StateObject private var cameraCoordinator = SceneKitPointCloudViewCoordinator()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // SceneKit Point Cloud
            SceneKitPointCloudView(
                plyFileURL: plyFileURL,
                colorMode: colorMode,
                pointCount: $pointCount,
                isLoading: $isLoading,
                cameraCoordinator: cameraCoordinator
            )
            .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top Bar
                topBar

                Spacer()

                // Bottom Controls
                bottomControls
            }
            .padding(Design.Space.lg)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: Design.Space.md) {
            // 占位，保持标题居中
            Spacer().frame(width: 36)

            Spacer()

            // Title
            Text("点云预览")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(.white)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, Design.Space.sm)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

            Spacer()

            // Export Button
            Button {
                showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: Design.Space.lg) {
            // Point Count Badge
            HStack {
                Spacer()

                VStack(spacing: Design.Space.xs) {
                    Text("\(pointCount.formatted())")
                        .font(Design.Typography.title2)
                        .foregroundColor(.white)

                    Text("点云点数")
                        .font(Design.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(Design.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.large)
                        .fill(.ultraThinMaterial)
                )
            }

            // Control Toolbar
            HStack(spacing: Design.Space.md) {
                // Reset View
                ControlButton(icon: "arrow.uturn.backward", label: "重置") {
                    cameraCoordinator.resetCamera()
                }

                // Color Mode
                Menu {
                    ForEach(PointCloudColorMode.allCases, id: \.self) { mode in
                        Button {
                            colorMode = mode
                        } label: {
                            HStack {
                                Image(systemName: mode.icon)
                                Text(mode.rawValue)
                                if mode == colorMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    VStack(spacing: Design.Space.xs) {
                        ZStack {
                            Circle()
                                .fill(Design.Colors.forest)
                                .frame(width: 28, height: 28)
                            Image(systemName: colorMode.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("色彩")
                            .font(Design.Typography.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 60, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .fill(.ultraThinMaterial)
                    )
                }

                // Zoom In
                ControlButton(icon: "plus.viewfinder", label: "放大") {
                    cameraCoordinator.zoomIn()
                }

                // Zoom Out
                ControlButton(icon: "minus.viewfinder", label: "缩小") {
                    cameraCoordinator.zoomOut()
                }
            }

            // Color Legend
            colorLegend
        }
    }

    // MARK: - Color Legend
    private var colorLegend: some View {
        HStack(spacing: Design.Space.lg) {
            Text("色彩模式: \(colorMode.rawValue)")
                .font(Design.Typography.caption)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            // Legend items based on color mode
            switch colorMode {
            case .height:
                HStack(spacing: Design.Space.xs) {
                    Rectangle().fill(Design.Colors.forest).frame(width: 16, height: 8).cornerRadius(2)
                    Text("低").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.5))
                    Rectangle().fill(Design.Colors.harvest).frame(width: 16, height: 8).cornerRadius(2)
                    Text("高").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                }

            case .density:
                HStack(spacing: Design.Space.xs) {
                    Rectangle().fill(Color(hex: "8E8E93").opacity(0.3)).frame(width: 16, height: 8).cornerRadius(2)
                    Text("稀疏").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.5))
                    Rectangle().fill(Design.Colors.slate).frame(width: 16, height: 8).cornerRadius(2)
                    Text("密集").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                }

            case .fruit:
                HStack(spacing: Design.Space.xs) {
                    Circle().fill(Design.Colors.harvest).frame(width: 8, height: 8)
                    Text("果实").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                }

            case .uniform:
                HStack(spacing: Design.Space.xs) {
                    Circle().fill(Design.Colors.forest).frame(width: 8, height: 8)
                    Text("统一").font(Design.Typography.caption).foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Control Button
struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Design.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))

                Text(label)
                    .font(Design.Typography.caption)
            }
            .foregroundColor(.white)
            .frame(width: 60, height: 56)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - SceneKit Camera Controller
class PointCloudCameraController: NSObject, ObservableObject {
    weak var sceneView: SCNView?

    func resetCamera() {
        guard let sceneView = sceneView else { return }
        // Animate camera back to default position
        if let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
            cameraNode.eulerAngles = SCNVector3(0, 0, 0)
            SCNTransaction.commit()
        }
    }

    func zoomIn() {
        guard let sceneView = sceneView else { return }
        if let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) {
            let currentZ = cameraNode.position.z
            let newZ = max(currentZ * 0.7, 0.5)  // Zoom in by reducing distance
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            cameraNode.position.z = newZ
            SCNTransaction.commit()
        }
    }

    func zoomOut() {
        guard let sceneView = sceneView else { return }
        if let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) {
            let currentZ = cameraNode.position.z
            let newZ = min(currentZ * 1.3, 20)  // Zoom out by increasing distance
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            cameraNode.position.z = newZ
            SCNTransaction.commit()
        }
    }
}

// MARK: - PLY Parser
struct PLYPoint {
    let x: Float, y: Float, z: Float
    let r: UInt8, g: UInt8, b: UInt8
}

func parsePLY(url: URL) -> (vertices: [SCNVector3], colors: [UIColor], pointCount: Int)? {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

    let lines = content.split(separator: "\n")
    var vertexCount = 0
    var formatASCII = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("element vertex") {
            let parts = trimmed.split(separator: " ")
            if parts.count >= 3, let count = Int(parts[2]) {
                vertexCount = count
            }
        } else if trimmed == "format ascii 1.0" || trimmed.hasPrefix("format ascii") {
            formatASCII = true
        } else if trimmed == "end_header" {
            break
        }
    }

    guard vertexCount > 0, formatASCII else { return nil }

    // Find start of vertex data (after end_header line)
    var vertexStartIndex = 0
    for (index, line) in lines.enumerated() {
        if line.trimmingCharacters(in: .whitespaces) == "end_header" {
            vertexStartIndex = index + 1
            break
        }
    }

    var vertices: [SCNVector3] = []
    var colors: [UIColor] = []

    for i in vertexStartIndex..<lines.count {
        let values = lines[i].split(separator: " ")
        guard values.count >= 6 else { continue }

        guard let x = Float(values[0]), let y = Float(values[1]), let z = Float(values[2]),
              let r = UInt8(values[3]), let g = UInt8(values[4]), let b = UInt8(values[5]) else {
            continue
        }

        vertices.append(SCNVector3(x, y, z))
        // Clamp RGB values to valid 0-255 range to avoid UIColor out-of-range warning
        colors.append(UIColor(
            red: CGFloat(min(max(r, 0), 255)) / 255.0,
            green: CGFloat(min(max(g, 0), 255)) / 255.0,
            blue: CGFloat(min(max(b, 0), 255)) / 255.0,
            alpha: 1.0
        ))
    }

    return (vertices, colors, vertices.count)
}

// MARK: - SceneKit Camera Coordinator
class SceneKitPointCloudViewCoordinator: NSObject, ObservableObject {
    weak var sceneView: SCNView?

    func resetCamera() {
        guard let sceneView = sceneView,
              let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        SCNTransaction.commit()
    }

    func zoomIn() {
        guard let sceneView = sceneView,
              let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) else { return }
        let currentZ = cameraNode.position.z
        let newZ = max(currentZ * 0.7, 0.5)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        cameraNode.position.z = newZ
        SCNTransaction.commit()
    }

    func zoomOut() {
        guard let sceneView = sceneView,
              let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) else { return }
        let currentZ = cameraNode.position.z
        let newZ = min(currentZ * 1.3, 20)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        cameraNode.position.z = newZ
        SCNTransaction.commit()
    }
}

// MARK: - SceneKit Point Cloud View
struct SceneKitPointCloudView: UIViewRepresentable {
    let plyFileURL: URL?
    let colorMode: PointCloudColorMode
    @Binding var pointCount: Int
    @Binding var isLoading: Bool
    @ObservedObject var cameraCoordinator: SceneKitPointCloudViewCoordinator

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor(Color(hex: "1C1C1E"))
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.pointOfView?.name = "camera"

        let scene = SCNScene()
        sceneView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        if let url = plyFileURL, let parsed = parsePLY(url: url) {
            createPLYPointCloud(vertices: parsed.vertices, colors: parsed.colors, in: scene)
            pointCount = parsed.pointCount
        } else {
            createDemoPointCloud(in: scene)
        }

        // Store reference for camera control
        DispatchQueue.main.async {
            self.cameraCoordinator.sceneView = sceneView
        }

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func createPLYPointCloud(vertices: [SCNVector3], colors: [UIColor], in scene: SCNScene) {
        // Center the point cloud
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for v in vertices {
            minX = min(minX, v.x); maxX = max(maxX, v.x)
            minY = min(minY, v.y); maxY = max(maxY, v.y)
            minZ = min(minZ, v.z); maxZ = max(maxZ, v.z)
        }
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2

        for (index, vertex) in vertices.enumerated() {
            let sphere = SCNSphere(radius: 0.006)
            sphere.segmentCount = 6

            let material = SCNMaterial()
            material.diffuse.contents = index < colors.count ? colors[index] : UIColor(Design.Colors.slate)
            material.lightingModel = .constant
            sphere.materials = [material]

            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(vertex.x - centerX, vertex.y - centerY, vertex.z - centerZ)
            scene.rootNode.addChildNode(node)
        }
    }

    private func createDemoPointCloud(in scene: SCNScene) {
        // Create demo points forming a tree-like shape
        var points: [SCNVector3] = []
        var colors: [UIColor] = []

        // Trunk (brownish points)
        for _ in 0..<500 {
            let x = Float.random(in: -0.1...0.1)
            let y = Float.random(in: -1...0)
            let z = Float.random(in: -0.1...0.1)
            points.append(SCNVector3(x, y, z))
            colors.append(UIColor.brown.withAlphaComponent(0.8))
        }

        // Crown (green points with height variation)
        for _ in 0..<2000 {
            let radius = Float.random(in: 0...0.8)
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = Float.random(in: 0...(1 * .pi))

            let x = radius * sin(phi) * cos(theta)
            let y = Float.random(in: 0...2) + radius * cos(phi) * 0.5
            let z = radius * sin(phi) * sin(theta)

            points.append(SCNVector3(x, y, z))

            // Color by height
            let heightRatio = y / 2.5
            if heightRatio > 0.7 {
                colors.append(UIColor(Design.Colors.forest))
            } else if heightRatio > 0.4 {
                colors.append(UIColor(Design.Colors.earth))
            } else {
                colors.append(UIColor(Design.Colors.earthLight))
            }
        }

        // Create point geometry using small spheres
        for (index, point) in points.enumerated() {
            let sphere = SCNSphere(radius: 0.008)
            sphere.segmentCount = 6 // Low poly for performance

            let material = SCNMaterial()
            material.diffuse.contents = colors[index]
            material.lightingModel = .constant
            sphere.materials = [material]

            let node = SCNNode(geometry: sphere)
            node.position = point
            scene.rootNode.addChildNode(node)
        }

        pointCount = points.count
    }
}

#Preview {
    PointCloudView(plyFileURL: nil)
}
