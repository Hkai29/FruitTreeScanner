import Foundation
import SceneKit
import simd

// MARK: - Point Cloud Color Mode
enum PointCloudColorMode: String, CaseIterable {
    case height = "高度"
    case density = "密度"
    case fruit = "果实"
    case uniform = "统一"

    var displayName: String {
        switch self {
        case .height: return L10n.PointCloud.colorHeight
        case .density: return L10n.PointCloud.colorDensity
        case .fruit: return L10n.PointCloud.colorFruit
        case .uniform: return L10n.PointCloud.colorUniform
        }
    }

    var icon: String {
        switch self {
        case .height: return "arrow.up.arrow.down"
        case .density: return "circle.grid.3x3"
        case .fruit: return "leaf.fill"
        case .uniform: return "paintpalette"
        }
    }
}

// MARK: - Point Cloud View Mode
enum PointCloudViewMode: String, CaseIterable {
    case orbit = "自由"
    case front = "正面"
    case top = "俯视"
    case side = "侧面"

    var displayName: String {
        switch self {
        case .orbit: return L10n.PointCloud.viewOrbit
        case .front: return L10n.PointCloud.viewFront
        case .top: return L10n.PointCloud.viewTop
        case .side: return L10n.PointCloud.viewSide
        }
    }

    var icon: String {
        switch self {
        case .orbit: return "rotate.3d"
        case .front: return "rectangle.portrait"
        case .top: return "square.grid.3x3"
        case .side: return "rectangle"
        }
    }

    var detail: String {
        switch self {
        case .orbit: return L10n.PointCloud.viewDetailOrbit
        case .front: return L10n.PointCloud.viewDetailFront
        case .top: return L10n.PointCloud.viewDetailTop
        case .side: return L10n.PointCloud.viewDetailSide
        }
    }

    var usesOrthographicCamera: Bool {
        self != .orbit
    }
}

// MARK: - Point Cloud Bounds
struct PointCloudBounds: Sendable {
    let min: SCNVector3
    let max: SCNVector3
    let center: SCNVector3
    let size: SCNVector3
    let radius: Float

    var heightMeters: Float { size.y }
    var widthMeters: Float { size.x }
    var depthMeters: Float { size.z }

    init?(vertices: [SCNVector3]) {
        guard let first = vertices.first else { return nil }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        var minZ = first.z
        var maxZ = first.z

        for vertex in vertices.dropFirst() {
            minX = Swift.min(minX, vertex.x)
            maxX = Swift.max(maxX, vertex.x)
            minY = Swift.min(minY, vertex.y)
            maxY = Swift.max(maxY, vertex.y)
            minZ = Swift.min(minZ, vertex.z)
            maxZ = Swift.max(maxZ, vertex.z)
        }

        min = SCNVector3(minX, minY, minZ)
        max = SCNVector3(maxX, maxY, maxZ)
        center = SCNVector3(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )
        size = SCNVector3(
            Swift.max(maxX - minX, 0.001),
            Swift.max(maxY - minY, 0.001),
            Swift.max(maxZ - minZ, 0.001)
        )

        let halfX = size.x / 2
        let halfY = size.y / 2
        let halfZ = size.z / 2
        radius = Swift.max(sqrt(halfX * halfX + halfY * halfY + halfZ * halfZ), 0.25)
    }

    var heightText: String {
        String(format: "%.2f m", heightMeters)
    }

    var footprintText: String {
        String(format: "%.2f x %.2f m", widthMeters, depthMeters)
    }
}

// MARK: - Point Cloud Display Data
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
    let bounds: PointCloudBounds?

    var pointCount: Int { vertices.count }

    init(id: String, vertices: [SCNVector3], colors: [PointCloudColor]) {
        self.id = id
        self.vertices = vertices
        self.colors = colors
        self.bounds = PointCloudBounds(vertices: vertices)
    }
}

struct ColoredPoint: Sendable {
    let pos: SIMD3<Float>
    let r: Float
    let g: Float
    let b: Float
}
