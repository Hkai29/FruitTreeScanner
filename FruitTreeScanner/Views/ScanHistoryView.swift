// ScanHistoryView.swift
// 扫描历史列表 - 自然有机风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = "扫描历史"
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var selectedPointCloudURL: URL?
    @State private var showPointCloud = false
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
                VStack(spacing: 0) {
                    DashboardToolHeader(
                        imageName: "FeatureScanHistory",
                        title: "扫描记录",
                        subtitle: "按时间、地块和状态查看所有扫描文件。",
                        icon: "folder",
                        accent: Design.Colors.harvest
                    )
                    .padding(.horizontal, Design.Space.md)
                    .padding(.top, Design.Space.md)

                    // Filter bar
                    filterBar
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, Design.Space.sm)

                    // Scan list
                    ScrollView {
                        if filteredScans.isEmpty {
                            ScanHistoryEmptyState(
                                title: "没有符合筛选的记录",
                                message: "切换地块或状态筛选后再查看。",
                                onStartScan: nil,
                                onImportFile: nil
                            )
                            .padding(.top, Design.Space.md)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredScans) { record in
                                    HistoryRow(record: record, onPreview: {
                                        selectedPointCloudURL = record.fileURL
                                        showPointCloud = true
                                    }, onShare: {
                                        shareItems = [record.fileURL]
                                        showShareSheet = true
                                    }, onDelete: {
                                        recordPendingDeletion = record
                                    })
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showPointCloud) {
            PointCloudSheet(initialFileURL: selectedPointCloudURL)
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

    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Space.sm) {
                // Plot filter
                FilterChip(
                    title: selectedPlotId == nil ? "全部地块" : (tagStore.getPlot(id: selectedPlotId!)?.name ?? "地块"),
                    isSelected: selectedPlotId != nil
                ) {
                    Button("全部地块") { selectedPlotId = nil }
                    Divider()
                    ForEach(tagStore.plots) { plot in
                        Button(plot.name) { selectedPlotId = plot.id }
                    }
                }

                // Status filter
                FilterChip(
                    title: selectedStatus == nil ? "全部状态" : (selectedStatus?.rawValue ?? "状态"),
                    isSelected: selectedStatus != nil
                ) {
                    Button("全部状态") { selectedStatus = nil }
                    Divider()
                    ForEach(ScanStatus.allCases, id: \.self) { status in
                        Button(status.rawValue) { selectedStatus = status }
                    }
                }
            }
        }
    }
}

// MARK: - 历史记录空状态

private struct ScanHistoryEmptyState: View {
    let title: String
    let message: String
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "clock.arrow.circlepath",
                imageName: "FeatureScanHistory",
                title: title,
                message: message,
                accent: Design.Colors.harvest,
                primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
                secondaryAction: action(title: "导入 PLY", icon: "square.and.arrow.down", handler: onImportFile)
            )

            Spacer()
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

// MARK: - 历史记录行

struct HistoryRow: View {
    let record: ScanFileRecord
    let onPreview: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 32, height: 32)
                .background(Design.Colors.harvest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(record.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(fileSize)
                    Text(dateString)
                }
                .font(.system(size: 11))
                .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.fruitCount > 0 ? "\(record.fruitCount) 个" : "未计数")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(record.fruitCount > 0 ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)

                Text(record.yieldKg > 0 ? String(format: "%.1f kg", record.yieldKg) : "--")
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .frame(minWidth: 58, alignment: .trailing)

            Button(action: onPreview) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("预览点云")

            Menu {
                Button(action: onShare) {
                    Label("分享点云", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("删除记录", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var fileSize: String {
        guard record.fileSizeBytes > 0 else { return "未知大小" }
        let mb = Double(record.fileSizeBytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.scanDate)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
