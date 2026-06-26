import Foundation
import UIKit

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
                try Self.exportToCSV(records: records, options: options, to: tempURL)
            case .excel:
                try Self.exportToExcel(records: records, options: options, to: tempURL)
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
    
    nonisolated private static func exportToCSV(records: [ScanFileRecord], options: ExportOptions, to url: URL) throws {
        var rows: [String] = []
        rows.reserveCapacity(records.count + 4)

        var headers: [String] = []
        if options.groupBy != .none { headers.append("分组") }
        if options.includeTreeID { headers.append("果树编号") }
        if options.includeFruitCount { headers.append("果实数量") }
        if options.includeYield { headers.append("产量(kg)") }
        if options.includeGPS {
            headers.append("纬度")
            headers.append("经度")
        }
        if options.includeDate { headers.append("扫描日期") }
        headers.append("水果类型")
        
        rows.append(headers.map(escapeCSV).joined(separator: ","))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for record in orderedRecords(records, options: options) {
            try Task.checkCancellation()
            var row: [String] = []
            if options.groupBy != .none {
                row.append(SpreadsheetTextSafety.neutralizingFormula(groupLabel(for: record, options: options)))
            }
            if options.includeTreeID {
                row.append(SpreadsheetTextSafety.neutralizingFormula(record.treeID))
            }
            if options.includeFruitCount { row.append("\(record.fruitCount)") }
            if options.includeYield { row.append(String(format: "%.2f", record.yieldKg)) }
            if options.includeGPS {
                row.append(String(format: "%.6f", record.gpsLat))
                row.append(String(format: "%.6f", record.gpsLon))
            }
            if options.includeDate { row.append(dateFormatter.string(from: record.scanDate)) }
            row.append(SpreadsheetTextSafety.neutralizingFormula(record.fruitType))
            
            rows.append(row.map(escapeCSV).joined(separator: ","))
        }
        
        rows.append("")
        rows.append("汇总")
        rows.append(["总计", "\(records.count) 棵", "\(totalFruitCount(records)) 个", String(format: "%.2f kg", totalYield(records))].map(escapeCSV).joined(separator: ","))

        let csvContent = "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    nonisolated private static func exportToExcel(records: [ScanFileRecord], options: ExportOptions, to url: URL) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        var headers: [String] = []
        if options.groupBy != .none { headers.append("分组") }
        if options.includeTreeID { headers.append("果树编号") }
        if options.includeFruitCount { headers.append("果实数量") }
        if options.includeYield { headers.append("产量(kg)") }
        if options.includeGPS {
            headers.append("纬度")
            headers.append("经度")
        }
        if options.includeDate { headers.append("扫描日期") }
        headers.append("水果类型")
        
        var xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <?xml-stylesheet type="text/xsl" href="grid.xsl"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
                  xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
          <Worksheet ss:Name="果园数据">
            <Table>

        """
        
        xmlContent += "              <Row>\n"
        for header in headers {
            xmlContent += "                <Cell><Data ss:Type=\"String\">\(escapeXML(header))</Data></Cell>\n"
        }
        xmlContent += "              </Row>\n"
        
        for record in orderedRecords(records, options: options) {
            try Task.checkCancellation()
            xmlContent += "              <Row>\n"
            if options.groupBy != .none {
                xmlContent += "                <Cell><Data ss:Type=\"String\">\(escapeXML(spreadsheetText(groupLabel(for: record, options: options))))</Data></Cell>\n"
            }
            if options.includeTreeID {
                xmlContent += "                <Cell><Data ss:Type=\"String\">\(escapeXML(spreadsheetText(record.treeID)))</Data></Cell>\n"
            }
            if options.includeFruitCount {
                xmlContent += "                <Cell><Data ss:Type=\"Number\">\(record.fruitCount)</Data></Cell>\n"
            }
            if options.includeYield {
                xmlContent += "                <Cell><Data ss:Type=\"Number\">\(String(format: "%.2f", record.yieldKg))</Data></Cell>\n"
            }
            if options.includeGPS {
                xmlContent += "                <Cell><Data ss:Type=\"Number\">\(String(format: "%.6f", record.gpsLat))</Data></Cell>\n"
                xmlContent += "                <Cell><Data ss:Type=\"Number\">\(String(format: "%.6f", record.gpsLon))</Data></Cell>\n"
            }
            if options.includeDate {
                xmlContent += "                <Cell><Data ss:Type=\"String\">\(escapeXML(dateFormatter.string(from: record.scanDate)))</Data></Cell>\n"
            }
            xmlContent += "                <Cell><Data ss:Type=\"String\">\(escapeXML(spreadsheetText(record.fruitType)))</Data></Cell>\n"
            xmlContent += "              </Row>\n"
        }
        
        xmlContent += """
                  </Table>
          </Worksheet>
        </Workbook>
        """
        
        try xmlContent.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private static func orderedRecords(
        _ records: [ScanFileRecord],
        options: ExportOptions
    ) -> [ScanFileRecord] {
        guard options.groupBy != .none else { return records }
        return records.sorted { lhs, rhs in
            let lhsGroup = groupLabel(for: lhs, options: options)
            let rhsGroup = groupLabel(for: rhs, options: options)
            if lhsGroup == rhsGroup {
                return lhs.scanDate > rhs.scanDate
            }
            return lhsGroup.localizedStandardCompare(rhsGroup) == .orderedAscending
        }
    }

    nonisolated private static func groupLabel(
        for record: ScanFileRecord,
        options: ExportOptions
    ) -> String {
        switch options.groupBy {
        case .none:
            return ""
        case .fruitType:
            return record.fruitType.isEmpty ? "未分类" : record.fruitType
        case .date:
            return dayGroupDateFormatter.string(from: record.scanDate)
        case .plot:
            return options.plotNameByTreeID[record.treeID] ?? "未分配地块"
        }
    }
    
    nonisolated private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    nonisolated private static func spreadsheetText(_ field: String) -> String {
        SpreadsheetTextSafety.neutralizingFormula(field)
    }

    nonisolated private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    nonisolated private static var filenameDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }

    nonisolated private static var dayGroupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    nonisolated private static func totalYield(_ records: [ScanFileRecord]) -> Float {
        records.reduce(0) { $0 + $1.yieldKg }
    }
    
    nonisolated private static func totalFruitCount(_ records: [ScanFileRecord]) -> Int {
        records.reduce(0) { $0 + $1.fruitCount }
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
