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
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    @State private var presentedSheet: ScanHistorySheet?
    @State private var recordPendingDeletion: ScanFileRecord?
    @State private var showClearAllConfirmation = false
    @State private var deletionAttempt: ScanHistoryDeletionAttempt?
    @State private var failedDeletionRecords: [ScanFileRecord] = []
    @State private var showDeletionFailure = false

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
        }
        .navigationTitle(NSLocalizedString(customTitle, value: customTitle, comment: "Scan history title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyStore.scanFiles.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Label(ScanHistoryText.clearAll, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Design.Colors.forest)
                    }
                    .accessibilityLabel(ScanHistoryText.moreHistoryActions)
                }
            }
        }
        .onAppear { historyStore.loadRecords() }
        .refreshable { historyStore.loadRecords() }
        .onReceive(NotificationCenter.default.publisher(for: ScanHistoryStore.didUpdateNotification)) { _ in
            resolveDeletionAttempt()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url])
            case .pointCloud(let url):
                PointCloudSheet(initialFileURL: url)
            }
        }
        .alert(ScanHistoryText.deleteConfirmationTitle, isPresented: deleteRecordAlertBinding) {
            Button(ScanHistoryText.cancel, role: .cancel) {
                recordPendingDeletion = nil
            }
            Button(ScanHistoryText.delete, role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            Text(ScanHistoryText.deleteConfirmationMessage)
        }
        .alert(ScanHistoryText.clearConfirmationTitle, isPresented: $showClearAllConfirmation) {
            Button(ScanHistoryText.cancel, role: .cancel) {}
            Button(ScanHistoryText.clear, role: .destructive) {
                beginDeleting(historyStore.scanFiles)
            }
        } message: {
            Text(ScanHistoryText.clearConfirmationMessage)
        }
        .alert(ScanHistoryText.deleteFailureTitle, isPresented: $showDeletionFailure) {
            Button(ScanHistoryText.deleteLater, role: .cancel) {
                failedDeletionRecords = []
            }
            Button(ScanHistoryText.retryDelete) {
                retryFailedDeletion()
            }
        } message: {
            Text(ScanHistoryText.deleteFailureMessage(count: failedDeletionRecords.count))
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

    private func deletePendingRecord() {
        guard let record = recordPendingDeletion else { return }
        recordPendingDeletion = nil
        beginDeleting([record])
    }

    private func beginDeleting(_ records: [ScanFileRecord]) {
        guard !records.isEmpty else { return }
        deletionAttempt = ScanHistoryDeletionAttempt(records: records)
        historyStore.deleteRecords(records)
    }

    private func resolveDeletionAttempt() {
        guard let deletionAttempt else { return }
        let remaining = deletionAttempt.remainingRecords(in: historyStore.scanFiles)
        self.deletionAttempt = nil
        guard !remaining.isEmpty else {
            failedDeletionRecords = []
            return
        }
        failedDeletionRecords = remaining
        showDeletionFailure = true
    }

    private func retryFailedDeletion() {
        let records = failedDeletionRecords
        failedDeletionRecords = []
        beginDeleting(records)
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

struct ScanHistoryDeletionAttempt: Equatable {
    private let recordIDs: Set<String>

    init(records: [ScanFileRecord]) {
        recordIDs = Set(records.map(\.id))
    }

    func remainingRecords(in records: [ScanFileRecord]) -> [ScanFileRecord] {
        records.filter { recordIDs.contains($0.id) }
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
