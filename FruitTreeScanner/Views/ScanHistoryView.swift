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
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    @State private var presentedSheet: ScanHistorySheet?
    @State private var recordPendingDeletion: ScanFileRecord?
    @State private var showClearAllConfirmation = false

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
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
                ScanHistoryEmptyState(
                    title: "暂无扫描记录",
                    message: "完成扫描或导入 PLY 后，点云文件、果数和产量会按时间保存在这里。",
                    onStartScan: onStartScan,
                    onImportFile: onImportFile
                )
            case .records:
                loadedHistoryContent
            }
        }
        .navigationTitle(customTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyStore.scanFiles.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Label("清空全部", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Design.Colors.forest)
                    }
                }
            }
        }
        .onAppear { historyStore.loadRecords() }
        .refreshable { await historyStore.reloadRecords() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url])
            case .pointCloud(let url):
                PointCloudSheet(initialFileURL: url)
            }
        }
        .alert("删除扫描记录", isPresented: deleteRecordAlertBinding) {
            Button("取消", role: .cancel) {
                recordPendingDeletion = nil
            }
            Button("删除", role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            Text("将删除这条记录关联的 PLY 点云、CSV 和结果文件。")
        }
        .alert("清空全部扫描记录", isPresented: $showClearAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                historyStore.deleteRecords(historyStore.scanFiles)
            }
        } message: {
            Text("将删除当前所有扫描记录及其关联文件，此操作无法撤销。")
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
        VStack(spacing: 0) {
            if loadPresentation.showsLoadFailureBanner {
                ScanHistoryLoadFeedbackCard(
                    icon: "exclamationmark.arrow.triangle.2.circlepath",
                    title: ScanHistoryLoadText.failureTitle,
                    message: ScanHistoryLoadText.staleRecordsMessage(
                        count: historyStore.scanFiles.count
                    ),
                    accent: Design.Colors.error,
                    isRetrying: historyStore.isLoading,
                    onRetry: retryLoadingHistory
                )
                .padding(.horizontal, Design.Space.md)
                .padding(.top, Design.Space.sm)
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
                    accent: Design.Colors.warning,
                    isRetrying: historyStore.isLoading,
                    onRetry: retryLoadingHistory
                )
                .padding(.horizontal, Design.Space.md)
                .padding(.top, Design.Space.sm)
            }

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

    private func retryLoadingHistory() {
        historyStore.loadRecords()
    }

    private func deletePendingRecord() {
        guard let record = recordPendingDeletion else { return }
        recordPendingDeletion = nil
        historyStore.deleteRecord(record)
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
                .tint(Design.Colors.harvest)
            Text(ScanHistoryLoadText.loading)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScanHistoryLoadText.loading)
    }
}

private struct ScanHistoryLoadFailureStateView: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack {
            ScanHistoryLoadFeedbackCard(
                icon: "folder.badge.questionmark",
                title: ScanHistoryLoadText.failureTitle,
                message: ScanHistoryLoadText.failureEmptyMessage,
                accent: Design.Colors.error,
                isRetrying: isRetrying,
                onRetry: onRetry
            )
            .padding(Design.Space.md)

            Spacer()
        }
    }
}

private struct ScanHistoryLoadFeedbackCard: View {
    let icon: String
    let title: String
    let message: String
    let accent: Color
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(alignment: .top, spacing: Design.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onRetry) {
                HStack(spacing: 6) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(
                        isRetrying
                            ? ScanHistoryLoadText.retrying
                            : ScanHistoryLoadText.retry
                    )
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .disabled(isRetrying)
            .accessibilityHint(ScanHistoryLoadText.retryHint)
        }
        .padding(Design.Space.sm)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
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
