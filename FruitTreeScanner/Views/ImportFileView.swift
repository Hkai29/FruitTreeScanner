// ImportFileView.swift
// 外部文件导入分析

import SwiftUI
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
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
    }
}
