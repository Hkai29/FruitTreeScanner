import Combine
import CoreLocation
import Foundation

/// A measured trunk base, independent of a phone/camera position and of scan yield.
struct TreeSurveyPoint: Identifiable, Equatable, Sendable {
    var id: String { treeID }
    let treeID: String
    let longitude: Double
    let latitude: Double
    let horizontalAccuracyMeters: Double
    let method: TreeSurveyMethod
    let measuredAt: String
    let sourceNote: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A declared input quality gate, not independent physical accuracy acceptance.
    var meetsReportedTarget: Bool {
        (method == .rtkFixed || method == .totalStation) && horizontalAccuracyMeters <= 1.0
    }

    var accuracyDescription: String {
        String(format: "报告误差半径 %.3f m", horizontalAccuracyMeters)
    }
}

enum TreeSurveyMethod: String, Codable, Sendable {
    case rtkFixed = "rtk_fixed"
    case rtkFloat = "rtk_float"
    case totalStation = "total_station"
    case deviceGPS = "device_gps"

    var title: String {
        switch self {
        case .rtkFixed: return "RTK 固定解"
        case .rtkFloat: return "RTK 浮点解 · 待复测"
        case .totalStation: return "全站仪测量"
        case .deviceGPS: return "普通定位 · 仅参考"
        }
    }
}

struct TreeSurveyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum TreeSurveyCodec {
    static let maximumFileBytes = 2 * 1024 * 1024
    static let maximumPointCount = 5_000

    private struct Collection: Codable {
        let type: String
        let features: [Feature]
    }
    private struct Feature: Codable {
        let type: String
        let geometry: Geometry
        let properties: Properties
    }
    private struct Geometry: Codable {
        let type: String
        let coordinates: [Double]
    }
    private struct Properties: Codable {
        let tree_id: String
        let position_source: TreeSurveyMethod
        let horizontal_accuracy_m: Double
        let measured_at: String
        let reference: String
        let source_note: String
    }

    static func decode(_ data: Data) throws -> [TreeSurveyPoint] {
        guard data.count <= maximumFileBytes else { throw error("树位文件不能超过 2 MB。") }
        let raw: [String: Any]
        let collection: Collection
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw error("请选择树位 GeoJSON。")
            }
            raw = object
            collection = try JSONDecoder().decode(Collection.self, from: data)
        } catch {
            throw self.error("树位文件格式不完整。请检查树号、来源、误差、测量日期与 Point 坐标。")
        }
        guard raw["crs"] == nil else { throw error("请先转换为 WGS84 经纬度，再导入树位；不接受投影或偏移坐标系声明。") }
        guard collection.type == "FeatureCollection", !collection.features.isEmpty,
              collection.features.count <= maximumPointCount else {
            throw error("每个文件需包含 1–5000 个树位 Point。")
        }
        var identities = Set<String>()
        let fractionalDateParser = ISO8601DateFormatter()
        fractionalDateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateParser = ISO8601DateFormatter()
        return try collection.features.map { feature in
            let p = feature.properties
            let treeID = TreeIdentifierPolicy.normalized(p.tree_id)
            guard TreeIdentifierPolicy.isValid(treeID), identities.insert(treeID).inserted else {
                throw error("树号无效或重复：\(treeID)。整批树位尚未导入。")
            }
            let xy = feature.geometry.coordinates
            guard feature.type == "Feature", feature.geometry.type == "Point", xy.count == 2,
                  xy.allSatisfy(\.isFinite), (-180...180).contains(xy[0]), (-85...85).contains(xy[1]) else {
                throw error("\(treeID) 需要 [经度, 纬度] 的 WGS84 Point，纬度范围为 -85 至 85。")
            }
            guard p.reference == "trunk_base" else {
                throw error("\(treeID) 的测量对象必须是树干基部 trunk_base，不能使用手机位置。")
            }
            guard p.horizontal_accuracy_m.isFinite, p.horizontal_accuracy_m > 0,
                  p.horizontal_accuracy_m <= 10_000 else {
                throw error("\(treeID) 缺少有效的水平误差半径（单位：米）。")
            }
            let date = fractionalDateParser.date(from: p.measured_at) ?? dateParser.date(from: p.measured_at)
            guard let date, date <= Date().addingTimeInterval(300) else {
                throw error("\(treeID) 的测量日期无效或在未来。")
            }
            let note = p.source_note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, note.count <= 160 else {
                throw error("\(treeID) 需要 1–160 字的测量来源或测站说明。")
            }
            return TreeSurveyPoint(treeID: treeID, longitude: xy[0], latitude: xy[1],
                                   horizontalAccuracyMeters: p.horizontal_accuracy_m,
                                   method: p.position_source, measuredAt: p.measured_at, sourceNote: note)
        }
    }

    static func encode(_ points: [TreeSurveyPoint]) throws -> Data {
        let collection = Collection(type: "FeatureCollection", features: points.map { point in
            Feature(type: "Feature", geometry: Geometry(type: "Point", coordinates: [point.longitude, point.latitude]),
                    properties: Properties(tree_id: point.treeID, position_source: point.method,
                        horizontal_accuracy_m: point.horizontalAccuracyMeters, measured_at: point.measuredAt,
                        reference: "trunk_base", source_note: point.sourceNote))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(collection)
    }

    static func readFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw error("树位文件不能超过 2 MB。") }
        return data
    }

    private static func error(_ message: String) -> TreeSurveyError { TreeSurveyError(message: message) }
}

