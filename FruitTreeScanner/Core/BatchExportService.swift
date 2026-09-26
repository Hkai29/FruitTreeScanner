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

struct BatchExportTemporaryStorage {
    static let directoryName = "FruitTreeScannerBatchExports"

    let fileManager: FileManager
    let baseTemporaryDirectory: URL
    let sessionID: String

    init(
        fileManager: FileManager = .default,
        baseTemporaryDirectory: URL? = nil,
        sessionID: String
    ) {
        self.fileManager = fileManager
        self.baseTemporaryDirectory = baseTemporaryDirectory ?? fileManager.temporaryDirectory
        self.sessionID = sessionID
    }

    var rootDirectory: URL {
        baseTemporaryDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    var sessionDirectory: URL {
        rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    func prepareDirectory() throws -> URL {
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        removeAbandonedSessionDirectories()
        return sessionDirectory
    }

    func isManagedFileURL(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == sessionDirectory.standardizedFileURL
    }

    @discardableResult
    func removeManagedFile(at url: URL) -> Bool {
        guard isManagedFileURL(url) else { return false }
        guard fileManager.fileExists(atPath: url.path) else { return true }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            Log.export.error("Unable to remove temporary batch export: \(error.localizedDescription)")
            return false
        }
    }

    private func removeAbandonedSessionDirectories() {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Log.export.error("Unable to inspect temporary batch exports: \(error.localizedDescription)")
            return
        }
        let currentDirectory = sessionDirectory.standardizedFileURL
        for entry in entries where entry.standardizedFileURL != currentDirectory {
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                let cocoaError = error as NSError
                guard cocoaError.domain != NSCocoaErrorDomain
                        || cocoaError.code != CocoaError.fileNoSuchFile.rawValue
                else { continue }
                Log.export.error("Unable to remove abandoned batch export session: \(error.localizedDescription)")
            }
        }
    }
}

final class BatchExportService {
    static let shared = BatchExportService()
    static let temporaryStorage = BatchExportTemporaryStorage(sessionID: UUID().uuidString)
    
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
            guard let totals = BatchExportFormatting.totals(for: completeRecords) else {
                throw BatchExportError.aggregateOutOfRange
            }
            try Self.validateCurrentRecords(completeRecords)

            let filename = Self.makeFilename(
                format: format,
                date: Date(),
                uniqueSuffix: String(UUID().uuidString.prefix(8))
            )
            let tempDirectory = try Self.temporaryStorage.prepareDirectory()
            let tempURL = tempDirectory.appendingPathComponent(filename)
            var shouldKeepFile = false
            defer {
                if !shouldKeepFile {
                    Self.removeTemporaryExport(at: tempURL)
                }
            }

            switch format {
            case .csv:
                try BatchExportCSVWriter.write(
                    records: completeRecords,
                    totals: totals,
                    options: options,
                    to: tempURL
                )
            case .excel:
                try BatchExportExcelWriter.write(records: completeRecords, options: options, to: tempURL)
            case .json:
                try BatchExportJSONWriter.write(
                    records: completeRecords,
                    totals: totals,
                    options: options,
                    to: tempURL
                )
            }

            try Task.checkCancellation()
            try Self.validateCurrentRecords(completeRecords)
            shouldKeepFile = true
            return ExportResult(
                url: tempURL,
                recordCount: completeRecords.count,
                totalYield: totals.totalYield,
                totalFruitCount: totals.totalFruitCount,
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

    static func makeFilename(
        format: ExportFormat,
        date: Date,
        uniqueSuffix: String,
        bundle: Bundle = .main
    ) -> String {
        let prefix = L10n.Export.filenamePrefix(in: bundle)
        let timestamp = filenameDateFormatter.string(from: date)
        return "\(prefix)_\(timestamp)_\(uniqueSuffix).\(format.fileExtension)"
    }

    @discardableResult
    static func removeTemporaryExport(at url: URL) -> Bool {
        temporaryStorage.removeManagedFile(at: url)
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
            // History rows always require source validation. Callers may also
            // supply synthetic records without a source for summary exports.
            if !record.requiresSourceValidation &&
                (!sidecarExists || !fileManager.fileExists(atPath: record.fileURL.path)) {
                continue
            }
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

enum BatchExportError: LocalizedError, Equatable {
    case noRecords
    case aggregateOutOfRange
    case inconsistentRecord
    
    var errorDescription: String? {
        switch self {
        case .noRecords: return L10n.Export.noRecords
        case .aggregateOutOfRange: return L10n.Export.aggregateOutOfRange
        case .inconsistentRecord: return "扫描结果文件不完整或已更新，请刷新历史记录后重试导出"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noRecords: return L10n.Export.noRecordsRecovery
        case .aggregateOutOfRange: return L10n.Export.aggregateOutOfRangeRecovery
        case .inconsistentRecord: return "请刷新扫描历史后重试导出"
        }
    }
}
