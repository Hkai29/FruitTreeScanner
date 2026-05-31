import Foundation

final class ScanResultExportService {
    static let shared = ScanResultExportService()

    struct ExportRequest: Sendable {
        let treeID: String
        let fruitType: String
        let scanDate: Date
        let gpsLat: Double
        let gpsLon: Double
        let sourceFilename: String
        let result: YieldResult
        var includeCSV: Bool = true
    }

    struct ExportedFiles: Sendable {
        let csvURL: URL
        let metadataURL: URL?
    }

    private let fileManager: FileManager

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func exportIfNeeded(_ request: ExportRequest) throws -> ExportedFiles? {
        let scansDir = try scansDirectory()
        let baseName = (request.sourceFilename as NSString).deletingPathExtension
        let csvURL = scansDir.appendingPathComponent("\(baseName).csv")

        if request.includeCSV && !fileManager.fileExists(atPath: csvURL.path) {
            let csvContent = makeCSVContent(for: request)
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        }

        let metadataURL = try writeMetadata(for: request, baseName: baseName, scansDir: scansDir)

        return ExportedFiles(csvURL: csvURL, metadataURL: metadataURL)
    }

    private func scansDirectory() throws -> URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCSVContent(for request: ExportRequest) -> String {
        let result = request.result
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let header = [
            "树编号",
            "水果类型",
            "扫描日期",
            "果实数量",
            "产量(kg)",
            "GPS纬度",
            "GPS经度",
            "聚类Eps",
            "聚类MinPoints",
            "颜色过滤",
            "遮挡系数K",
            "点云大小",
            "置信度",
            "方法",
            "备注"
        ]

        let row = [
            request.treeID,
            request.fruitType,
            formatter.string(from: request.scanDate),
            "\(result.nLidar)",
            String(format: "%.2f", result.yieldFinalKg),
            String(format: "%.6f", request.gpsLat),
            String(format: "%.6f", request.gpsLon),
            String(format: "%.3f", result.clusterEps),
            "\(result.clusterMinPoints)",
            result.colorFilterDesc.isEmpty ? "N/A" : result.colorFilterDesc,
            String(format: "%.2f", result.occlusionK),
            "\(result.pointCloudSize)",
            result.confidence,
            result.methodUsed,
            result.note
        ]

        return csvLine(header) + csvLine(row)
    }

    private func writeMetadata(for request: ExportRequest, baseName: String, scansDir: URL) throws -> URL {
        let result = request.result
        let metadataURL = scansDir.appendingPathComponent("\(baseName)_result.json")
        let payload: [String: Any] = [
            "treeID": request.treeID,
            "fruitType": request.fruitType,
            "fruitCount": result.nLidar,
            "yieldKg": result.yieldFinalKg,
            "confidence": result.confidence,
            "methodUsed": result.methodUsed,
            "note": result.note,
            "clusterEps": result.clusterEps,
            "clusterMinPoints": result.clusterMinPoints,
            "fruitCategory": result.fruitCategory,
            "colorFilterDesc": result.colorFilterDesc,
            "occlusionK": result.occlusionK,
            "pointCloudSize": result.pointCloudSize,
            "meanDiameterCm": result.meanDiameterCm,
            "meanVolumeCm3": result.meanVolumeCm3,
            "correctionK": result.correctionK,
            "yieldBVisibleKg": result.yieldBVisibleKg,
            "yieldBCorrectedKg": result.yieldBCorrectedKg,
            "gpsLat": request.gpsLat,
            "gpsLon": request.gpsLon,
            "timestamp": ISO8601DateFormatter().string(from: request.scanDate)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        try data.write(to: metadataURL)
        return metadataURL
    }

    private func csvLine(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    private func csvEscape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
