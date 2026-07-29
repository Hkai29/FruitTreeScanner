import SwiftUI

struct PointCloudSheet: View {
    @Environment(\.dismiss) var dismiss
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    @ObservedObject var historyStore = ScanHistoryStore.shared
    @State private var searchText = ""
    @State private var selectedFile: URL?

    init(
        initialFileURL: URL? = nil,
        onStartScan: (() -> Void)? = nil,
        onImportFile: (() -> Void)? = nil
    ) {
        _selectedFile = State(initialValue: initialFileURL)
        self.onStartScan = onStartScan
        self.onImportFile = onImportFile
    }

    private var effectiveSelectedFile: URL? {
        selectedFile ?? historyStore.scanFiles.first?.fileURL
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        PointCloudFileSelector(
                            records: historyStore.scanFiles,
                            selectedFile: effectiveSelectedFile,
                            searchText: $searchText,
                            onSelect: selectFile
                        )

                        PointCloudView(plyFileURL: effectiveSelectedFile)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(L10n.PointCloud.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                    .accessibilityLabel(L10n.PointCloud.closePreviewAccessibility)
                }
            }
        }
        .onAppear(perform: loadInitialSelection)
        .onChange(of: historyStore.scanFiles, perform: updateSelection)
    }

    private var emptyState: some View {
        DashboardSheetEmptyState(
            icon: "cube",
            imageName: "FeaturePointCloud",
            title: L10n.PointCloud.emptyTitle,
            message: L10n.PointCloud.emptyMessage,
            accent: Design.Colors.Dark.info,
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
