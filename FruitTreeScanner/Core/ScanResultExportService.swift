import Foundation
import os

final class ScanResultExportService: @unchecked Sendable {
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
        let csvURL: URL?
        let metadataURL: URL?
    }

    private let fileManager: FileManager
    private let exportQueue = DispatchQueue(label: "com.fruittreescanner.scan-result-export")

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func exportIfNeeded(_ request: ExportRequest) throws -> ExportedFiles? {
        try exportQueue.sync {
            try exportIfNeededOnQueue(request)
        }
    }

    @discardableResult
    private func exportIfNeededOnQueue(_ request: ExportRequest) throws -> ExportedFiles? {
        let scansDir = try scansDirectory()
        guard LocalFileStorage.isSafeLeafFilename(request.sourceFilename) else {
            throw LocalFileStorageError.invalidFilename
        }
        let baseName = (request.sourceFilename as NSString).deletingPathExtension
        guard !baseName.isEmpty else {
            throw LocalFileStorageError.invalidFilename
        }
        let csvURL = scansDir.appendingPathComponent("\(baseName).csv")

        let metadataURL = try writeMetadata(for: request, baseName: baseName, scansDir: scansDir)

        if request.includeCSV && !fileManager.fileExists(atPath: csvURL.path) {
            let csvContent = makeCSVContent(for: request)
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            Log.export.info("CSV exported: \(baseName).csv")
        }

        Log.export.info("Export complete for \(request.treeID)")

        let exportedCSVURL = fileManager.fileExists(atPath: csvURL.path) ? csvURL : nil
        return ExportedFiles(csvURL: exportedCSVURL, metadataURL: metadataURL)
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
            SpreadsheetTextSafety.neutralizingFormula(request.treeID),
            SpreadsheetTextSafety.neutralizingFormula(request.fruitType),
            formatter.string(from: request.scanDate),
            "\(result.nLidar)",
            format(result.yieldFinalKg, precision: 2),
            format(request.gpsLat, precision: 6),
            format(request.gpsLon, precision: 6),
            format(result.clusterEps, precision: 3),
            "\(result.clusterMinPoints)",
            SpreadsheetTextSafety.neutralizingFormula(
                result.colorFilterDesc.isEmpty ? "N/A" : result.colorFilterDesc
            ),
            format(result.occlusionK, precision: 2),
            "\(result.pointCloudSize)",
            SpreadsheetTextSafety.neutralizingFormula(result.confidence),
            SpreadsheetTextSafety.neutralizingFormula(result.methodUsed),
            SpreadsheetTextSafety.neutralizingFormula(result.note)
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
            "yieldKg": finite(result.yieldFinalKg),
            "confidence": result.confidence,
            "methodUsed": result.methodUsed,
            "note": result.note,
            "clusterEps": finite(result.clusterEps),
            "clusterMinPoints": result.clusterMinPoints,
            "fruitCategory": result.fruitCategory,
            "colorFilterDesc": result.colorFilterDesc,
            "occlusionK": finite(result.occlusionK),
            "pointCloudSize": result.pointCloudSize,
            "meanDiameterCm": finite(result.meanDiameterCm),
            "meanVolumeCm3": finite(result.meanVolumeCm3),
            "correctionK": finite(result.correctionK),
            "yieldBVisibleKg": finite(result.yieldBVisibleKg),
            "yieldBCorrectedKg": finite(result.yieldBCorrectedKg),
            "gpsLat": finite(request.gpsLat),
            "gpsLon": finite(request.gpsLon),
            "timestamp": ISO8601DateFormatter().string(from: request.scanDate)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        try data.write(to: metadataURL, options: .atomic)
        return metadataURL
    }

    private func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    private func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private func format(_ value: Float, precision: Int) -> String {
        String(format: "%.\(precision)f", finite(value))
    }

    private func format(_ value: Double, precision: Int) -> String {
        String(format: "%.\(precision)f", finite(value))
    }

    private func csvLine(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    private func csvEscape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
