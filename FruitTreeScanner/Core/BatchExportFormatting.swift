// BatchExportFormatting.swift
// Shared ordering, grouping, and escaping helpers for batch exports.

import Foundation

enum BatchExportFormatting {
    private struct OrderedRecordKey {
        let groupLabel: String
        let scanDate: Date
    }

    static func headers(options: BatchExportService.ExportOptions) -> [String] {
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
        return headers
    }

    /// Visits records in export order while sorting compact keys and indices instead of record copies.
    static func forEachOrderedRecord(
        _ records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        body: (ScanFileRecord, String) throws -> Void
    ) throws {
        guard options.groupBy != .none else {
            for record in records {
                try Task.checkCancellation()
                try body(record, "")
            }
            return
        }

        let dateFormatter = options.groupBy == .date ? dayGroupDateFormatter : nil
        var sortKeys: [OrderedRecordKey] = []
        sortKeys.reserveCapacity(records.count)
        for record in records {
            try Task.checkCancellation()
            sortKeys.append(
                OrderedRecordKey(
                    groupLabel: groupLabel(
                        for: record,
                        options: options,
                        dateFormatter: dateFormatter
                    ),
                    scanDate: record.scanDate
                )
            )
        }

        var orderedIndices = Array(records.indices)
        try orderedIndices.sort { lhsIndex, rhsIndex in
            try Task.checkCancellation()
            let lhs = sortKeys[lhsIndex]
            let rhs = sortKeys[rhsIndex]
            if lhs.groupLabel == rhs.groupLabel {
                return lhs.scanDate > rhs.scanDate
            }
            return lhs.groupLabel.localizedStandardCompare(rhs.groupLabel) == .orderedAscending
        }

        for index in orderedIndices {
            try Task.checkCancellation()
            try body(records[index], sortKeys[index].groupLabel)
        }
    }

    static func groupLabel(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions
    ) -> String {
        groupLabel(for: record, options: options, dateFormatter: nil)
    }

    private static func groupLabel(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions,
        dateFormatter: DateFormatter?
    ) -> String {
        switch options.groupBy {
        case .none:
            return ""
        case .fruitType:
            return record.fruitType.isEmpty ? "未分类" : record.fruitType
        case .date:
            return (dateFormatter ?? dayGroupDateFormatter).string(from: record.scanDate)
        case .plot:
            return options.plotNameByTreeID[record.treeID] ?? "未分配地块"
        }
    }

    static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    static func spreadsheetText(_ field: String) -> String {
        SpreadsheetTextSafety.neutralizingFormula(field)
    }

    static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func totalYield(_ records: [ScanFileRecord]) -> Float {
        records.reduce(0) { $0 + $1.yieldKg }
    }

    static func totalFruitCount(_ records: [ScanFileRecord]) -> Int {
        records.reduce(0) { $0 + $1.fruitCount }
    }

    private static var dayGroupDateFormatter: DateFormatter {
        StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd")
    }
}
