// ImportFileView.swift
// 外部文件导入分析。
//
// 一次导入一个 PLY 点云：状态、真实失败原因与成功结果全部来自既有导入实现。

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportFileView: View {
    @Environment(\.dismiss) private var dismiss
    @State var isImporting = false
    @State var importStatus: ImportStatus = .idle
    @State var importTask: Task<Void, Never>?
    @State var isViewActive = false
    let operations: ScanImportOperations

    @MainActor
    init(operations: ScanImportOperations? = nil) {
        self.operations = operations ?? .production(repository: .shared, historyStore: .shared)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ImportFileContentView(
                    status: importStatus,
                    isProcessing: isProcessing,
                    onImportTap: beginImportSelection
                )
            }
            .workspacePage()
            .navigationTitle(L10n.Import.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importStatus.isSuccess ? L10n.Common.done : L10n.Common.cancel) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.plyFile],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: isImporting) { isPresented in
                guard !isPresented else { return }
                importStatus = importStatus.afterImporterDismissal
            }
            .onChange(of: importStatus) { status in
                guard let announcement = status.accessibilityAnnouncement else { return }
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
    }
}
