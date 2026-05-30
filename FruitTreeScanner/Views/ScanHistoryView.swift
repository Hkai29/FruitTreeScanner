// ScanHistoryView.swift
// 扫描历史列表 - 自然有机风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = "扫描历史"
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @StateObject private var tagStore = TagStore.shared
    @State private var selectedPlotId: UUID?
    @State private var selectedStatus: ScanStatus?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if historyStore.scanFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(Design.Colors.Dark.textSecondary.opacity(0.5))

                    Text("暂无扫描记录")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Text("开始扫描以创建历史记录")
                        .font(.system(size: 14))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    // Filter bar
                    filterBar
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, Design.Space.sm)

                    // Scan list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredScans) { record in
                                HistoryCard(record: record, onShare: {
                                    shareItems = [record.fileURL]
                                    showShareSheet = true
                                }, onDelete: {
                                    historyStore.deleteRecord(record)
                                })
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
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
                            let filesToDelete = historyStore.scanFiles
                            filesToDelete.forEach { historyStore.deleteRecord($0) }
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

// MARK: - 历史记录卡片
struct HistoryCard: View {
    let record: ScanFileRecord
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Design.Colors.harvest.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "cube.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Design.Colors.harvest)
            }

            // 信息
            VStack(alignment: .leading, spacing: 6) {
                Text(record.fileURL.lastPathComponent)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(fileSize, systemImage: "doc")
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    Label(dateString, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

                if record.fruitCount > 0 || record.yieldKg > 0 {
                    HStack(spacing: 12) {
                        if record.fruitCount > 0 {
                            Label("\(record.fruitCount) 个", systemImage: "leaf.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Design.Colors.harvest)
                        }
                        if record.yieldKg > 0 {
                            Label(String(format: "%.1f kg", record.yieldKg), systemImage: "scalemass.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Design.Colors.harvest)
                        }
                    }
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundColor(Design.Colors.Dark.info)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(Design.Colors.error)
                }
            }
        }
        .padding(16)
        .background(
            GlassCard(cornerRadius: 16, padding: 0) {
                EmptyView()
            }
            .opacity(0.8)
        )
    }

    private var fileSize: String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path),
              let size = attr[.size] as? Int else { return "未知" }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: record.scanDate)
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