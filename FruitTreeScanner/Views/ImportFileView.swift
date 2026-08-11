// ImportFileView.swift
// 外部文件导入分析

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportFileView: View {
    @Environment(\.dismiss) private var dismiss
    @State var isImporting = false
    @State var importStatus: ImportStatus = .idle
    @State var importTask: Task<Void, Never>?
    @State var isViewActive = false

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ImportFileContentView(
                    status: importStatus,
                    isProcessing: isProcessing,
                    onImportTap: beginImportSelection
                )
            }
            .navigationTitle(L10n.Import.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        .preferredColorScheme(.dark)
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
    }
}
