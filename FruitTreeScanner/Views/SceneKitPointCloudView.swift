import SceneKit
import SwiftUI

// MARK: - SceneKit Camera Coordinator
class SceneKitPointCloudViewCoordinator: NSObject, ObservableObject {
    weak var sceneView: SCNView?
    private var bounds: PointCloudBounds?
    private var currentViewMode: PointCloudViewMode = .orbit
    private var zoomScale: Float = 1
    private var orbitYaw: Float = 0.62
    private var orbitPitch: Float = 0.36
    private let defaultOrbitYaw: Float = 0.62
    private let defaultOrbitPitch: Float = 0.36

    func resetCamera() {
        zoomScale = 1
        resetOrbitAngles()
        applyCamera(animated: true)
    }

    func setBounds(_ bounds: PointCloudBounds?) {
        self.bounds = bounds
        zoomScale = 1
        applyCamera(animated: false)
    }

    func setViewMode(_ viewMode: PointCloudViewMode) {
        currentViewMode = viewMode
        zoomScale = 1
        if viewMode == .orbit {
            resetOrbitAngles()
        }
        applyCamera(animated: true)
    }

    func zoomIn() {
        zoomScale = max(zoomScale * 0.72, 0.22)
        applyCamera(animated: true)
    }

    func zoomOut() {
        zoomScale = min(zoomScale * 1.32, 4.5)
        applyCamera(animated: true)
    }

    func adjustZoom(by magnification: CGFloat) {
        guard magnification.isFinite, magnification > 0 else { return }
        zoomScale = min(max(zoomScale / Float(magnification), 0.22), 4.5)
        applyCamera(animated: false)
    }

    func rotateOrbit(delta: CGPoint) {
        guard currentViewMode == .orbit else { return }
        orbitYaw -= Float(delta.x) * 0.006
        orbitPitch = min(max(orbitPitch + Float(delta.y) * 0.006, -1.05), 1.05)
        applyCamera(animated: false)
    }

    private func applyCamera(animated: Bool) {
        guard let sceneView = sceneView,
              let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) else { return }
        let pointBounds = bounds
        let radius = max(pointBounds?.radius ?? 1.6, 0.35)
        let size = pointBounds?.size ?? SCNVector3(1.8, 1.8, 1.8)
        let distance = max(radius * 2.45 * zoomScale, 0.7)
        let target = SCNVector3(0, 0, 0)

        let position: SCNVector3
        switch currentViewMode {
        case .orbit:
            let horizontal = cos(orbitPitch)
            position = SCNVector3(
                distance * sin(orbitYaw) * horizontal,
                distance * sin(orbitPitch),
                distance * cos(orbitYaw) * horizontal
            )
        case .front:
            position = SCNVector3(0, 0, distance)
        case .top:
            position = SCNVector3(0, distance, 0.001)
        case .side:
            position = SCNVector3(distance, 0, 0)
        }

        let orthographicScale = orthographicScale(for: currentViewMode, size: size) * zoomScale
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.28 : 0
        cameraNode.camera?.usesOrthographicProjection = currentViewMode.usesOrthographicCamera
        cameraNode.camera?.orthographicScale = Double(max(orthographicScale, 0.4))
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = Double(max(distance * 8, 20))
        cameraNode.position = position
        cameraNode.look(at: target)
        SCNTransaction.commit()
    }

    private func resetOrbitAngles() {
        orbitYaw = defaultOrbitYaw
        orbitPitch = defaultOrbitPitch
    }

    private func orthographicScale(for mode: PointCloudViewMode, size: SCNVector3) -> Float {
        switch mode {
        case .orbit:
            return max(max(size.x, size.y), size.z) * 1.08
        case .front:
            return max(size.y, size.x) * 1.08
        case .top:
            return max(size.x, size.z) * 1.08
        case .side:
            return max(size.y, size.z) * 1.08
        }
    }
}

// MARK: - SceneKit Point Cloud View
struct SceneKitPointCloudView: UIViewRepresentable {
    let plyFileURL: URL?
    let pointCloudData: PointCloudData?
    let colorMode: PointCloudColorMode
    let viewMode: PointCloudViewMode
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
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false
        sceneView.isUserInteractionEnabled = true

        let scene = SCNScene()
        sceneView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 44
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        cameraCoordinator.sceneView = sceneView
        measurementController?.sceneView = sceneView
        context.coordinator.attachGestures(to: sceneView)
        reloadPointCloud(in: sceneView, context: context)

        return sceneView
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SceneKitPointCloudView
        var loadedContentID: String?
        var appliedColorMode: PointCloudColorMode?
        var appliedViewMode: PointCloudViewMode?

        init(_ parent: SceneKitPointCloudView) {
            self.parent = parent
        }

        func attachGestures(to sceneView: SCNView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            sceneView.addGestureRecognizer(tap)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            sceneView.addGestureRecognizer(pinch)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            sceneView.addGestureRecognizer(pan)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.measurementController?.handleTap(at: location)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            parent.cameraCoordinator.adjustZoom(by: gesture.scale)
            gesture.scale = 1
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            let translation = gesture.translation(in: gesture.view)
            parent.cameraCoordinator.rotateOrbit(delta: translation)
            gesture.setTranslation(.zero, in: gesture.view)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        cameraCoordinator.sceneView = uiView
        measurementController?.sceneView = uiView
        if context.coordinator.loadedContentID != contentID {
            reloadPointCloud(in: uiView, context: context)
        }
        if context.coordinator.appliedViewMode != viewMode {
            cameraCoordinator.setViewMode(viewMode)
            context.coordinator.appliedViewMode = viewMode
        }
        guard context.coordinator.appliedColorMode != colorMode else { return }
        guard let pointCloudNode = uiView.scene?.rootNode.childNode(withName: "pointCloud", recursively: true),
              SceneKitPointCloudColorRenderer.apply(colorMode: colorMode, to: pointCloudNode)
        else { return }
        context.coordinator.appliedColorMode = colorMode
    }

    private func reloadPointCloud(in sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }
        scene.rootNode.childNode(withName: "pointCloud", recursively: true)?.removeFromParentNode()
        scene.rootNode.childNode(withName: "pointCloudReference", recursively: true)?.removeFromParentNode()

        let loadedCount: Int
        let hasFinishedLoading: Bool
        if let pointCloudData {
            createPLYPointCloud(vertices: pointCloudData.vertices, colors: pointCloudData.colors, in: scene)
            loadedCount = pointCloudData.pointCount
            hasFinishedLoading = true
        } else {
            loadedCount = 0
            hasFinishedLoading = false
            cameraCoordinator.setBounds(nil)
        }

        context.coordinator.loadedContentID = contentID
        context.coordinator.appliedColorMode = nil
        context.coordinator.appliedViewMode = viewMode
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
        let bounds = SceneKitPointCloudGeometry.bounds(for: vertices)
        guard let node = SceneKitPointCloudGeometry.makePointCloudNode(
            vertices: vertices,
            colors: colors,
            pointSize: 6,
            bounds: bounds
        ) else { return }
        if let bounds {
            scene.rootNode.addChildNode(SceneKitPointCloudGeometry.makeReferenceNode(bounds: bounds))
        }
        scene.rootNode.addChildNode(node)
        cameraCoordinator.setBounds(bounds)
        cameraCoordinator.setViewMode(viewMode)
    }
}
