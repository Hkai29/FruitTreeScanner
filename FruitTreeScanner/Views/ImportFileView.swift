// ImportFileView.swift
// 外部文件导入分析

import SwiftUI
import UniformTypeIdentifiers

struct ImportFileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var importStatus: ImportStatus = .idle
    @State private var importTask: Task<Void, Never>?
    @State private var isViewActive = false

    enum ImportStatus: Equatable {
        case idle
        case selecting
        case processing(String)
        case success(String)
        case error(String)

        var isSuccess: Bool {
            if case .success = self {
                return true
            }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    ImportHeader()
                    statusView
                    importButton
                    ImportRulesList()
                    Spacer(minLength: 0)
                }
                .padding(Design.Space.lg)
            }
            .navigationTitle("导入文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importStatus.isSuccess ? "完成" : "取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.plyFile],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isViewActive = true
        }
        .onDisappear {
            isViewActive = false
            importTask?.cancel()
            importTask = nil
        }
    }

    private var isProcessing: Bool {
        if case .processing = importStatus {
            return true
        }
        return false
    }

    private var statusView: some View {
        Group {
            switch importStatus {
            case .idle:
                ImportStatusPanel(
                    icon: "doc.badge.plus",
                    title: "等待选择 PLY 文件",
                    message: "支持 ASCII 和 Binary PLY，导入后会写入本机扫描记录。"
                )

            case .selecting:
                ImportStatusPanel(
                    icon: "folder",
                    title: "请选择文件",
                    message: "从文件应用中选择一个 .ply 点云文件。"
                )

            case .processing(let filename):
                ImportStatusPanel(
                    icon: "arrow.triangle.2.circlepath",
                    title: "正在处理",
                    message: filename,
                    showsProgress: true
                )

            case .success(let filename):
                ImportStatusPanel(
                    icon: "checkmark.circle.fill",
                    title: "导入成功",
                    message: "\(filename) 已添加到扫描记录，可继续导入或关闭此页。",
                    tint: Design.Colors.forest
                )

            case .error(let message):
                ImportStatusPanel(
                    icon: "exclamationmark.triangle.fill",
                    title: "导入失败",
                    message: message,
                    tint: Design.Colors.error
                )
            }
        }
    }

    private var importButton: some View {
        Button {
            isImporting = true
            importStatus = .selecting
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                Text(importStatus.isSuccess ? "继续导入 PLY 文件" : "选择 PLY 文件")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Design.Colors.Dark.bgDeep)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let fileURL = urls.first else {
                importStatus = .error("未选择文件")
                return
            }

            let fileName = fileURL.lastPathComponent
            importStatus = .processing(fileName)
            importTask?.cancel()
            importTask = Task.detached(priority: .utility) {
                do {
                    let importedName = try PLYImportService.importFile(fileURL)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .success(importedName)
                        ScanHistoryStore.shared.notifyRecordsUpdated()
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .error(error.localizedDescription)
                    }
                }
            }

        } catch {
            importStatus = .error(error.localizedDescription)
        }
    }

}

enum PLYImportService {
    nonisolated static func importFile(
        _ fileURL: URL,
        scansDirectory: URL? = nil
    ) throws -> String {
        guard fileURL.pathExtension.lowercased() == "ply" else {
            throw ImportError.unsupportedFormat
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        try Task.checkCancellation()

        let fileManager = FileManager.default
        let scansDir = scansDirectory ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("scans", isDirectory: true)

        try fileManager.createDirectory(at: scansDir, withIntermediateDirectories: true)

        let destURL = uniqueDestinationURL(for: fileURL, in: scansDir)
        let stagingURL = scansDir.appendingPathComponent(".import-\(UUID().uuidString).ply-partial")
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        try fileManager.copyItem(at: fileURL, to: stagingURL)
        try Task.checkCancellation()
        try validatePLYHeader(at: stagingURL)
        guard PLYParserHelper.parsePointCloudData(at: stagingURL) != nil else {
            throw ImportError.invalidPointCloud
        }
        try Task.checkCancellation()
        try fileManager.moveItem(at: stagingURL, to: destURL)

        return destURL.lastPathComponent
    }

    nonisolated static func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = TreeIdentifierPolicy.safeFileComponent(from: baseName)
        var candidate = directory.appendingPathComponent("\(safeBaseName).ply")

        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let timestamp = importTimestamp()
        candidate = directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp).ply")

        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let shortID = UUID().uuidString.prefix(6)
        return directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp)_\(shortID).ply")
    }

    nonisolated static func validatePLYHeader(at fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let prefix = try handle.read(upToCount: PLYParserHelper.maximumHeaderSize + 1) ?? Data()
        let terminator = PLYParserHelper.headerEndRange(in: prefix)
        guard let terminator,
              terminator.upperBound <= PLYParserHelper.maximumHeaderSize,
              let header = String(data: prefix[..<terminator.upperBound], encoding: .utf8)
        else {
            throw ImportError.invalidPLY
        }

        let lines = header
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first == "ply",
              PLYParserHelper.parsePointCloudHeader(lines) != nil
        else {
            throw ImportError.invalidPLY
        }
    }

    nonisolated static func importTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case invalidPLY
        case invalidPointCloud

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "当前导入记录只支持 PLY 点云文件"
            case .invalidPLY:
                return "文件不是有效的 PLY 点云"
            case .invalidPointCloud:
                return "PLY 点云数据不完整或当前无法读取"
            }
        }
    }
}

// MARK: - UTType Extensions

extension UTType {
    static let plyFile = UTType(filenameExtension: "ply") ?? .data
}
