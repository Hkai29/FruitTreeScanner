// ScanHistoryView.swift
// 扫描历史列表 - 自然有机风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = "扫描历史"
    var onStartScan: (() -> Void)? = nil
    var onRescanTree: ((String) -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @StateObject private var deletionController = ScanHistoryDeletionController()
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    @State private var presentedSheet: ScanHistorySheet?
    @State private var recordPendingDeletion: ScanFileRecord?
    @State private var showClearAllConfirmation = false
    @State private var deletionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if historyStore.scanFiles.isEmpty {
                ScanHistoryEmptyState(
                    title: "暂无扫描记录",
                    message: "完成扫描或导入 PLY 后，点云文件、果数和产量会按时间保存在这里。",
                    onStartScan: onStartScan,
                    onImportFile: onImportFile
                )
            } else {
                ScanHistoryContentView(
                    filteredScans: filteredScans,
                    selectedPlotId: $selectedPlotId,
                    selectedStatus: $selectedStatus,
                    tagStore: tagStore,
                    onPreview: preview,
                    onShare: share,
                    onRescan: rescan,
                    onMarkReview: markReview,
                    onDelete: confirmDelete
                )
            }

            if deletionController.isDeleting {
                ScanHistoryDeletionProgressOverlay()
            }
        }
        .navigationTitle(customTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(deletionController.isDeleting)
        .interactiveDismissDisabled(deletionController.isDeleting)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyStore.scanFiles.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Label(ScanHistoryDeletionCopy.clearMenu, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Design.Colors.forest)
                    }
                    .disabled(deletionController.isDeleting)
                }
            }
        }
        .onAppear { historyStore.loadRecords() }
        .onDisappear(perform: cancelDeletionPresentation)
        .refreshable { historyStore.loadRecords() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url])
            case .pointCloud(let url):
                PointCloudSheet(initialFileURL: url)
            }
        }
        .alert(ScanHistoryDeletionCopy.recordConfirmationTitle, isPresented: deleteRecordAlertBinding) {
            Button(ScanHistoryDeletionCopy.cancel, role: .cancel) {
                recordPendingDeletion = nil
            }
            Button(ScanHistoryDeletionCopy.delete, role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            Text(ScanHistoryDeletionCopy.recordConfirmationMessage)
        }
        .alert(ScanHistoryDeletionCopy.clearConfirmationTitle, isPresented: $showClearAllConfirmation) {
            Button(ScanHistoryDeletionCopy.cancel, role: .cancel) {}
            Button(ScanHistoryDeletionCopy.clear, role: .destructive) {
                startDeletion(historyStore.scanFiles)
            }
        } message: {
            Text(ScanHistoryDeletionCopy.clearConfirmationMessage)
        }
        .alert(ScanHistoryDeletionCopy.failureTitle, isPresented: deletionFailureAlertBinding) {
            Button(ScanHistoryDeletionCopy.dismiss, role: .cancel) {
                deletionController.dismissFailure()
            }
            Button(ScanHistoryDeletionCopy.retry) {
                retryFailedDeletion()
            }
        } message: {
            Text(deletionFailureMessage)
        }
    }

    // MARK: - Filtered Scans
    private var filteredScans: [ScanFileRecord] {
        historyStore.scanFiles.filter { record in
            let assignment = tagStore.getAssignment(treeId: record.treeID)
            if let plotId = selectedPlotId, assignment?.plotId != plotId { return false }
            if let status = selectedStatus, assignment?.status != status { return false }
            return true
        }
    }

    private var deleteRecordAlertBinding: Binding<Bool> {
        Binding(
            get: { recordPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    recordPendingDeletion = nil
                }
            }
        )
    }

    private var deletionFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { deletionController.failure != nil },
            set: { isPresented in
                if !isPresented {
                    deletionController.dismissFailure()
                }
            }
        )
    }

    private var deletionFailureMessage: String {
        guard let failure = deletionController.failure else { return "" }
        return ScanHistoryDeletionCopy.failureMessage(for: failure)
    }

    private func deletePendingRecord() {
        guard let record = recordPendingDeletion else { return }
        recordPendingDeletion = nil
        startDeletion([record])
    }

    private func startDeletion(_ records: [ScanFileRecord]) {
        guard !records.isEmpty, !deletionController.isDeleting else { return }
        deletionTask = Task {
            await deletionController.delete(records)
            deletionTask = nil
        }
    }

    private func retryFailedDeletion() {
        guard let records = deletionController.failure?.recordsToRetry else { return }
        startDeletion(records)
    }

    private func cancelDeletionPresentation() {
        deletionController.invalidate()
        deletionTask?.cancel()
        deletionTask = nil
    }

    private func preview(_ record: ScanFileRecord) {
        presentedSheet = .pointCloud(record.fileURL)
    }

    private func share(_ record: ScanFileRecord) {
        presentedSheet = .share(record.fileURL)
    }

    private func confirmDelete(_ record: ScanFileRecord) {
        recordPendingDeletion = record
    }

    private func rescan(_ record: ScanFileRecord) {
        if let onRescanTree {
            onRescanTree(record.treeID)
        } else {
            onStartScan?()
        }
    }

    private func markReview(_ record: ScanFileRecord) {
        if let existing = tagStore.getAssignment(treeId: record.treeID) {
            tagStore.createOrUpdateAssignment(
                treeId: record.treeID,
                plotId: existing.plotId,
                tagIds: existing.tagIds,
                status: .reviewing
            )
        } else {
            tagStore.createOrUpdateAssignment(
                treeId: record.treeID,
                plotId: nil,
                tagIds: [],
                status: .reviewing
            )
        }
    }

}

