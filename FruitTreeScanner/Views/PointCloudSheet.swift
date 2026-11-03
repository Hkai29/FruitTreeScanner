import SwiftUI

struct PointCloudSheet: View {
    @Environment(\.dismiss) var dismiss
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    @ObservedObject var historyStore: ScanHistoryStore
    @State private var searchText = ""
    @State private var selectedFile: URL?
    @State private var showsFileSelection = false

    @MainActor
    init(
        initialFileURL: URL? = nil,
        onStartScan: (() -> Void)? = nil,
        onImportFile: (() -> Void)? = nil,
        historyStore: ScanHistoryStore? = nil
    ) {
        _selectedFile = State(initialValue: initialFileURL)
        self.onStartScan = onStartScan
        self.onImportFile = onImportFile
        self.historyStore = historyStore ?? .shared
    }

    private var effectiveSelectedFile: URL? {
        selectedFile ?? historyStore.scanFiles.first?.fileURL
    }

    /// 当前点云对应的档案记录。用于判定并标注点云来源。
    private var selectedRecord: ScanFileRecord? {
        guard let effectiveSelectedFile else { return nil }
        return historyStore.scanFiles.first { $0.fileURL == effectiveSelectedFile }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Workspace.background.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    ScrollView {
                        emptyState
                    }
                } else {
                    VStack(spacing: 0) {
                        PointCloudView(
                            plyFileURL: effectiveSelectedFile, onClose: { dismiss() },
                            treeID: selectedRecord?.treeID,
                            provenance: PointCloudProvenance.resolve(record: selectedRecord),
                            onChooseArchive: { showsFileSelection.toggle() }
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(L10n.PointCloud.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Design.Colors.Workspace.secondary)
                    }
                    .accessibilityLabel(L10n.PointCloud.closePreviewAccessibility)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: loadInitialSelection)
        .onChange(of: historyStore.scanFiles, perform: updateSelection)
        .sheet(isPresented: $showsFileSelection) {
            NavigationView {
                PointCloudFileSelector(
                    records: historyStore.scanFiles,
                    selectedFile: effectiveSelectedFile,
                    searchText: $searchText,
                    onSelect: selectFile
                )
                .navigationTitle(WorkspaceText.chooseArchive)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.Common.done) { showsFileSelection = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
            .preferredColorScheme(.light)
        }
    }

    private var emptyState: some View {
        DashboardSheetEmptyState(
            icon: "cube",
            imageName: "FeaturePointCloud",
            title: L10n.PointCloud.emptyTitle,
            message: L10n.PointCloud.emptyMessage,
            accent: Design.Colors.Workspace.information,
            primaryAction: action(title: L10n.PointCloud.newScan, icon: "viewfinder", handler: onStartScan),
            secondaryAction: action(title: L10n.PointCloud.importPLY, icon: "square.and.arrow.down", handler: onImportFile)
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }

    private func selectFile(_ url: URL) {
        selectedFile = url
        showsFileSelection = false
    }

    private func loadInitialSelection() {
        historyStore.loadRecords()
        if selectedFile == nil, let first = historyStore.scanFiles.first {
            selectedFile = first.fileURL
        }
    }

    private func updateSelection(_ records: [ScanFileRecord]) {
        if selectedFile == nil, let first = records.first {
            selectedFile = first.fileURL
        } else if let selectedFile, !records.contains(where: { $0.fileURL == selectedFile }) {
            self.selectedFile = records.first?.fileURL
        }
    }
}
