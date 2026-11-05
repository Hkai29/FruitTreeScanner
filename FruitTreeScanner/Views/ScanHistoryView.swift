// ScanHistoryView.swift
// 扫描历史列表：档案行的完整性与恢复入口必须可见

import SwiftUI

/// 返回档案列表时要放回哪一条。
///
/// 焦点与滚动锚点用**同一份**决定：要么是刚才打开的那一条，要么什么都不放回。
/// 绝不悄悄换成另一条 —— 尤其是同一棵树的另一份存档。
enum ScanHistoryRestoreTarget: Equatable {
    case restore(String)
    case none

    /// 决定：刚打开的那一条还在，就放回那一条；不在了，就什么都不放回。
    static func resolve(openedRecordID: String?, availableRecordIDs: [String]) -> ScanHistoryRestoreTarget {
        guard let openedRecordID, availableRecordIDs.contains(openedRecordID) else { return .none }
        return .restore(openedRecordID)
    }
}

struct ScanHistoryView: View {
    var customTitle: String = L10n.History.navigationTitle
    var onStartScan: (() -> Void)? = nil
    var onRescanTree: ((String) -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    @ObservedObject var historyStore: ScanHistoryStore
    @ObservedObject private var tagStore: TagStore
    @StateObject private var deletionController: ScanHistoryDeletionController
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    /// 当前搜索词（树号或存档编号）。
    ///
    /// 它是这一页的**状态**：进详情再返回，搜索词还在（与地块/状态筛选同一性质）。
    @State private var searchQuery: String = ""
    @State private var presentedSheet: ScanHistorySheet?
    /// 正在查看的归档（按存档身份定位，不是树号）。
    @State private var openedRecord: ScanFileRecord?
    /// 详情是否处于展示中。与 payload 分开：弹出动画期间 payload 不能被清空，
    /// 否则详情会在退场动画里变成空视图。
    @State private var isDetailPresented = false
    /// 上一次查看过的存档身份：返回后仍知道是哪一条，刷新后若它消失了就清掉，
    /// 绝不悄悄换成另一条。
    @State private var lastOpenedRecordID: String?
    /// 返回档案列表后要把无障碍焦点放回哪一行。
    @AccessibilityFocusState private var focusedRecordID: String?
    /// 返回档案列表后要把滚动位置放回哪一行。
    @State private var pendingScrollRecordID: String?
    @State private var recordPendingDeletion: ScanFileRecord?
    @State private var showClearAllConfirmation = false
    @State private var deletionTask: Task<Void, Never>?
    /// 分享点云失败时要告诉用户：面板一关就什么也没发生，用户会以为已经分享成功。
    @State private var showShareError = false

    @MainActor
    init(
        customTitle: String = L10n.History.navigationTitle,
        onStartScan: (() -> Void)? = nil,
        onRescanTree: ((String) -> Void)? = nil,
        onImportFile: (() -> Void)? = nil,
        historyStore: ScanHistoryStore? = nil,
        tagStore: TagStore = .shared
    ) {
        let historyStore = historyStore ?? .shared
        self.customTitle = customTitle
        self.onStartScan = onStartScan
        self.onRescanTree = onRescanTree
        self.onImportFile = onImportFile
        self.historyStore = historyStore
        self.tagStore = tagStore
        _deletionController = StateObject(wrappedValue: ScanHistoryDeletionController(
            deleteRecords: { records in await historyStore.deleteRecordsWithResult(records) }
        ))
    }

    var body: some View {
        ZStack {
            Design.Colors.Workspace.background
                .ignoresSafeArea()

            switch loadPresentation.primaryContent {
            case .loading:
                ScanHistoryLoadingView()
            case .loadFailure:
                ScanHistoryLoadFailureStateView(
                    isRetrying: historyStore.isLoading,
                    onRetry: retryLoadingHistory
                )
            case .empty:
                ScrollView {
                    ScanHistoryEmptyState(
                        title: L10n.History.emptyTitle,
                        message: L10n.History.emptyMessage,
                        onStartScan: onStartScan,
                        onImportFile: onImportFile
                    )
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .records:
                loadedHistoryContent
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
                            Label(L10n.History.clearAll, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Design.Colors.Workspace.accent)
                    }
                    .disabled(deletionController.isDeleting)
                    .accessibilityLabel(ScanHistoryText.moreHistoryActions)
                }
            }
        }
        .onAppear { historyStore.loadRecords() }
        .onChange(of: historyStore.scanFiles.count) { _ in dropSelectionIfRecordDisappeared() }
        .onDisappear(perform: cancelDeletionPresentation)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                // 分享点云必须接上完成回调：失败要说出来，不能让用户以为已经分享成功。
                ShareSheet(items: [url]) { result in handleShareCompletion(result) }
            case .pointCloud(let url):
                PointCloudSheet(initialFileURL: url, historyStore: historyStore)
            }
        }
        .navigationDestination(isPresented: openedRecordBinding) {
            if let record = openedRecord {
                ScanArchiveDetailView(
                    recordID: record.id,
                    historyStore: historyStore,
                    onRescan: onRescanTree
                )
                .onDisappear { openedRecord = nil }
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
        .alert(L10n.History.shareFailureTitle, isPresented: $showShareError) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.History.shareFailureMessage)
        }
    }

    // MARK: - Filtered Scans
    private var loadPresentation: ScanHistoryLoadPresentation {
        ScanHistoryLoadPresentation(
            records: historyStore.scanFiles,
            isLoading: historyStore.isLoading,
            loadFailure: historyStore.loadFailure,
            damagedRecords: historyStore.damagedRecords
        )
    }

    private var loadedHistoryContent: some View {
        ScanHistoryContentView(
            filteredScans: filteredScans,
            emptyReason: emptyReason,
            searchQuery: $searchQuery,
            selectedPlotId: $selectedPlotId,
            selectedStatus: $selectedStatus,
            tagStore: tagStore,
            onOpen: openDetail,
            focusedRecordID: $focusedRecordID,
            pendingScrollRecordID: $pendingScrollRecordID,
            onPreview: preview,
            onShare: share,
            onRescan: rescan,
            onMarkReview: markReview,
            onDelete: confirmDelete,
            historyStore: historyStore,
            loadFeedback: historyLoadFeedback
        )
    }

    private var historyLoadFeedback: AnyView? {
        guard loadPresentation.showsLoadFailureBanner || loadPresentation.showsDamagedRecordsBanner else { return nil }
        return AnyView(VStack(alignment: .leading, spacing: Design.Space.md) {
            if loadPresentation.showsLoadFailureBanner {
                ScanHistoryLoadFeedbackCard(
                    icon: "exclamationmark.arrow.triangle.2.circlepath",
                    title: ScanHistoryLoadText.failureTitle,
                    message: ScanHistoryLoadText.staleRecordsMessage(
                        count: historyStore.scanFiles.count
                    ),
                    accent: Design.Colors.Workspace.failure,
                    isRetrying: historyStore.isLoading,
                    onRetry: retryLoadingHistory
                )
            }

            if loadPresentation.showsDamagedRecordsBanner {
                ScanHistoryLoadFeedbackCard(
                    icon: "doc.badge.ellipsis",
                    title: ScanHistoryLoadText.damagedTitle(
                        count: loadPresentation.damagedRecordNames.count
                    ),
                    message: ScanHistoryLoadText.damagedMessage(
                        recordNames: loadPresentation.damagedRecordNames
                    ),
                    accent: Design.Colors.Workspace.attention,
                    isRetrying: historyStore.isLoading,
                    onRetry: retryLoadingHistory
                )
            }
        })
    }

    /// 当前**可见**的档案：地块/状态筛选 ∩ 搜索。
    ///
    /// 三件事分开：
    /// - 地块与状态按树当前归属筛选（与筛选条同源）；
    /// - 搜索只匹配内存里已加载的档案元数据（树号 + 存档编号），
    ///   每敲一个字都不重新解析 PLY，也不另开一条读盘通路；
    /// - 搜索与筛选是**交集**：两个条件都满足才可见。
    private var filteredScans: [ScanFileRecord] {
        let scoped = historyStore.scanFiles.filter { record in
            let assignment = tagStore.getAssignment(treeId: record.treeID)
            if let plotId = selectedPlotId, assignment?.plotId != plotId { return false }
            if let status = selectedStatus, assignment?.status != status { return false }
            return true
        }
        return ScanHistorySearch.filter(scoped, query: searchQuery)
    }

    /// 只按查询命中的档案（**不套**地块/状态）。
    ///
    /// 它只用来判断空结果的**原因**：查询命中了几条却一条都没显示，
    /// 说明是筛选把它们排掉的，不是「没有这样的树号或记录号」。
    private var searchMatchedScans: [ScanFileRecord] {
        ScanHistorySearch.filter(historyStore.scanFiles, query: searchQuery)
    }

    /// 当前该说哪一种空结果（可见记录不为空时没有空结果）。
    private var emptyReason: ScanHistoryEmptyReason? {
        ScanHistoryEmptyReason.resolve(
            archiveCount: historyStore.scanFiles.count,
            searchMatchCount: searchMatchedScans.count,
            visibleCount: filteredScans.count,
            hasSearchQuery: !ScanHistorySearch.normalized(searchQuery).isEmpty)
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

    private func retryLoadingHistory() {
        historyStore.loadRecords()
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

    /// 打开归档详情：定位用存档身份（record.id），同树的多次扫描不会串。
    private func openDetail(_ record: ScanFileRecord) {
        openedRecord = record
        lastOpenedRecordID = record.id
        isDetailPresented = true
    }

    /// 详情是否展示。退场时**不**清 payload —— 由详情页的 `onDisappear` 收尾，
    /// 这样退场动画期间详情仍然是原来那一条，不是空视图。
    private var openedRecordBinding: Binding<Bool> {
        Binding(
            get: { isDetailPresented },
            set: { isPresented in
                isDetailPresented = isPresented
                if !isPresented {
                    prepareRestoreAfterDetail()
                }
            }
        )
    }

    /// 从详情返回：把焦点与滚动位置放回刚才看的那一条。
    ///
    /// 筛选、搜索词与选中本来就是这一页的状态（没有被详情改写），所以返回后它们自然还在；
    /// 焦点与滚动位置是**新**的状态，必须显式放回去。
    ///
    /// 放回哪一条由 `ScanHistoryRestoreTarget` 决定，可用的候选是**当前可见**的那些：
    /// 那条存档要是已经不在了，或者被搜索/筛选挡住了，就什么都不放回 ——
    /// 绝不悄悄换成另一条（同树的另一份存档也不行，更不能落到看不见的行上）。
    private func prepareRestoreAfterDetail() {
        let target = ScanHistoryRestoreTarget.resolve(
            openedRecordID: lastOpenedRecordID,
            availableRecordIDs: filteredScans.map(\.id)
        )
        guard case .restore(let recordID) = target else { return }
        pendingScrollRecordID = recordID
        focusedRecordID = recordID
    }

    /// 刷新后如果刚看过的那条已经不在档案里，就清掉这份选择 ——
    /// 不能悄悄换成同树的另一条记录。
    private func dropSelectionIfRecordDisappeared() {
        guard let id = lastOpenedRecordID else { return }
        if !historyStore.scanFiles.contains(where: { $0.id == id }) {
            lastOpenedRecordID = nil
        }
    }

    private func preview(_ record: ScanFileRecord) {
        presentedSheet = .pointCloud(record.fileURL)
    }

    private func share(_ record: ScanFileRecord) {
        presentedSheet = .share(record.fileURL)
    }

    /// 分享点云失败要说出来。
    ///
    /// 之前这里用 `ShareSheet(items:)` 不带完成回调，UIKit 报的失败被直接丢掉：
    /// 分享面板关掉后什么也没发生，用户以为点云已经分享/保存成功。
    /// 用户自己取消不算失败，不打扰。
    private func handleShareCompletion(_ result: ShareActivityResult) {
        guard ScanShareFailurePolicy.isFailure(result) else { return }
        Log.export.error("Archive point cloud sharing failed: \(result.errorDescription ?? "Unknown activity error")")
        showShareError = true
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

    private static func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }
}

struct ScanHistoryLoadPresentation: Equatable {
    enum PrimaryContent: Equatable {
        case loading
        case loadFailure
        case empty
        case records
    }

    let primaryContent: PrimaryContent
    let showsLoadFailureBanner: Bool
    let showsDamagedRecordsBanner: Bool
    let damagedRecordNames: [String]

    init(
        records: [ScanFileRecord],
        isLoading: Bool,
        loadFailure: ScanHistoryLoadFailure?,
        damagedRecords: [ScanFileRecord]
    ) {
        if records.isEmpty {
            if loadFailure != nil {
                primaryContent = .loadFailure
            } else if isLoading {
                primaryContent = .loading
            } else {
                primaryContent = .empty
            }
        } else {
            primaryContent = .records
        }

        showsLoadFailureBanner = !records.isEmpty && loadFailure != nil
        damagedRecordNames = damagedRecords.map(\.id)
        showsDamagedRecordsBanner = loadFailure == nil && !damagedRecordNames.isEmpty
    }
}

private struct ScanHistoryLoadingView: View {
    var body: some View {
        VStack(spacing: Design.Space.sm) {
            ProgressView()
                .tint(Design.Colors.Workspace.accent)
            Text(ScanHistoryLoadText.loading)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScanHistoryLoadText.loading)
    }
}

private struct ScanHistoryLoadFailureStateView: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            ScanHistoryLoadFeedbackCard(
                icon: "folder.badge.questionmark",
                title: ScanHistoryLoadText.failureTitle,
                message: ScanHistoryLoadText.failureEmptyMessage,
                accent: Design.Colors.Workspace.failure,
                isRetrying: isRetrying,
                onRetry: onRetry
            )
            .frame(maxWidth: 760, alignment: .leading)
            .padding(Design.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 读取反馈：归档目录没读成功，或部分记录的结果文件损坏。
///
/// 反馈必须是"看得懂的解释 + 下一步"，因此保留标题、说明与重试动作。
private struct ScanHistoryLoadFeedbackCard: View {
    let icon: String
    let title: String
    let message: String
    let accent: Color
    let isRetrying: Bool
    let onRetry: () -> Void

    private var isFailure: Bool {
        accent == Design.Colors.Workspace.failure
    }

    var body: some View {
        if isFailure {
            InstrumentPanel(label: title, systemImage: icon, tone: .failure) {
                content
            }
        } else {
            InstrumentPanel(label: title, systemImage: icon, tone: .attention) {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.footnote)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                HStack(spacing: 6) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRetrying ? ScanHistoryLoadText.retrying : ScanHistoryLoadText.retry)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent)
                .padding(.horizontal, 10)
                .frame(minHeight: Design.Touch.minimumHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityLabel(isRetrying ? ScanHistoryLoadText.retrying : ScanHistoryLoadText.retry)
            .accessibilityHint(ScanHistoryLoadText.retryHint)
        }
    }
}

private enum ScanHistoryLoadText {
    static let loading = localized(
        "history.load.loading",
        fallback: "正在读取历史记录…"
    )
    static let failureTitle = localized(
        "history.load.failure.title",
        fallback: "历史记录未更新"
    )
    static let failureEmptyMessage = localized(
        "history.load.failure.empty_message",
        fallback: "无法读取本机扫描目录。现有文件没有被删除，请重试。"
    )
    static let retry = localized(
        "history.load.retry",
        fallback: "重试"
    )
    static let retrying = localized(
        "history.load.retrying",
        fallback: "正在重试…"
    )
    static let retryHint = localized(
        "history.load.retry_hint",
        fallback: "重新读取本机扫描目录。"
    )

    static func staleRecordsMessage(count: Int) -> String {
        String(
            format: localized(
                "history.load.failure.stale_message_format",
                fallback: "无法读取本机扫描目录，正在显示上次成功加载的 %d 条记录。"
            ),
            count
        )
    }

}

extension ScanHistoryText {
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
}

extension ScanHistoryLoadText {
    static func damagedTitle(count: Int) -> String {
        let key = count == 1
            ? "history.load.damaged.title_one"
            : "history.load.damaged.title_many_format"
        let fallback = count == 1
            ? "1 条记录的结果文件损坏"
            : "%d 条记录的结果文件损坏"
        let localizedTitle = localized(key, fallback: fallback)
        return count == 1 ? localizedTitle : String(format: localizedTitle, count)
    }

    static func damagedMessage(recordNames: [String]) -> String {
        let visibleNames = recordNames.prefix(2)
        var summary = visibleNames.joined(
            separator: localized(
                "history.load.damaged.separator",
                fallback: "、"
            )
        )
        let remainingCount = recordNames.count - visibleNames.count
        if remainingCount > 0 {
            summary += String(
                format: localized(
                    "history.load.damaged.more_format",
                    fallback: "等 %d 条"
                ),
                remainingCount
            )
        }
        return String(
            format: localized(
                "history.load.damaged.message_format",
                fallback: "点云仍保留，但果数和产量不可作为可靠结果：%@"
            ),
            summary
        )
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
                    .tint(Design.Colors.Workspace.accent)

                Text(ScanHistoryDeletionCopy.progress)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .fill(Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
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
        value: "将永久删除这条扫描记录及全部关联文件，包括点云、结果和已有的观测回放数据。此操作无法撤销。"
    )
    static let clearConfirmationTitle = localized(
        "history.delete.all.title",
        value: "清空全部扫描记录"
    )
    static let clearConfirmationMessage = localized(
        "history.delete.all.message",
        value: "将永久删除全部扫描记录及所有关联文件，包括点云、结果和已有的观测回放数据。此操作无法撤销。"
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
        case .replayInput, .replayPoints, .replayPreparation:
            return localized("history.delete.artifact.replay_data", value: "回放数据")
        case .archiveRecovery:
            return localized("history.delete.artifact.archive_recovery", value: "存档恢复数据")
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
