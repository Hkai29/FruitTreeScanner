import SwiftUI

@MainActor
struct BatchExportView: View {
    @Environment(\.dismiss) private var dismiss

    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    @ObservedObject var store: ScanHistoryStore
    @ObservedObject var tagStore: TagStore
    @State var selectedRecords: Set<String> = []
    @State var exportFormat: BatchExportService.ExportFormat = .csv
    @State var exportOptions = BatchExportService.ExportOptions()
    @StateObject var workflow: BatchExportWorkflow
    @State var showShareError = false
    @State var presentedSheet: BatchExportSheet?

    init(
        onStartScan: (() -> Void)? = nil,
        onImportFile: (() -> Void)? = nil,
        store: ScanHistoryStore? = nil,
        tagStore: TagStore? = nil,
        exportedURL: URL? = nil,
        operations: BatchExportOperations = .production
    ) {
        self.init(
            onStartScan: onStartScan, onImportFile: onImportFile,
            store: store, tagStore: tagStore,
            workflow: BatchExportWorkflow(operations: operations, exportedURL: exportedURL)
        )
    }

    init(
        onStartScan: (() -> Void)? = nil,
        onImportFile: (() -> Void)? = nil,
        store: ScanHistoryStore? = nil,
        tagStore: TagStore? = nil,
        workflow: @autoclosure @escaping () -> BatchExportWorkflow
    ) {
        self.onStartScan = onStartScan
        self.onImportFile = onImportFile
        self.store = store ?? .shared
        self.tagStore = tagStore ?? .shared
        _workflow = StateObject(wrappedValue: workflow())
    }

    var exportedURL: URL? { workflow.exportedURL }
    var isExporting: Bool { workflow.isExporting }

    private var exportFailure: Binding<BatchExportFailurePresentation?> {
        Binding(
            get: { workflow.failure.map { BatchExportFailurePresentation(error: $0) } },
            set: { _ in workflow.dismissFailure() }
        )
    }

    var exportableRecordIDs: Set<String> {
        BatchExportSelectionPolicy.exportableRecordIDs(from: store.scanFiles)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
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
            .workspacePage()
            .navigationTitle(L10n.Export.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
        .preferredColorScheme(.light)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url]) { result in
                    handleShareCompletion(result, for: url)
                }
            }
        }
        .batchExportFailureAlert(failure: exportFailure, onRetry: performExport)
        .alert(L10n.Export.shareFailureTitle, isPresented: $showShareError) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.Export.shareFailureMessage)
        }
        .onChange(of: workflow.exportedURL) { url in
            presentedSheet = url.map(BatchExportSheet.share)
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

    func exportRequestReader() -> @MainActor () -> BatchExportRequestSnapshot {
        // Capture only the request's stores and State locations. Capturing this
        // View would retain its StateObject owner through the pending task.
        { [store, tagStore, selection = _selectedRecords, format = _exportFormat, options = _exportOptions] in
            Self.makeExportRequestSnapshot(
                records: store.scanFiles,
                selectedRecordIDs: selection.wrappedValue,
                format: format.wrappedValue,
                options: options.wrappedValue,
                plotNames: Self.plotNameByTreeID(tagStore: tagStore)
            )
        }
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
        case inconsistentRecord
        case outOfSpace
        case fileWrite
        case replayUnavailable
        case replayInvalidArchive
        case replayBudgetExceeded
        case replayAlgorithmMismatch
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
        case .inconsistentRecord:
            return BatchExportError.inconsistentRecord.recoverySuggestion ?? L10n.Export.genericFailureRecovery
        case .outOfSpace:
            return L10n.Export.outOfSpaceRecovery
        case .fileWrite:
            return L10n.Export.fileWriteRecovery
        case .replayUnavailable:
            return ScanReplayError.unavailable.localizedDescription
        case .replayInvalidArchive:
            return ScanReplayError.invalidArchive.localizedDescription
        case .replayBudgetExceeded:
            return ScanReplayError.budgetExceeded.localizedDescription
        case .replayAlgorithmMismatch:
            return ScanReplayError.algorithmMismatch.localizedDescription
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
        if let replayError = error as? ScanReplayError {
            switch replayError {
            case .unavailable: return .replayUnavailable
            case .invalidArchive: return .replayInvalidArchive
            case .budgetExceeded: return .replayBudgetExceeded
            case .algorithmMismatch: return .replayAlgorithmMismatch
            }
        }
        if let batchExportError = error as? BatchExportError {
            switch batchExportError {
            case .noRecords: return .noRecords
            case .aggregateOutOfRange: return .aggregateOutOfRange
            case .inconsistentRecord: return .inconsistentRecord
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
