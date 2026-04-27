// TreeFilterView.swift
// 果树列表筛选视图

import SwiftUI

struct TreeFilterView: View {
    @StateObject private var tagStore = TagStore.shared
    @ObservedObject var historyStore: ScanHistoryStore

    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter bar
                    filterBar
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, Design.Space.sm)

                    // Tree list
                    treeList
                }
            }
            .navigationTitle("果树列表")
            .navigationBarTitleDisplayMode(.large)
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

                // Tag filter
                FilterChip(
                    title: selectedTagIds.isEmpty ? "全部标签" : "\(selectedTagIds.count) 个标签",
                    isSelected: !selectedTagIds.isEmpty
                ) {
                    Button("全部标签") { selectedTagIds = [] }
                    Divider()
                    ForEach(tagStore.tags) { tag in
                        Button {
                            if selectedTagIds.contains(tag.id) {
                                selectedTagIds.remove(tag.id)
                            } else {
                                selectedTagIds.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Text(tag.name)
                                if selectedTagIds.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
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

    // MARK: - Tree List
    private var treeList: some View {
        let filtered = tagStore.filteredAssignments(
            plotId: selectedPlotId,
            tagIds: Array(selectedTagIds),
            status: selectedStatus
        )

        return Group {
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "8E8E93"))
                    Text("暂无果树")
                        .font(.headline)
                        .foregroundColor(Color(hex: "3D3A36"))
                    Text("当前筛选条件下没有果树记录")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "8E8E93"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: Design.Space.sm) {
                        ForEach(filtered) { assignment in
                            TreeRowView(
                                assignment: assignment,
                                plot: assignment.plotId.flatMap { tagStore.getPlot(id: $0) },
                                tags: tagStore.tags.filter { assignment.tagIds.contains($0.id) },
                                latestScan: latestScan(for: assignment.treeId)
                            )
                        }
                    }
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                }
            }
        }
    }

    // MARK: - Helpers
    private func latestScan(for treeId: String) -> ScanFileRecord? {
        historyStore.scanFiles.first { $0.treeID == treeId }
    }
}

// MARK: - StatusBadge
struct StatusBadge: View {
    let status: ScanStatus

    private var backgroundColor: Color {
        switch status {
        case .notScanned: return Color(hex: "8E8E93")  // gray
        case .scanned: return Design.Colors.earth       // blue
        case .reviewing: return Design.Colors.harvest    // orange
        case .completed: return Design.Colors.forest    // green
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(Design.Typography.captionMedium)
            .foregroundColor(.white)
            .padding(.horizontal, Design.Space.sm + 2)
            .padding(.vertical, Design.Space.xs + 1)
            .background(Capsule().fill(backgroundColor))
    }
}

// MARK: - TagBadge
struct TagBadge: View {
    let tag: GroupTag

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)

            Text(tag.name)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.charcoal)
        }
        .padding(.horizontal, Design.Space.sm + 2)
        .padding(.vertical, Design.Space.xs + 1)
        .background(Capsule().fill(Design.Colors.stone))
    }
}

// MARK: - TreeRowView
struct TreeRowView: View {
    let assignment: TreeAssignment
    let plot: Plot?
    let tags: [GroupTag]
    let latestScan: ScanFileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            // Top row: plot name + status badge
            HStack {
                if let plot = plot {
                    HStack(spacing: Design.Space.sm) {
                        Circle()
                            .fill(Color(hex: plot.colorHex))
                            .frame(width: 8, height: 8)

                        Text(plot.name)
                            .font(Design.Typography.subheadlineMedium)
                            .foregroundColor(Design.Colors.charcoal)
                    }
                } else {
                    Text("未分配")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.slate)
                }

                Spacer()

                StatusBadge(status: assignment.status)
            }

            // Tree ID (headline)
            Text(assignment.treeId)
                .font(Design.Typography.headline)
                .foregroundColor(Color(hex: "1C1C1E"))

            // Tag badges
            if !tags.isEmpty {
                HStack(spacing: Design.Space.xs) {
                    ForEach(tags.prefix(3)) { tag in
                        TagBadge(tag: tag)
                    }

                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.slate)
                            .padding(.horizontal, Design.Space.sm)
                            .padding(.vertical, Design.Space.xs + 1)
                            .background(Capsule().fill(Design.Colors.stone))
                    }
                }
            }

            // Latest scan info
            if let scan = latestScan {
                HStack(spacing: Design.Space.md) {
                    Label(scan.fruitType, systemImage: "leaf.fill")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.forest)

                    if scan.fruitCount > 0 {
                        Label("\(scan.fruitCount) 个", systemImage: "number")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.slate)
                    }

                    Spacer()

                    Text(scanDateString(scan.scanDate))
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Color.white)
                .shadow(
                    color: Design.Shadow.subtle.color,
                    radius: Design.Shadow.subtle.radius,
                    y: Design.Shadow.subtle.y
                )
        )
    }

    private func scanDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

#Preview {
    TreeFilterView(historyStore: ScanHistoryStore.shared)
}