// BatchExportFormatting.swift
// Shared ordering, grouping, and escaping helpers for batch exports.

import Foundation

struct BatchExportTotals: Equatable, Sendable {
    let totalYield: Float
    let totalFruitCount: Int
}

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

    static func totals(for records: [ScanFileRecord]) -> BatchExportTotals? {
        var totalYield: Float = 0
        var totalFruitCount = 0
        for record in records {
            let nextYield = totalYield + record.yieldKg
            guard nextYield.isFinite else { return nil }
            let nextCount = totalFruitCount.addingReportingOverflow(record.fruitCount)
            guard !nextCount.overflow else { return nil }
            totalYield = nextYield
            totalFruitCount = nextCount.partialValue
        }
        return BatchExportTotals(
            totalYield: totalYield,
            totalFruitCount: totalFruitCount
        )
    }

    private static var dayGroupDateFormatter: DateFormatter {
        StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd")
    }
}
