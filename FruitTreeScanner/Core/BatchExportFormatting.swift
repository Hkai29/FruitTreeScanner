// BatchExportFormatting.swift
// Shared ordering, grouping, and escaping helpers for batch exports.

import Foundation

/// Writes unpublished batch-export files with bounded memory and cooperative cancellation.
/// Any error or cancellation removes the partial destination before returning.
final class BatchExportStreamWriter {
    static let bufferCapacity = 64 * 1024

    private let fileHandle: FileHandle
    private var buffer = Data()
    private var isClosed = false
    private(set) var maximumBufferedByteCount = 0

    private init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        buffer.reserveCapacity(Self.bufferCapacity)
    }

    static func write(
        to url: URL,
        body: (BatchExportStreamWriter) throws -> Void
    ) throws {
        try Task.checkCancellation()
        try Data().write(to: url, options: .atomic)

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        let writer = BatchExportStreamWriter(fileHandle: fileHandle)
        var completed = false
        defer {
            writer.closeIfNeeded()
            if !completed {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try body(writer)
        try writer.finish()
        completed = true
    }

    func write(_ string: String) throws {
        let bytes = string.utf8
        var offset = bytes.startIndex
        while offset < bytes.endIndex {
            try Task.checkCancellation()
            let availableCapacity = Self.bufferCapacity - buffer.count
            let end = bytes.index(
                offset,
                offsetBy: availableCapacity,
                limitedBy: bytes.endIndex
            ) ?? bytes.endIndex
            buffer.append(contentsOf: bytes[offset..<end])
            recordBufferHighWaterMark()
            offset = end

            if buffer.count == Self.bufferCapacity {
                try flush()
            }
        }
    }

    func write(_ data: Data) throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            try Task.checkCancellation()
            let availableCapacity = Self.bufferCapacity - buffer.count
            let count = min(availableCapacity, data.endIndex - offset)
            let end = offset + count
            buffer.append(contentsOf: data[offset..<end])
            recordBufferHighWaterMark()
            offset = end

            if buffer.count == Self.bufferCapacity {
                try flush()
            }
        }
    }

    private func finish() throws {
        try flush()
        try Task.checkCancellation()
        try fileHandle.close()
        isClosed = true
    }

    private func recordBufferHighWaterMark() {
        maximumBufferedByteCount = max(maximumBufferedByteCount, buffer.count)
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try Task.checkCancellation()
        try fileHandle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
        try Task.checkCancellation()
    }

    private func closeIfNeeded() {
        guard !isClosed else { return }
        try? fileHandle.close()
        isClosed = true
    }
}

enum BatchExportFormatting {
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

    static func orderedRecords(
        _ records: [ScanFileRecord],
        options: BatchExportService.ExportOptions
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

    static func groupLabel(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions
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
