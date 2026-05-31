// ImportFileView.swift
// 外部文件导入分析

import SwiftUI
import UniformTypeIdentifiers

struct ImportFileView: View {
    @Environment(\.dismiss) var dismiss
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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    // 标题区域
                    VStack(spacing: 16) {
                        Image(systemName: "folder.open")
                            .font(.system(size: 60, weight: .light))
                            .foregroundColor(Design.Colors.harvest)

                        Text("导入外部文件")
                            .font(Design.Typography.headline)
                            .foregroundColor(Design.Colors.Dark.textPrimary)

                        Text("支持 PLY（ASCII/Binary）点云文件")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }

                    // 状态显示
                    statusView

                    // 导入按钮
                    Button {
                        isImporting = true
                        importStatus = .selecting
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Design.Colors.harvest)
                                .frame(height: 50)
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("选择文件")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.6 : 1)

                    VStack(spacing: 10) {
                        Label("导入后会出现在扫描记录", systemImage: "clock.arrow.circlepath")
                        Label("保留可读取的扫描元数据", systemImage: "doc.badge.gearshape")
                        Label("同名文件会自动生成新副本", systemImage: "square.on.square")
                    }
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .multilineTextAlignment(.center)
                }
                .padding(Design.Space.lg)
            }
            .navigationTitle("导入文件")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
                EmptyView()

            case .selecting:
                Text("请选择文件...")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

            case .processing(let filename):
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在处理: \(filename)")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

            case .success(let filename):
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(Design.Colors.forest)
                    Text("导入成功: \(filename)")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.Dark.glow)
                    Text("已添加到扫描记录")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(Design.Colors.error)
                    Text("导入失败")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(message)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
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
                    let importedName = try Self.importFile(fileURL)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .success(importedName)
                        ScanHistoryStore.shared.notifyRecordsUpdated()
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        dismiss()
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

    nonisolated private static func importFile(_ fileURL: URL) throws -> String {
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

        let scansDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("scans")

        try FileManager.default.createDirectory(at: scansDir, withIntermediateDirectories: true)

        let destURL = uniqueDestinationURL(for: fileURL, in: scansDir)
        try FileManager.default.copyItem(at: fileURL, to: destURL)
        try Task.checkCancellation()

        try validatePLYHeader(at: destURL)
        _ = PLYParserHelper.parsePLYFile(at: destURL)

        return destURL.lastPathComponent
    }

    nonisolated private static func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBaseName = baseName.isEmpty ? "ImportedScan" : baseName
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)

        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let timestamp = importTimestamp()
        candidate = directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp).\(ext)")

        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let shortID = UUID().uuidString.prefix(6)
        return directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp)_\(shortID).\(ext)")
    }

    nonisolated private static func validatePLYHeader(at fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let headerData = try handle.read(upToCount: 3) ?? Data()
        guard String(data: headerData, encoding: .ascii) == "ply" else {
            throw ImportError.invalidPLY
        }
    }

    nonisolated private static func importTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private enum ImportError: LocalizedError {
        case unsupportedFormat
        case invalidPLY

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "当前导入记录只支持 PLY 点云文件"
            case .invalidPLY:
                return "文件不是有效的 PLY 点云"
            }
        }
    }
}

// MARK: - UTType Extensions

extension UTType {
    static let plyFile = UTType(filenameExtension: "ply") ?? .data
}

#Preview {
    NavigationStack {
        ImportFileView()
    }
}
