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
    /// 视口尺寸变化会改变可视范围，需要重新取景。
    private var viewportSize: CGSize = .zero
    /// HUD 覆盖在视口上下：读数条与工具条会遮住点云，
    /// 取景必须把点云收进**没有遮挡**的那一段。
    var hudSafeInsets: UIEdgeInsets = .zero

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

    /// 视口尺寸变化后重新取景，避免窄屏把点云左右切掉。
    func viewportDidChange(to size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        applyCamera(animated: false)
    }

    /// HUD 遮挡范围变化后重新取景。
    func hudSafeInsetsDidChange(_ insets: UIEdgeInsets) {
        guard insets != hudSafeInsets else { return }
        hudSafeInsets = insets
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
        // 点云节点在建模时已经按包围盒中心平移过（见 SceneKitPointCloudNodeFactory），
        // 场景里的几何以原点为中心，因此相机看向原点就是看向点云中心。
        let target = SCNVector3(0, 0, 0)
        let distance = max(fittedDistance(for: size, radius: radius) * zoomScale, 0.7)

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

    // MARK: - 取景计算

    /// 相机竖直视场角（度）。必须与建场景时写入相机的值一致。
    private static let fieldOfViewDegrees: Float = 44

    /// 当前视口尺寸。
    private var currentViewportSize: CGSize {
        if viewportSize != .zero { return viewportSize }
        if let sceneView, sceneView.bounds.size != .zero { return sceneView.bounds.size }
        return CGSize(width: 402, height: 640)
    }

    /// 视口宽高比。
    private var viewportAspect: Float {
        let size = currentViewportSize
        guard size.height > 0 else { return 0.63 }
        return max(Float(size.width / size.height), 0.2)
    }

    /// HUD 遮挡之后**真正可用**的比例（上/下/左/右）。
    ///
    /// 上下留白通常不对称（顶部读数条与底部工具条高度不同），
    /// 而相机的投影中心固定在视口中心：按一侧的最大值取**对称**安全带，
    /// 点云才能既不压到 HUD、又不跑出视口。
    private func usableFractions() -> (height: Float, width: Float) {
        let size = currentViewportSize
        let top = size.height > 0 ? Float(hudSafeInsets.top) / Float(size.height) : 0
        let bottom = size.height > 0 ? Float(hudSafeInsets.bottom) / Float(size.height) : 0
        let left = size.width > 0 ? Float(hudSafeInsets.left) / Float(size.width) : 0
        let right = size.width > 0 ? Float(hudSafeInsets.right) / Float(size.width) : 0
        return (
            max(1 - max(top, bottom) * 2, 0.12),
            max(1 - max(left, right) * 2, 0.12)
        )
    }

    /// 有效半角正切：视口比例、FOV 与 HUD 留白共同决定。
    private func effectiveTangents() -> (vertical: Float, horizontal: Float) {
        let tanVertical = tan(Self.fieldOfViewDegrees * .pi / 360)
        let usable = usableFractions()
        return (
            max(tanVertical * usable.height, 0.01),
            max(tanVertical * viewportAspect * usable.width, 0.01)
        )
    }

    /// 解出"整盒入画"的最小相机距离。
    ///
    /// 只用 `max(size.x, size.z) / 2` 会漏掉两件事：
    ///   1. 轨道旋转之后，盒子在相机右轴上的投影比半宽更大；
    ///   2. 近端的角点离相机更近，能用的视锥更窄。
    /// 因此按相机的真实基向量，把 8 个角点逐个做视锥校验。
    private func fittedDistance(for size: SCNVector3, radius: Float) -> Float {
        let tangents = effectiveTangents()
        let basis = cameraBasis()
        let half = SCNVector3(size.x / 2, size.y / 2, size.z / 2)

        var distance: Float = 0
        for corner in Self.corners(half: half) {
            // 角点在相机基上的分量：along 指向相机（越大越近），其余为横/纵偏移。
            let along = Self.dot(corner, basis.forward)
            let lateral = abs(Self.dot(corner, basis.right))
            let vertical = abs(Self.dot(corner, basis.up))
            distance = max(distance, along + lateral / tangents.horizontal)
            distance = max(distance, along + vertical / tangents.vertical)
        }
        return max(distance * 1.06, radius * 0.9)
    }

    /// 相机基向量：forward 由相机指向目标，right/up 与之正交。
    private func cameraBasis() -> (forward: SCNVector3, right: SCNVector3, up: SCNVector3) {
        let direction: SCNVector3
        switch currentViewMode {
        case .orbit:
            let horizontal = cos(orbitPitch)
            direction = SCNVector3(
                sin(orbitYaw) * horizontal,
                sin(orbitPitch),
                cos(orbitYaw) * horizontal
            )
        case .front:
            direction = SCNVector3(0, 0, 1)
        case .top:
            direction = SCNVector3(0, 1, 0.001)
        case .side:
            direction = SCNVector3(1, 0, 0)
        }
        let forward = SCNVector3(-direction.x, -direction.y, -direction.z)
        let worldUp = SCNVector3(0, 1, 0)
        let right = Self.normalized(Self.cross(forward, worldUp))
        let up = Self.cross(right, forward)
        return (forward, right, up)
    }

    /// 正交取景的比例。
    ///
    /// `SCNCamera.projectionDirection` 默认是 `.vertical`：`orthographicScale`
    /// 定义的是**相机纵向**（高度方向）的可见范围，可见宽度 = scale × 视口宽高比。
    /// 因此竖屏时宽度往往是约束（宽度 = scale × aspect 很小），横屏时高度是约束。
    /// HUD 遮住上下之后，可用高度还要再除一次可用比例。
    private func orthographicScale(for mode: PointCloudViewMode, size: SCNVector3) -> Float {
        let projected: (width: Float, height: Float)
        switch mode {
        case .orbit:
            projected = (max(size.x, size.z), size.y)
        case .front:
            projected = (size.x, size.y)
        case .top:
            projected = (size.x, size.z)
        case .side:
            projected = (size.z, size.y)
        }
        let aspect = viewportAspect
        let scale = max(projected.height, projected.width / max(aspect, 0.01))
        return scale * 1.08 / usableFractions().height
    }

    // MARK: - 向量工具

    private static func corners(half: SCNVector3) -> [SCNVector3] {
        var result: [SCNVector3] = []
        for x in [-half.x, half.x] {
            for y in [-half.y, half.y] {
                for z in [-half.z, half.z] {
                    result.append(SCNVector3(x, y, z))
                }
            }
        }
        return result
    }

    private static func dot(_ lhs: SCNVector3, _ rhs: SCNVector3) -> Float {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private static func cross(_ lhs: SCNVector3, _ rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    private static func normalized(_ vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0.0001 else { return SCNVector3(1, 0, 0) }
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }

    private func resetOrbitAngles() {
        orbitYaw = defaultOrbitYaw
        orbitPitch = defaultOrbitPitch
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
        // 视口尺寸确定后再取景一次：初装载时宽度可能还是 0。
        cameraCoordinator.viewportDidChange(to: uiView.bounds.size)
        if context.coordinator.loadedContentID != contentID {
            reloadPointCloud(in: uiView, context: context)
        }
        if context.coordinator.appliedViewMode != viewMode {
            cameraCoordinator.setViewMode(viewMode)
            context.coordinator.appliedViewMode = viewMode
        }
        guard context.coordinator.appliedColorMode != colorMode else { return }
        guard let pointCloudData,
              let pointCloudNode = uiView.scene?.rootNode.childNode(withName: "pointCloud", recursively: true),
              SceneKitPointCloudColorRenderer.apply(
                  colorMode: colorMode,
                  to: pointCloudNode,
                  sourceVertices: pointCloudData.vertices,
                  sourceColors: pointCloudData.colors
              )
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
            createPLYPointCloud(
                vertices: pointCloudData.vertices,
                colors: pointCloudData.colors,
                bounds: pointCloudData.bounds,
                in: scene
            )
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

    private func createPLYPointCloud(
        vertices: [SCNVector3],
        colors: [PointCloudColor],
        bounds: PointCloudBounds?,
        in scene: SCNScene
    ) {
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
