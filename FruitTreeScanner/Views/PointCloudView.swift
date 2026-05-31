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
    @State private var pointCloudData: PointCloudData?
    @State private var loadErrorMessage: String?
    @StateObject private var cameraCoordinator = SceneKitPointCloudViewCoordinator()
    @StateObject private var measurementController = PointCloudMeasurementController()
    @State private var showMeasurement = false
    @State private var measuredDistance: Float?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // SceneKit Point Cloud
            SceneKitPointCloudView(
                plyFileURL: plyFileURL,
                pointCloudData: pointCloudData,
                colorMode: colorMode,
                pointCount: $pointCount,
                isLoading: $isLoading,
                cameraCoordinator: cameraCoordinator,
                measurementController: measurementController
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(Design.Space.md)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            } else if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(Design.Typography.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            // Measurement Tool Overlay
            if showMeasurement {
                MeasurementToolOverlay(
                    controller: measurementController,
                    measuredDistance: $measuredDistance,
                    onClose: stopMeasurement
                )
            }

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
        .task(id: plyFileURL) {
            stopMeasurement()
            await loadPointCloud()
        }
        .sheet(isPresented: $showExportSheet) {
            if let plyFileURL {
                ShareSheet(items: [plyFileURL])
            }
        }
    }

    private var canExportCurrentFile: Bool {
        plyFileURL != nil && !isLoading
    }

    @MainActor
    private func loadPointCloud() async {
        guard let plyFileURL else {
            pointCloudData = nil
            pointCount = 0
            loadErrorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        loadErrorMessage = nil
        let loadedData = await Task.detached(priority: .userInitiated) {
            parsePLY(url: plyFileURL)
        }.value
        guard !Task.isCancelled else { return }
        pointCloudData = loadedData
        pointCount = loadedData?.pointCount ?? 0
        loadErrorMessage = loadedData == nil ? "无法读取点云文件" : nil
        isLoading = false
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
            .disabled(!canExportCurrentFile)
            .opacity(canExportCurrentFile ? 1 : 0.45)
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

                // Measurement Tool
                MeasurementToolbarButton(
                    icon: "ruler",
                    label: "测量",
                    isActive: showMeasurement
                ) {
                    toggleMeasurement()
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

    private func toggleMeasurement() {
        if measurementController.isActive {
            stopMeasurement()
        } else {
            measurementController.activate()
            showMeasurement = true
            measuredDistance = nil
        }
    }

    private func stopMeasurement() {
        measurementController.deactivate()
        showMeasurement = false
        measuredDistance = nil
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

// MARK: - PLY Parser
struct PointCloudColor: Sendable {
    let r: Float
    let g: Float
    let b: Float
    let a: Float
}

struct PointCloudData: @unchecked Sendable {
    let id: String
    let vertices: [SCNVector3]
    let colors: [PointCloudColor]

    var pointCount: Int { vertices.count }
}

func parsePLY(url: URL) -> PointCloudData? {
    guard let data = try? Data(contentsOf: url) else { return nil }

    guard let headerEndRange = data.range(of: Data("end_header\n".utf8)) ?? data.range(of: Data("end_header\r\n".utf8)) else { return nil }

    let headerData = data[data.startIndex..<headerEndRange.lowerBound]
    guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

    let headerLines = headerStr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

    var vertexCount = 0
    var isBinary = false
    var isBigEndian = false
    var hasColor = false

    for line in headerLines {
        if line.hasPrefix("element vertex") {
            let parts = line.split(separator: " ")
            if parts.count >= 3, let count = Int(parts[2]) {
                vertexCount = count
            }
        } else if line.hasPrefix("format ascii") {
            isBinary = false
        } else if line.hasPrefix("format binary_little_endian") {
            isBinary = true
            isBigEndian = false
        } else if line.hasPrefix("format binary_big_endian") {
            isBinary = true
            isBigEndian = true
        } else if line.hasPrefix("property uchar red") || line.hasPrefix("property uchar r") {
            hasColor = true
        }
    }

    guard vertexCount > 0 else { return nil }

    let bodyStart = headerEndRange.upperBound

    if !isBinary {
        return parsePLYASCII(data: data, bodyStart: bodyStart, vertexCount: vertexCount, sourceURL: url)
    } else {
        return parsePLYBinary(data: data, bodyStart: bodyStart, vertexCount: vertexCount, bigEndian: isBigEndian, hasColor: hasColor, sourceURL: url)
    }
}

private func parsePLYASCII(data: Data, bodyStart: Int, vertexCount: Int, sourceURL: URL) -> PointCloudData? {
    guard let content = String(data: data[bodyStart...], encoding: .utf8) else { return nil }
    let lines = content.split(separator: "\n")

    var vertices: [SCNVector3] = []
    var colors: [PointCloudColor] = []
    vertices.reserveCapacity(min(vertexCount, 500000))
    colors.reserveCapacity(min(vertexCount, 500000))

    for line in lines {
        let values = line.split(separator: " ")
        guard values.count >= 6,
              let x = Float(values[0]), let y = Float(values[1]), let z = Float(values[2]),
              let r = UInt8(values[3]), let g = UInt8(values[4]), let b = UInt8(values[5]) else {
            continue
        }
        vertices.append(SCNVector3(x, y, z))
        colors.append(PointCloudColor(
            r: Float(r) / 255.0,
            g: Float(g) / 255.0,
            b: Float(b) / 255.0,
            a: 1.0
        ))
        if vertices.count >= vertexCount { break }
    }

    guard !vertices.isEmpty else { return nil }
    return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
}

private func parsePLYBinary(data: Data, bodyStart: Int, vertexCount: Int, bigEndian: Bool, hasColor: Bool, sourceURL: URL) -> PointCloudData? {
    let stride = hasColor ? 15 : 12
    let expectedSize = bodyStart + vertexCount * stride
    guard data.count >= expectedSize else { return nil }

    var vertices: [SCNVector3] = []
    var colors: [PointCloudColor] = []
    let maxPoints = min(vertexCount, 500000)
    vertices.reserveCapacity(maxPoints)
    colors.reserveCapacity(maxPoints)

    data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
        guard let basePtr = rawPtr.baseAddress else { return }
        let bodyPtr = basePtr.advanced(by: bodyStart)

        for i in 0..<vertexCount {
            if vertices.count >= maxPoints { break }
            let offset = i * stride
            let pointPtr = bodyPtr.advanced(by: offset)

            let rawX = pointPtr.assumingMemoryBound(to: UInt32.self).pointee
            let rawY = pointPtr.advanced(by: 4).assumingMemoryBound(to: UInt32.self).pointee
            let rawZ = pointPtr.advanced(by: 8).assumingMemoryBound(to: UInt32.self).pointee

            let fx = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawX) : UInt32(littleEndian: rawX))
            let fy = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawY) : UInt32(littleEndian: rawY))
            let fz = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawZ) : UInt32(littleEndian: rawZ))

            vertices.append(SCNVector3(fx, fy, fz))

            if hasColor {
                let r = pointPtr.advanced(by: 12).assumingMemoryBound(to: UInt8.self).pointee
                let g = pointPtr.advanced(by: 13).assumingMemoryBound(to: UInt8.self).pointee
                let b = pointPtr.advanced(by: 14).assumingMemoryBound(to: UInt8.self).pointee
                colors.append(PointCloudColor(
                    r: Float(r) / 255.0,
                    g: Float(g) / 255.0,
                    b: Float(b) / 255.0,
                    a: 1.0
                ))
            } else {
                colors.append(PointCloudColor(r: 0.5, g: 0.5, b: 0.5, a: 1.0))
            }
        }
    }

    guard !vertices.isEmpty else { return nil }
    return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
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
    let pointCloudData: PointCloudData?
    let colorMode: PointCloudColorMode
    @Binding var pointCount: Int
    @Binding var isLoading: Bool
    @ObservedObject var cameraCoordinator: SceneKitPointCloudViewCoordinator
    var measurementController: PointCloudMeasurementController?

    private var contentID: String {
        if let pointCloudData {
            return pointCloudData.id
        }
        return "empty:\(plyFileURL?.path ?? "none")"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor(Color(hex: "1C1C1E"))
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.pointOfView?.name = "camera"

        sceneView.addGestureRecognizer(
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        )

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

        reloadPointCloud(in: sceneView, context: context)

        // Store reference for camera control
        cameraCoordinator.sceneView = sceneView
        measurementController?.sceneView = sceneView

        return sceneView
    }

    class Coordinator: NSObject {
        var parent: SceneKitPointCloudView
        var loadedContentID: String?
        var appliedColorMode: PointCloudColorMode?

        init(_ parent: SceneKitPointCloudView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.measurementController?.handleTap(at: location)
        }
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedContentID != contentID {
            reloadPointCloud(in: uiView, context: context)
        }
        guard context.coordinator.appliedColorMode != colorMode else { return }
        guard let pointCloudNode = uiView.scene?.rootNode.childNode(withName: "pointCloud", recursively: true),
              let geometry = pointCloudNode.geometry,
              let colorSource = geometry.sources(for: .color).first else { return }

        let vertexCount = colorSource.vectorCount
        let colorData = colorSource.data
        var newColorData = [Float]()
        newColorData.reserveCapacity(vertexCount * 4)

        let posSource = geometry.sources(for: .vertex).first
        var positions: [SCNVector3] = []
        if let ps = posSource {
            positions = ps.data.withUnsafeBytes { ptr -> [SCNVector3] in
                let buffer = ptr.bindMemory(to: Float.self)
                var result: [SCNVector3] = []
                result.reserveCapacity(vertexCount)
                for i in 0..<vertexCount {
                    let idx = i * 3
                    if idx + 2 < buffer.count {
                        result.append(SCNVector3(buffer[idx], buffer[idx+1], buffer[idx+2]))
                    }
                }
                return result
            }
        }

        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        for p in positions {
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        let yRange = max(maxY - minY, 0.001)

        colorData.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Float.self)
            for i in 0..<vertexCount {
                let baseIdx = i * 4
                guard baseIdx + 3 < buffer.count else { continue }
                let origR = buffer[baseIdx]
                let origG = buffer[baseIdx + 1]
                let origB = buffer[baseIdx + 2]

                let newR: Float, newG: Float, newB: Float

                switch colorMode {
                case .height:
                    let t = i < positions.count ? (positions[i].y - minY) / yRange : 0.5
                    newR = t
                    newG = 0.6 * (1 - abs(t - 0.5) * 2)
                    newB = 1 - t
                case .density:
                    let brightness = (origR + origG + origB) / 3
                    newR = brightness * 0.4
                    newG = brightness * 0.6
                    newB = brightness * 0.8
                case .fruit:
                    let isFruitLike = origR > 0.4 && origG < 0.5
                    newR = isFruitLike ? 1.0 : origR * 0.3
                    newG = isFruitLike ? 0.58 : origG * 0.3
                    newB = isFruitLike ? 0.0 : origB * 0.3
                case .uniform:
                    newR = 0.2
                    newG = 0.7
                    newB = 0.3
                }

                newColorData.append(newR)
                newColorData.append(newG)
                newColorData.append(newB)
                newColorData.append(1.0)
            }
        }

        guard newColorData.count == vertexCount * 4 else { return }

        let newSource = SCNGeometrySource(data: Data(bytes: newColorData, count: newColorData.count * 4),
                                           semantic: .color,
                                           vectorCount: vertexCount,
                                           usesFloatComponents: true,
                                           componentsPerVector: 4,
                                           bytesPerComponent: 4,
                                           dataOffset: 0,
                                           dataStride: 16)

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
        context.coordinator.appliedColorMode = colorMode
    }

    private func reloadPointCloud(in sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }
        scene.rootNode.childNode(withName: "pointCloud", recursively: true)?.removeFromParentNode()

        let loadedCount: Int
        let hasFinishedLoading: Bool
        if let pointCloudData {
            createPLYPointCloud(vertices: pointCloudData.vertices, colors: pointCloudData.colors, in: scene)
            loadedCount = pointCloudData.pointCount
            hasFinishedLoading = true
        } else {
            loadedCount = 0
            hasFinishedLoading = false
        }

        context.coordinator.loadedContentID = contentID
        context.coordinator.appliedColorMode = nil
        publishLoadedCount(loadedCount, finishedLoading: hasFinishedLoading)
    }

    private func publishLoadedCount(_ count: Int, finishedLoading: Bool) {
        DispatchQueue.main.async {
            if pointCount != count {
                pointCount = count
            }
            if finishedLoading, isLoading {
                isLoading = false
            }
        }
    }

    private func createPLYPointCloud(vertices: [SCNVector3], colors: [PointCloudColor], in scene: SCNScene) {
        guard !vertices.isEmpty else { return }

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

        let positions = vertices.map { SCNVector3($0.x - centerX, $0.y - centerY, $0.z - centerZ) }
        let node = makePointNode(positions: positions, colors: colors, pointSize: 4)
        scene.rootNode.addChildNode(node)
    }

    private func makePointNode(positions: [SCNVector3], colors: [PointCloudColor], pointSize: CGFloat) -> SCNNode {
        var vertexData = [Float]()
        vertexData.reserveCapacity(positions.count * 3)
        for p in positions {
            vertexData.append(p.x)
            vertexData.append(p.y)
            vertexData.append(p.z)
        }
        let source = SCNGeometrySource(data: Data(bytes: vertexData, count: vertexData.count * 4),
                                       semantic: .vertex,
                                       vectorCount: positions.count,
                                       usesFloatComponents: true,
                                       componentsPerVector: 3,
                                       bytesPerComponent: 4,
                                       dataOffset: 0,
                                       dataStride: 12)

        var colorData = [Float]()
        colorData.reserveCapacity(positions.count * 4)
        for i in 0..<positions.count {
            if i < colors.count {
                let color = colors[i]
                colorData.append(color.r)
                colorData.append(color.g)
                colorData.append(color.b)
                colorData.append(color.a)
            } else {
                colorData.append(0.5)
                colorData.append(0.5)
                colorData.append(0.5)
                colorData.append(1.0)
            }
        }
        let colorSource = SCNGeometrySource(data: Data(bytes: colorData, count: colorData.count * 4),
                                            semantic: .color,
                                            vectorCount: positions.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: 4,
                                            dataOffset: 0,
                                            dataStride: 16)

        let indices = (0..<positions.count).map { Int32($0) }
        let indexData = Data(bytes: indices, count: indices.count * 4)
        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .point,
                                         primitiveCount: positions.count,
                                         bytesPerIndex: 4)

        let geometry = SCNGeometry(sources: [source, colorSource], elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "pointCloud"

        geometry.setValue(pointSize, forKey: "pointSize")
        geometry.setValue(1, forKey: "pointSizeMode")

        return node
    }
}

#Preview {
    PointCloudView(plyFileURL: nil)
}
