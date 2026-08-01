// BatchExportExcelWriter.swift
// Excel XML writer for batch scan exports.

import Foundation

enum BatchExportExcelWriter {
    static func write(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        let dateFormatter = StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm")

        try BatchExportStreamWriter.write(to: url) { writer in
            try writer.write(workbookPrefix)
            try writer.write(headerRow(options: options))

            for record in BatchExportFormatting.orderedRecords(records, options: options) {
                try Task.checkCancellation()
                try writer.write(row(for: record, options: options, dateFormatter: dateFormatter))
            }

            try writer.write("""
                  </Table>
          </Worksheet>
        </Workbook>
        """)
        }
    }

    private static var workbookPrefix: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <?xml-stylesheet type="text/xsl" href="grid.xsl"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
                  xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
          <Worksheet ss:Name="果园数据">
            <Table>

        """
    }

    private static func headerRow(options: BatchExportService.ExportOptions) -> String {
        var xml = "              <Row>\n"
        for header in BatchExportFormatting.headers(options: options) {
            xml += "                <Cell><Data ss:Type=\"String\">\(BatchExportFormatting.escapeXML(header))</Data></Cell>\n"
        }
        xml += "              </Row>\n"
        return xml
    }

    private static func row(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions,
        dateFormatter: DateFormatter
    ) -> String {
        var xml = "              <Row>\n"
        if options.groupBy != .none {
            xml += stringCell(
                BatchExportFormatting.spreadsheetText(
                    BatchExportFormatting.groupLabel(for: record, options: options)
                )
            )
        }
        if options.includeTreeID {
            xml += stringCell(BatchExportFormatting.spreadsheetText(record.treeID))
        }
        if options.includeFruitCount {
            xml += numberCell("\(record.fruitCount)")
        }
        if options.includeYield {
            xml += numberCell(StableDataFormatting.decimal(record.yieldKg, precision: 2))
        }
        if options.includeGPS {
            xml += numberCell(StableDataFormatting.decimal(record.gpsLat, precision: 6))
            xml += numberCell(StableDataFormatting.decimal(record.gpsLon, precision: 6))
        }
        if options.includeDate {
            xml += stringCell(dateFormatter.string(from: record.scanDate))
        }
        xml += stringCell(BatchExportFormatting.spreadsheetText(record.fruitType))
        xml += "              </Row>\n"
        return xml
    }

    private static func stringCell(_ value: String) -> String {
        "                <Cell><Data ss:Type=\"String\">\(BatchExportFormatting.escapeXML(value))</Data></Cell>\n"
    }

    private static func numberCell(_ value: String) -> String {
        "                <Cell><Data ss:Type=\"Number\">\(value)</Data></Cell>\n"
    }
}