@MainActor
final class TreeSurveyCatalog: ObservableObject {
    struct RecoverySnapshot {
        fileprivate let owner: UUID
        fileprivate let original: Data
    }

    static let shared = TreeSurveyCatalog(fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TreeSurvey/positions.geojson"))
    @Published private(set) var points: [TreeSurveyPoint] = []
    @Published private(set) var loadError: String?
    private let fileURL: URL
    private let write: (Data, URL) throws -> Void
    private let copyBackup: (URL, URL) throws -> Void
    private let recoveryOwner = UUID()

    init(fileURL: URL, write: @escaping (Data, URL) throws -> Void = { data, url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }, copyBackup: @escaping (URL, URL) throws -> Void = { source, destination in
        try FileManager.default.copyItem(at: source, to: destination)
    }) {
        self.fileURL = fileURL
        self.write = write
        self.copyBackup = copyBackup
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { points = try TreeSurveyCodec.decode(TreeSurveyCodec.readFile(fileURL)) }
        catch { loadError = "树位档案读取失败，原文件已保留，当前页面已停止写入。需要恢复 TreeSurvey/positions.geojson：\(error.localizedDescription)" }
    }

    func point(treeID: String) -> TreeSurveyPoint? {
        let normalized = TreeIdentifierPolicy.normalized(treeID)
        return points.first { $0.treeID == normalized }
    }

    func conflictCount(for imported: [TreeSurveyPoint]) -> Int {
        let identities = Set(points.map(\.treeID))
        return imported.reduce(0) { $0 + (identities.contains($1.treeID) ? 1 : 0) }
    }

    /// Bind a recovery preview to this catalog and the exact unreadable file.
    /// A valid or externally repaired file must never be replaced by an old preview.
    func prepareRecovery() throws -> RecoverySnapshot {
        guard loadError != nil else { throw TreeSurveyError(message: "档案状态已改变，请重新打开导入预览。") }
        let original = try TreeSurveyCodec.readFile(fileURL)
        if (try? TreeSurveyCodec.decode(original)) != nil {
            throw TreeSurveyError(message: "原档已改变或已修复，请重新启动应用读取当前档案后再导入。")
        }
        return RecoverySnapshot(owner: recoveryOwner, original: original)
    }

    /// Recovery is deliberately separate from ordinary commit. No suspension is
    /// allowed between the final source check, atomic replacement and publication.
    /// The production writer is atomic; injected writers must uphold that contract.
    @discardableResult
    func recover(_ imported: [TreeSurveyPoint], from snapshot: RecoverySnapshot, confirmed: Bool) throws -> URL {
        guard confirmed, loadError != nil, snapshot.owner == recoveryOwner else {
            throw TreeSurveyError(message: "请重新预览并明确确认恢复树位档案。")
        }
        guard !imported.isEmpty, imported.count <= TreeSurveyCodec.maximumPointCount else {
            throw TreeSurveyError(message: "恢复文件需包含 1–5000 个树位 Point。")
        }
        let validated = try TreeSurveyCodec.decode(TreeSurveyCodec.encode(imported)).sorted { $0.treeID < $1.treeID }
        let data = try TreeSurveyCodec.encode(validated)
        guard try TreeSurveyCodec.readFile(fileURL) == snapshot.original else {
            throw TreeSurveyError(message: "原档在预览后已改变，尚未覆盖。请重新预览。")
        }
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("positions-unreadable-\(UUID().uuidString).geojson")
        // copyItem refuses to overwrite an existing backup. Verify the copy before
        // replacing the active file, and retain it if the atomic write fails.
        try copyBackup(fileURL, backup)
        guard try TreeSurveyCodec.readFile(backup) == snapshot.original,
              try TreeSurveyCodec.readFile(fileURL) == snapshot.original else {
            throw TreeSurveyError(message: "原档副本核验失败或原档已改变，尚未覆盖。")
        }
        try write(data, fileURL)
        points = validated
        loadError = nil
        return backup
    }

    /// Validate and write the entire candidate before publishing any changes.
    func commit(_ imported: [TreeSurveyPoint], replacingExisting: Bool) throws {
        guard loadError == nil else { throw TreeSurveyError(message: "当前树位档案读取失败，已阻止覆盖。原文件需要先恢复。") }
        let validated = try TreeSurveyCodec.decode(TreeSurveyCodec.encode(imported))
        let importedIDs = Set(validated.map(\.treeID))
        guard replacingExisting || !points.contains(where: { importedIDs.contains($0.treeID) }) else {
            throw TreeSurveyError(message: "包含已有树号，请明确确认更新测量点。")
        }
        let candidate = (points.filter { !importedIDs.contains($0.treeID) } + validated).sorted { $0.treeID < $1.treeID }
        guard candidate.count <= TreeSurveyCodec.maximumPointCount else { throw TreeSurveyError(message: "树位总数不能超过 5000 棵。") }
        let data = try TreeSurveyCodec.encode(candidate)
        guard data.count <= TreeSurveyCodec.maximumFileBytes else { throw TreeSurveyError(message: "合并后的树位档案超过 2 MB，未保存。") }
        try write(data, fileURL)
        points = candidate
    }
}
