// PointCloudFramingTests.swift
// 点云取景的几何验收：初始视角必须把整团点云收进**没有被 HUD 遮住**的那块画面。
//
// 这里不复述拟合公式，而是做真实投影：
//   1. 构造一个**原始中心不在原点**的包围盒（真实 PLY 的坐标不会以原点为中心）；
//   2. 走生产链路的同一个节点工厂（节点会按包围盒中心平移）；
//   3. 用 SCNView.projectPoint 把平移后的 8 个角点投到屏幕上；
//   4. 逐点断言它们落在视口内、且避开了 HUD 的上下留白。
//
// 任何一次取景公式写错（视口比例、FOV、旋转包围、HUD 留白、正交比例），
// 都会在这里表现为某个角点被裁掉。

import SceneKit
import XCTest
@testable import FruitTreeScanner

@MainActor
final class PointCloudFramingTests: XCTestCase {
    /// 原始中心刻意偏离原点：点云节点按包围盒中心平移过，
    /// 相机必须看向**平移后**的原点，否则会出现二次偏移。
    private static let rawCenter = SCNVector3(12, -3.5, 7)
    private static let rawHalf = SCNVector3(1.35, 2.0, 1.35)

    private static func rawCorners() -> [SCNVector3] {
        var result: [SCNVector3] = []
        for x in [-rawHalf.x, rawHalf.x] {
            for y in [-rawHalf.y, rawHalf.y] {
                for z in [-rawHalf.z, rawHalf.z] {
                    result.append(SCNVector3(rawCenter.x + x, rawCenter.y + y, rawCenter.z + z))
                }
            }
        }
        return result
    }

    /// 建一个与生产一致的最小场景：点云节点 + 相机 + 取景协调器。
    private func makeScene(
        size: CGSize,
        mode: PointCloudViewMode,
        hudInsets: UIEdgeInsets
    ) throws -> (sceneView: SCNView, coordinator: SceneKitPointCloudViewCoordinator, bounds: PointCloudBounds) {
        let vertices = Self.rawCorners()
        let bounds = try XCTUnwrap(PointCloudBounds(vertices: vertices))
        let colors = vertices.map { _ in PointCloudColor(r: 0.4, g: 0.6, b: 0.3, a: 1) }

        let sceneView = SCNView(frame: CGRect(origin: .zero, size: size))
        let scene = SCNScene()
        sceneView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 44
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        let node = try XCTUnwrap(SceneKitPointCloudNodeFactory.makePointCloudNode(
            vertices: vertices,
            colors: colors,
            pointSize: 6,
            bounds: bounds
        ))
        scene.rootNode.addChildNode(node)

        let coordinator = SceneKitPointCloudViewCoordinator()
        coordinator.sceneView = sceneView
        coordinator.hudSafeInsetsDidChange(hudInsets)
        coordinator.viewportDidChange(to: size)
        coordinator.setBounds(bounds)
        coordinator.setViewMode(mode)

        sceneView.layoutIfNeeded()
        sceneView.prepare(scene, shouldAbortBlock: { false })
        _ = sceneView.bounds
        return (sceneView, coordinator, bounds)
    }

    /// 初始视角（自由/正面/俯视/侧面）都必须把整团点云放进安全区。
    func testInitialFramingKeepsTheWholeCloudInsideTheSafeArea() throws {
        // 每个视口用**真实**的 HUD 高度：竖屏是读数条 + 工具条，
        // 横屏的 HUD 更矮（工具条折叠），iPad 又是另一套尺寸。
        let viewports: [(name: String, size: CGSize, insets: UIEdgeInsets)] = [
            ("narrow portrait", CGSize(width: 402, height: 640), UIEdgeInsets(top: 150, left: 0, bottom: 170, right: 0)),
            ("tall phone", CGSize(width: 402, height: 874), UIEdgeInsets(top: 150, left: 0, bottom: 170, right: 0)),
            ("landscape", CGSize(width: 874, height: 402), UIEdgeInsets(top: 64, left: 0, bottom: 96, right: 0)),
            ("ipad portrait", CGSize(width: 834, height: 1112), UIEdgeInsets(top: 150, left: 0, bottom: 170, right: 0))
        ]
        let modes: [PointCloudViewMode] = [.orbit, .front, .top, .side]

        for viewport in viewports {
            let insets = viewport.insets
            for mode in modes {
                let scene = try makeScene(size: viewport.size, mode: mode, hudInsets: insets)
                let bounds = scene.bounds
                let centered = Self.rawCorners().map {
                    SCNVector3($0.x - bounds.center.x, $0.y - bounds.center.y, $0.z - bounds.center.z)
                }
                // 相机投影中心固定在视口中心，因此安全带必须是以视口中心对称的一段。
                let band = max(insets.top, insets.bottom)
                let safeRect = CGRect(
                    x: 0,
                    y: band,
                    width: viewport.size.width,
                    height: viewport.size.height - band * 2
                )
                for corner in centered {
                    let projected = scene.sceneView.projectPoint(corner)
                    XCTAssertTrue(
                        safeRect.insetBy(dx: -0.5, dy: -0.5).contains(CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))),
                        """
                        \(mode.rawValue) in \(viewport.name) clips the point cloud: \
                        corner \(corner) projected to \(projected), safe area \(safeRect)
                        """
                    )
                }
            }
        }
    }

    /// 缩放手势必须保留：放大后仍然由同一套取景逻辑控制，不改变原始点数据。
    func testZoomKeepsWorkingAfterFramingChange() throws {
        let size = CGSize(width: 402, height: 640)
        let scene = try makeScene(size: size, mode: .orbit, hudInsets: .zero)
        let before = scene.sceneView.pointOfView?.position
        scene.coordinator.zoomIn()
        let after = scene.sceneView.pointOfView?.position
        XCTAssertNotEqual(before?.z, after?.z, "zoom in must still move the camera")
        XCTAssertEqual(
            scene.sceneView.scene?.rootNode.childNode(withName: "pointCloud", recursively: true)?.childNodes.count, 0,
            "zoom must not add or remove geometry"
        )
    }
}