struct ScanHistoryDeletionFailure: Equatable {
    let recordsToRetry: [ScanFileRecord]
    let residualKinds: [ScanHistoryDeletionArtifact.Kind]
    let failedRecordCount: Int
}

@MainActor
final class ScanHistoryDeletionController: ObservableObject {
    typealias DeleteRecords = ([ScanFileRecord]) async -> ScanHistoryBatchDeletionResult

    private enum State: Equatable {
        case idle
        case deleting
        case failed(ScanHistoryDeletionFailure)
    }

    @Published private var state: State = .idle
    private let deleteRecords: DeleteRecords
    private var generation = 0

    init(
        deleteRecords: @escaping DeleteRecords = { records in
            await ScanHistoryStore.shared.deleteRecordsWithResult(records)
        }
    ) {
        self.deleteRecords = deleteRecords
    }

    var isDeleting: Bool {
        state == .deleting
    }

    var failure: ScanHistoryDeletionFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }

    func delete(_ records: [ScanFileRecord]) async {
        guard !records.isEmpty, !isDeleting else { return }
        generation += 1
        let operationGeneration = generation
        state = .deleting

        let result = await deleteRecords(records)
        guard generation == operationGeneration else { return }
        guard !Task.isCancelled else {
            state = .idle
            return
        }

        let failedResults = result.records.filter { !$0.isComplete }
        guard !failedResults.isEmpty else {
            state = .idle
            return
        }

        let failedRecordIDs = Set(failedResults.map(\.recordID))
        let recordsToRetry = records.filter { failedRecordIDs.contains($0.id) }
        var residualKinds: [ScanHistoryDeletionArtifact.Kind] = []
        for kind in failedResults.flatMap(\.residualArtifacts).map(\.kind)
        where !residualKinds.contains(kind) {
            residualKinds.append(kind)
        }
        state = .failed(
            ScanHistoryDeletionFailure(
                recordsToRetry: recordsToRetry,
                residualKinds: residualKinds,
                failedRecordCount: failedResults.count
            )
        )
    }

    func retry() async {
        guard let records = failure?.recordsToRetry else { return }
        await delete(records)
    }

    func dismissFailure() {
        guard failure != nil else { return }
        state = .idle
    }

    func invalidate() {
        generation += 1
        state = .idle
    }
}

private struct ScanHistoryDeletionProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                ProgressView()
                    .tint(Design.Colors.harvest)

                Text(ScanHistoryDeletionCopy.progress)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .fill(Design.Colors.Dark.hudBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScanHistoryDeletionCopy.progress)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("history.deletion.progress")
        .zIndex(1)
    }
}

private enum ScanHistoryDeletionCopy {
    static let recordConfirmationTitle = localized(
        "history.delete.record.title",
        value: "删除扫描记录"
    )
    static let recordConfirmationMessage = localized(
        "history.delete.record.message",
        value: "将删除这条记录关联的 PLY 点云、CSV、结果 JSON 和完成清单。"
    )
    static let clearConfirmationTitle = localized(
        "history.delete.all.title",
        value: "清空全部扫描记录"
    )
    static let clearConfirmationMessage = localized(
        "history.delete.all.message",
        value: "将删除当前所有扫描记录及其关联文件，此操作无法撤销。"
    )
    static let cancel = localized("common.cancel", value: "取消")
    static let delete = localized("common.delete", value: "删除")
    static let clearMenu = localized("history.delete.all.menu", value: "清空全部")
    static let clear = localized("history.delete.all.action", value: "清空")
    static let progress = localized("history.delete.progress", value: "正在删除关联文件…")
    static let failureTitle = localized("history.delete.failure.title", value: "部分文件未删除")
    static let retry = localized("history.delete.retry", value: "重试")
    static let dismiss = localized("history.delete.dismiss", value: "关闭")

    static func failureMessage(for failure: ScanHistoryDeletionFailure) -> String {
        let artifacts = failure.residualKinds
            .map(artifactName(for:))
            .joined(separator: localized("history.delete.artifact.separator", value: "、"))
        if failure.failedRecordCount == 1 {
            let format = localized(
                "history.delete.failure.message.one",
                value: "仍有 1 条记录的这些文件留在本机：%@。请重试。"
            )
            return String.localizedStringWithFormat(format, artifacts)
        }
        let format = localized(
            "history.delete.failure.message.many",
            value: "仍有 %d 条记录的这些文件留在本机：%@。请重试。"
        )
        return String.localizedStringWithFormat(format, failure.failedRecordCount, artifacts)
    }

    private static func artifactName(for kind: ScanHistoryDeletionArtifact.Kind) -> String {
        switch kind {
        case .pointCloud:
            return localized("history.delete.artifact.point_cloud", value: "PLY 点云")
        case .csv:
            return localized("history.delete.artifact.csv", value: "CSV")
        case .resultJSON:
            return localized("history.delete.artifact.result_json", value: "结果 JSON")
        case .completionManifest:
            return localized("history.delete.artifact.completion_manifest", value: "完成清单")
        }
    }

    private static func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}

private enum ScanHistorySheet: Identifiable {
    case share(URL)
    case pointCloud(URL)

    var id: String {
        switch self {
        case .share(let url):
            return "share-\(url.path)"
        case .pointCloud(let url):
            return "point-cloud-\(url.path)"
        }
    }
}
