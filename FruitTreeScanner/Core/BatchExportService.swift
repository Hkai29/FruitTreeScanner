import Foundation

final class BatchExportService {
    static let shared = BatchExportService()
    
    private init() {}
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case excel = "Excel (XML)"
        case json = "Research JSON"
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .excel: return "xls"
            case .json: return "json"
            }
        }
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .excel: return "tablecells.fill"
            case .json: return "doc.text.magnifyingglass"
            }
        }
        
        var description: String {
            switch self {
            case .csv: return "通用数据格式，兼容所有表格软件"
            case .excel: return "Microsoft Excel 兼容格式"
            case .json: return "研究分析用结构化 JSON"
            }
        }
    }
    
    struct ExportOptions: Equatable {
        var includeGPS: Bool = true
        var includeFruitCount: Bool = true
        var includeYield: Bool = true
        var includeDate: Bool = true
        var includeTreeID: Bool = true
        var groupBy: GroupByOption = .none
        var plotNameByTreeID: [String: String] = [:]
        
        enum GroupByOption: String, CaseIterable, Equatable {
            case none = "不分组"
            case fruitType = "按水果类型"
            case date = "按日期"
            case plot = "按地块"
        }
    }
    
    struct ExportResult {
        let url: URL
        let recordCount: Int
        let totalYield: Float
        let totalFruitCount: Int
        let excludedIncompleteCount: Int
    }
    
    func export(
        records: [ScanFileRecord],
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> ExportResult {
        let exportTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let completeRecords = records.filter { $0.persistenceState == .complete }
            guard !completeRecords.isEmpty else {
                throw BatchExportError.noRecords
            }
            try Self.validateCurrentRecords(completeRecords)

            let timestamp = Self.filenameDateFormatter.string(from: Date())
            let filename = "果园批次数据_\(timestamp)_\(UUID().uuidString.prefix(8)).\(format.fileExtension)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            var shouldKeepFile = false
            defer {
                if !shouldKeepFile, FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            let totalYield = completeRecords.reduce(0) { $0 + $1.yieldKg }
            let totalFruitCount = completeRecords.reduce(0) { $0 + $1.fruitCount }

            switch format {
            case .csv:
                try BatchExportCSVWriter.write(records: completeRecords, options: options, to: tempURL)
            case .excel:
                try BatchExportExcelWriter.write(records: completeRecords, options: options, to: tempURL)
            case .json:
                try BatchExportJSONWriter.write(records: completeRecords, options: options, to: tempURL)
            }

            try Task.checkCancellation()
            try Self.validateCurrentRecords(completeRecords)
            shouldKeepFile = true
            return ExportResult(
                url: tempURL,
                recordCount: completeRecords.count,
                totalYield: totalYield,
                totalFruitCount: totalFruitCount,
                excludedIncompleteCount: records.count - completeRecords.count
            )
        }

        return try await withTaskCancellationHandler {
            try await exportTask.value
        } onCancel: {
            exportTask.cancel()
        }
    }

    nonisolated static var filenameDateFormatter: DateFormatter {
        StableDataFormatting.dateFormatter(dateFormat: "yyyyMMdd_HHmmss")
    }

    /// History rows are snapshots. Check their source and companions before
    /// and after writing every batch format.
    nonisolated private static func validateCurrentRecords(_ records: [ScanFileRecord]) throws {
        let fileManager = FileManager.default
        for record in records {
            try Task.checkCancellation()
            let baseURL = record.fileURL.deletingPathExtension()
            let directory = record.fileURL.deletingLastPathComponent()
            let sidecarExists = [
                baseURL.appendingPathExtension("csv"),
                directory.appendingPathComponent("\(baseURL.lastPathComponent)_result.json"),
                directory.appendingPathComponent("\(baseURL.lastPathComponent)_complete.json")
            ].contains { fileManager.fileExists(atPath: $0.path) }
            if !sidecarExists && !record.requiresSourceValidation { continue }
            guard let current = PLYParserHelper.readCompanionResult(for: record.fileURL).result,
                  current.fruitCount == record.fruitCount,
                  current.yieldKg == record.yieldKg,
                  current.fruitType == record.fruitType
            else { throw BatchExportError.inconsistentRecord }
            if record.requiresSourceValidation {
                guard fileManager.fileExists(atPath: record.fileURL.path),
                      let size = try? record.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size == record.fileSizeBytes,
                      current.confidence == record.confidence
                else { throw BatchExportError.inconsistentRecord }
                let metadata = PLYParserHelper.parseHeaderMetadata(from: record.fileURL)
                    ?? PLYParserHelper.parseFilenameMetadata(from: record.fileURL)
                    ?? PLYParserHelper.fallbackMetadata(from: record.fileURL)
                guard metadata.treeID == record.treeID,
                      metadata.scanDate == record.scanDate,
                      metadata.gpsLat == record.gpsLat,
                      metadata.gpsLon == record.gpsLon
                else { throw BatchExportError.inconsistentRecord }
            }
        }
    }
}

enum BatchExportError: LocalizedError {
    case noRecords
    case inconsistentRecord
    
    var errorDescription: String? {
        switch self {
        case .noRecords: return "没有可导出的记录"
        case .inconsistentRecord: return "扫描结果文件不完整或已更新，请刷新历史记录后重试导出"
        }
    }
}
