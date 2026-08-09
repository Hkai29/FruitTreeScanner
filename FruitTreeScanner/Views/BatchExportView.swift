import SwiftUI

struct BatchExportView: View {
    @Environment(\.dismiss) private var dismiss

    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    @ObservedObject var store = ScanHistoryStore.shared
    @ObservedObject var tagStore = TagStore.shared
    @State var selectedRecords: Set<String> = []
    @State var exportFormat: BatchExportService.ExportFormat = .csv
    @State var exportOptions = BatchExportService.ExportOptions()
    @State var exportedURL: URL?
    @State var isExporting = false
    @State var showError = false
    @State var errorMessage = ""
    @State var presentedSheet: BatchExportSheet?
    @State var exportTask: Task<Void, Never>?
    @State var exportGeneration = 0

    var exportableRecordIDs: Set<String> {
        BatchExportSelectionPolicy.exportableRecordIDs(from: store.scanFiles)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                BatchExportContentView(
                    records: store.scanFiles,
                    selectedRecords: selectedRecords,
                    exportFormat: $exportFormat,
                    exportOptions: $exportOptions,
                    exportedURL: exportedURL,
                    isExporting: isExporting,
                    onStartScan: onStartScan,
                    onImportFile: onImportFile,
                    onToggleSelection: toggleSelection,
                    onOptionsChanged: clearExportedFile,
                    onShareExport: showExportShareSheet,
                    onClearExport: clearExportedFile,
                    onPrimaryAction: handlePrimaryExportAction
                )
            }
            .navigationTitle(L10n.Export.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Export.close, action: close)
                        .accessibilityHint(L10n.Export.closeHint)
                        .accessibilityIdentifier("batchExport.navigation.close")
                }

                ToolbarItem(placement: .primaryAction) {
                    if !exportableRecordIDs.isEmpty {
                        Button(selectionActionTitle) {
                            toggleSelectAll()
                        }
                        .disabled(isExporting)
                    }
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url])
            }
        }
        .alert("导出错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear(perform: handleAppear)
        .onChange(of: store.scanFiles, perform: handleRecordsChanged)
        .onChange(of: tagStore.plots) { _ in
            handleExportSourceChanged()
        }
        .onChange(of: tagStore.assignments) { _ in
            handleExportSourceChanged()
        }
        .onDisappear(perform: handleDisappear)
    }

    private func close() {
        dismiss()
    }
}

enum BatchExportSheet: Identifiable {
    case share(URL)

    var id: String {
        switch self {
        case .share(let url):
            return "share-\(url.path)"
        }
    }
}
