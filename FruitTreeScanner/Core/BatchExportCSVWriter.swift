// BatchExportCSVWriter.swift
// CSV writer for batch scan exports.

import Foundation

enum BatchExportCSVWriter {
    static func write(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        var rows: [String] = []
        rows.reserveCapacity(records.count + 4)

        rows.append(
            BatchExportFormatting.headers(options: options)
                .map(BatchExportFormatting.escapeCSV)
                .joined(separator: ",")
        )

        let dateFormatter = StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm")

        try BatchExportFormatting.forEachOrderedRecord(records, options: options) { record, groupLabel in
            rows.append(
                row(
                    for: record,
                    groupLabel: groupLabel,
                    options: options,
                    dateFormatter: dateFormatter
                )
            )
        }

        rows.append("")
        rows.append("汇总")
        rows.append(summaryRow(records: records, options: options))

        let csvContent = "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func row(
        for record: ScanFileRecord,
        groupLabel: String,
        options: BatchExportService.ExportOptions,
        dateFormatter: DateFormatter
    ) -> String {
        var row: [String] = []
        if options.groupBy != .none {
            row.append(
                SpreadsheetTextSafety.neutralizingFormula(
                    groupLabel
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
