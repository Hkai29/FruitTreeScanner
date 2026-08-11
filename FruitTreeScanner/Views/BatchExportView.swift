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
    @State var exportFailure: BatchExportFailurePresentation?
    @State var showShareError = false
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
                        .accessibilityHint(selectionActionHint)
                        .accessibilityIdentifier(selectionActionAccessibilityIdentifier)
                    }
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url]) { result in
                    handleShareCompletion(result, for: url)
                }
            }
        }
        .batchExportFailureAlert(failure: $exportFailure, onRetry: performExport)
        .alert(L10n.Export.shareFailureTitle, isPresented: $showShareError) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.Export.shareFailureMessage)
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

    private var hasSelectedAllExportableRecords: Bool {
        selectedRecords == exportableRecordIDs
    }

    private var selectionActionTitle: String {
        hasSelectedAllExportableRecords ? L10n.Export.deselectAll : L10n.Export.selectAll
    }

    private var selectionActionHint: String {
        hasSelectedAllExportableRecords ? L10n.Export.deselectAllHint : L10n.Export.selectAllHint
    }

    private var selectionActionAccessibilityIdentifier: String {
        hasSelectedAllExportableRecords
            ? "batchExport.navigation.deselectAll"
            : "batchExport.navigation.selectAll"
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

struct BatchExportFailurePresentation {
    enum Kind: Equatable {
        case noRecords
        case aggregateOutOfRange
        case outOfSpace
        case fileWrite
        case generic
    }

    let kind: Kind

    init(error: Error) {
        kind = Self.kind(for: error)
    }

    var message: String {
        switch kind {
        case .noRecords:
            return L10n.Export.noRecordsRecovery
        case .aggregateOutOfRange:
            return L10n.Export.aggregateOutOfRangeRecovery
        case .outOfSpace:
            return L10n.Export.outOfSpaceRecovery
        case .fileWrite:
            return L10n.Export.fileWriteRecovery
        case .generic:
            return L10n.Export.genericFailureRecovery
        }
    }

    private static let fileWriteErrorCodes: Set<Int> = [
        CocoaError.Code.fileWriteUnknown.rawValue,
        CocoaError.Code.fileWriteNoPermission.rawValue,
        CocoaError.Code.fileWriteInvalidFileName.rawValue,
        CocoaError.Code.fileWriteFileExists.rawValue,
        CocoaError.Code.fileWriteInapplicableStringEncoding.rawValue,
        CocoaError.Code.fileWriteUnsupportedScheme.rawValue,
        CocoaError.Code.fileWriteVolumeReadOnly.rawValue
    ]

    private static func kind(for error: Error) -> Kind {
        if let batchExportError = error as? BatchExportError {
            switch batchExportError {
            case .noRecords: return .noRecords
            case .aggregateOutOfRange: return .aggregateOutOfRange
            }
        }

        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        for candidate in [nsError, underlyingError].compactMap({ $0 }) {
            guard candidate.domain == NSCocoaErrorDomain else { continue }
            if candidate.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
                return .outOfSpace
            }
            if fileWriteErrorCodes.contains(candidate.code) {
                return .fileWrite
            }
        }
        return .generic
    }
}

struct BatchExportFailureAlertModifier: ViewModifier {
    @Binding var failure: BatchExportFailurePresentation?
    let onRetry: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            L10n.Export.failureTitle,
            isPresented: isPresented,
            presenting: failure
        ) { _ in
            Button(L10n.Export.failureCancel, role: .cancel) {
                failure = nil
            }
            .accessibilityIdentifier("batchExport.failure.cancel")

            Button(L10n.Export.failureRetry) {
                failure = nil
                onRetry()
            }
            .accessibilityIdentifier("batchExport.failure.retry")
        } message: {
            Text($0.message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { newValue in
                if !newValue {
                    failure = nil
                }
            }
        )
    }
}

extension View {
    func batchExportFailureAlert(
        failure: Binding<BatchExportFailurePresentation?>,
        onRetry: @escaping () -> Void
    ) -> some View {
        modifier(BatchExportFailureAlertModifier(failure: failure, onRetry: onRetry))
    }
}
