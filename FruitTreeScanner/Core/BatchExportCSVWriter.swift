// BatchExportCSVWriter.swift
// CSV writer for batch scan exports.

import Foundation

enum BatchExportCSVWriter {
    static func write(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        let header = BatchExportFormatting.headers(options: options)
            .map(BatchExportFormatting.escapeCSV)
            .joined(separator: ",")
        let dateFormatter = StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm")

        try BatchExportStreamWriter.write(to: url) { writer in
            try writer.write("\u{FEFF}")
            try writer.write(header)
            try writer.write("\n")

            for record in BatchExportFormatting.orderedRecords(records, options: options) {
                try Task.checkCancellation()
                try writer.write(row(for: record, options: options, dateFormatter: dateFormatter))
                try writer.write("\n")
            }

            try writer.write("\n汇总\n")
            try writer.write(summaryRow(records: records, options: options))
            try writer.write("\n")
        }
    }

    private static func row(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions,
        dateFormatter: DateFormatter
    ) -> String {
        var row: [String] = []
        if options.groupBy != .none {
            row.append(
                SpreadsheetTextSafety.neutralizingFormula(
                    BatchExportFormatting.groupLabel(for: record, options: options)
                )
            )
        }
        if options.includeTreeID {
            row.append(SpreadsheetTextSafety.neutralizingFormula(record.treeID))
        }
        if options.includeFruitCount { row.append("\(record.fruitCount)") }
        if options.includeYield { row.append(StableDataFormatting.decimal(record.yieldKg, precision: 2)) }
        if options.includeGPS {
            row.append(StableDataFormatting.decimal(record.gpsLat, precision: 6))
            row.append(StableDataFormatting.decimal(record.gpsLon, precision: 6))
        }
        if options.includeDate { row.append(dateFormatter.string(from: record.scanDate)) }
        row.append(SpreadsheetTextSafety.neutralizingFormula(record.fruitType))

        return row.map(BatchExportFormatting.escapeCSV).joined(separator: ",")
    }

    private static func summaryRow(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions
    ) -> String {
        var fields = [
            "总计",
            "\(records.count) 棵"
        ]

        if options.includeFruitCount {
            fields.append("\(BatchExportFormatting.totalFruitCount(records)) 个")
        }
        if options.includeYield {
            fields.append(
                "\(StableDataFormatting.decimal(BatchExportFormatting.totalYield(records), precision: 2)) kg"
            )
        }

        return fields
            .map(BatchExportFormatting.escapeCSV)
            .joined(separator: ",")
    }
}
