import Foundation

final class BatchExportService {
    static let shared = BatchExportService()
    
    private init() {}
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case excel = "Excel (XML)"
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .excel: return "xls"
            }
        }
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .excel: return "tablecells.fill"
            }
        }
        
        var description: String {
            switch self {
            case .csv: return "通用数据格式，兼容所有表格软件"
            case .excel: return "Microsoft Excel 兼容格式"
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
    }
    
    func export(
        records: [ScanFileRecord],
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> ExportResult {
        let exportTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard !records.isEmpty else {
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

            let totalYield = records.reduce(0) { $0 + $1.yieldKg }
            let totalFruitCount = records.reduce(0) { $0 + $1.fruitCount }

            switch format {
            case .csv:
                try BatchExportCSVWriter.write(records: records, options: options, to: tempURL)
            case .excel:
                try BatchExportExcelWriter.write(records: records, options: options, to: tempURL)
            }

            try Task.checkCancellation()
            shouldKeepFile = true
            return ExportResult(
                url: tempURL,
                recordCount: records.count,
                totalYield: totalYield,
                totalFruitCount: totalFruitCount
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
