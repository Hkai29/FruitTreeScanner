// ScanHistoryView.swift
// 扫描历史列表 - 自然有机风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = ScanHistoryText.title
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
                    title: ScanHistoryText.emptyTitle,
                    message: ScanHistoryText.emptyMessage,
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
        .navigationTitle(NSLocalizedString(customTitle, value: customTitle, comment: "Scan history title"))
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
                    .accessibilityLabel(ScanHistoryText.moreHistoryActions)
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

enum ScanHistoryText {
    static let title = localized("history.title", fallback: "扫描历史")
    static let headerTitle = localized("history.header.title", fallback: "扫描记录")
    static let headerSubtitle = localized(
        "history.header.subtitle",
        fallback: "按时间、地块和状态查看所有扫描文件。"
    )
    static let emptyTitle = localized("history.empty.title", fallback: "暂无扫描记录")
    static let emptyMessage = localized(
        "history.empty.message",
        fallback: "完成扫描或导入 PLY 后，点云文件、果数和产量会按时间保存在这里。"
    )
    static let filteredEmptyTitle = localized(
        "history.filtered_empty.title",
        fallback: "没有符合筛选的记录"
    )
    static let filteredEmptyMessage = localized(
        "history.filtered_empty.message",
        fallback: "切换地块或状态筛选后再查看。"
    )
    static let startScan = localized("history.action.start_scan", fallback: "开始扫描")
    static let importPLY = localized("history.action.import_ply", fallback: "导入 PLY")
    static let allPlots = localized("history.filter.all_plots", fallback: "全部地块")
    static let allStatuses = localized("history.filter.all_statuses", fallback: "全部状态")
    static let plot = localized("history.filter.plot", fallback: "地块")
    static let status = localized("history.filter.status", fallback: "状态")
    static let clearAll = localized("history.action.clear_all", fallback: "清空全部")
    static let preview = localized("history.action.preview", fallback: "预览点云")
    static let rescan = localized("history.action.rescan", fallback: "复扫这棵")
    static let markReview = localized("history.action.mark_review", fallback: "标记待复核")
    static let share = localized("history.action.share", fallback: "分享点云")
    static let deleteRecord = localized("history.action.delete", fallback: "删除记录")
    static let moreActions = localized("history.action.more", fallback: "更多操作")
    static let moreHistoryActions = localized(
        "history.action.more_history",
        fallback: "更多历史记录操作"
    )
    static let previewHint = localized(
        "history.action.preview_hint",
        fallback: "打开这条记录的点云预览。"
    )
    static let cancel = localized("common.cancel", fallback: "取消")
    static let delete = localized("common.delete", fallback: "删除")
    static let deleteConfirmationTitle = localized(
        "history.delete.confirmation_title",
        fallback: "删除扫描记录"
    )
    static let deleteConfirmationMessage = localized(
        "history.delete.confirmation_message",
        fallback: "将删除这条记录关联的 PLY 点云、CSV 和结果文件。"
    )
    static let clearConfirmationTitle = localized(
        "history.clear.confirmation_title",
        fallback: "清空全部扫描记录"
    )
    static let clearConfirmationMessage = localized(
        "history.clear.confirmation_message",
        fallback: "将删除当前所有扫描记录及其关联文件，此操作无法撤销。"
    )
    static let clear = localized("history.clear.action", fallback: "清空")
    static let deleteFailureTitle = localized(
        "history.delete.failure_title",
        fallback: "未能完全删除"
    )
    static let deleteLater = localized("history.delete.later", fallback: "稍后处理")
    static let retryDelete = localized("history.delete.retry", fallback: "重试删除")
    static let complete = localized("history.record.complete", fallback: "结果完整")
    static let incomplete = localized("history.record.incomplete", fallback: "待恢复")
    static let invalid = localized("history.record.invalid", fallback: "结果损坏")
    static let missingResult = localized(
        "history.record.reason.missing_result",
        fallback: "缺少结果文件"
    )
    static let unreadableJSON = localized(
        "history.record.reason.unreadable_json",
        fallback: "JSON 无法读取"
    )
    static let unreadableCSV = localized(
        "history.record.reason.unreadable_csv",
        fallback: "CSV 无法读取"
    )
    static let revisionMismatch = localized(
        "history.record.reason.revision_mismatch",
        fallback: "文件版本不一致"
    )
    static let incompleteUnknown = localized(
        "history.record.reason.incomplete_unknown",
        fallback: "结果尚未完整保存"
    )
    static let invalidUnknown = localized(
        "history.record.reason.invalid_unknown",
        fallback: "结果文件无法读取"
    )
    static let unknownSize = localized("history.record.unknown_size", fallback: "未知大小")

    static func fruitCount(_ count: Int) -> String {
        let key = count == 1
            ? "history.record.fruit_count_one_format"
            : "history.record.fruit_count_many_format"
        return String(
            format: localized(key, fallback: "%d 个"),
            count
        )
    }

    static func yield(_ kilograms: Float) -> String {
        String(
            format: localized("history.record.yield_format", fallback: "%.1f kg"),
            kilograms
        )
    }

    static func fileSize(megabytes: Double) -> String {
        String(
            format: localized("history.record.file_size_format", fallback: "%.1f MB"),
            megabytes
        )
    }

    static func statusName(_ status: ScanStatus) -> String {
        switch status {
        case .notScanned:
            return localized("history.scan_status.not_scanned", fallback: "未扫描")
        case .scanned:
            return localized("history.scan_status.scanned", fallback: "已扫描")
        case .reviewing:
            return localized("history.scan_status.reviewing", fallback: "复查中")
        case .completed:
            return localized("history.scan_status.completed", fallback: "已完成")
        }
    }

    static func deleteFailureMessage(count: Int) -> String {
        let format = localized(
            count == 1 ? "history.delete.failure_message_one" : "history.delete.failure_message_many",
            fallback: count == 1
                ? "这条记录仍在本机，可能有文件正在使用。请重试或稍后再试。"
                : "仍有 %d 条记录留在本机，可能有文件正在使用。请重试或稍后再试。"
        )
        return count == 1 ? format : String(format: format, count)
    }

    private static func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
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
