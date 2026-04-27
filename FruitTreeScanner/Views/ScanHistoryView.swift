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
            Color.white
                .ignoresSafeArea()

            if historyStore.scanFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(Color(hex: "C7C7CC"))

                    Text("暂无扫描记录")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(hex: "8E8E93"))

                    Text("开始扫描以创建历史记录")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "C7C7CC"))
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
                    Menu {
                        Button("全部地块") { selectedPlotId = nil }
                        Divider()
                        ForEach(tagStore.plots) { plot in
                            Button(plot.name) { selectedPlotId = plot.id }
                        }
                    } label: {
                        EmptyView()
                    }
                }

                // Status filter
                FilterChip(
                    title: selectedStatus == nil ? "全部状态" : (selectedStatus?.rawValue ?? "状态"),
                    isSelected: selectedStatus != nil
                ) {
                    Menu {
                        Button("全部状态") { selectedStatus = nil }
                        Divider()
                        ForEach(ScanStatus.allCases, id: \.self) { status in
                            Button(status.rawValue) { selectedStatus = status }
                        }
                    } label: {
                        EmptyView()
                    }
                }
            }
        }
    }
}

// MARK: - FilterChip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let menu: () -> Menu<Void, Never>

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: Design.Space.xs) {
                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(isSelected ? .white : Design.Colors.charcoal)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : Design.Colors.slate)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm + 2)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.forest : Design.Colors.bgSurface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Design.Colors.pebble, lineWidth: 1)
            )
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
                    .fill(Design.Colors.forest.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "cube.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Design.Colors.forest)
            }

            // 信息
            VStack(alignment: .leading, spacing: 6) {
                Text(record.fileURL.lastPathComponent)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "1C1C1E"))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(fileSize, systemImage: "doc")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8E8E93"))

                    Label(dateString, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8E8E93"))
                }

                if record.fruitCount > 0 || record.yieldKg > 0 {
                    HStack(spacing: 12) {
                        if record.fruitCount > 0 {
                            Label("\(record.fruitCount) 个", systemImage: "leaf.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Design.Colors.forest)
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
                        .foregroundColor(Design.Colors.info)
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)
                )
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