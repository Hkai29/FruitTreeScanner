import Foundation

enum BatchExportSelectionPolicy {
    static func isExportable(_ record: ScanFileRecord) -> Bool {
        record.persistenceState == .complete
    }

    static func exportableRecords(from records: [ScanFileRecord]) -> [ScanFileRecord] {
        records.filter(isExportable)
    }

    static func exportableRecordIDs(from records: [ScanFileRecord]) -> Set<String> {
        Set(exportableRecords(from: records).map(\.id))
    }

    static func normalizedSelection(
        _ selection: Set<String>,
        for records: [ScanFileRecord]
    ) -> Set<String> {
        selection.intersection(exportableRecordIDs(from: records))
    }
}

struct BatchExportRequestSnapshot: Equatable, Sendable {
    let records: [ScanFileRecord]
    let format: BatchExportService.ExportFormat
    let options: BatchExportService.ExportOptions

    init(
        records: [ScanFileRecord],
        selectedRecordIDs: Set<String>,
        format: BatchExportService.ExportFormat,
        options: BatchExportService.ExportOptions
    ) {
        let normalizedSelection = BatchExportSelectionPolicy.normalizedSelection(
            selectedRecordIDs,
            for: records
        )
        self.records = BatchExportSelectionPolicy.exportableRecords(from: records)
            .filter { normalizedSelection.contains($0.id) }
        self.format = format
        self.options = options
    }
}

final class BatchExportService {
    static let shared = BatchExportService()
    
    private init() {}
    
    enum ExportFormat: String, CaseIterable, Equatable, Sendable {
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
    
    struct ExportOptions: Equatable, Sendable {
        var includeGPS: Bool = true
        var includeFruitCount: Bool = true
        var includeYield: Bool = true
        var includeDate: Bool = true
        var includeTreeID: Bool = true
        var groupBy: GroupByOption = .none
        var plotNameByTreeID: [String: String] = [:]
        
        enum GroupByOption: String, CaseIterable, Equatable, Sendable {
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
            let completeRecords = BatchExportSelectionPolicy.exportableRecords(from: records)
            guard !completeRecords.isEmpty else {
                throw BatchExportError.noRecords
            }

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
}

enum BatchExportError: LocalizedError {
    case noRecords
    
    var errorDescription: String? {
        switch self {
        case .noRecords: return "没有可导出的记录"
        }
    }
}
