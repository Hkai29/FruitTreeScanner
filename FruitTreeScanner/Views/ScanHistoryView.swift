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
        .refreshable { historyStore.loadRecords() }
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
