// TagManagementView.swift
// 标签管理主页 - 地块、标签、状态三个标签页

import SwiftUI

struct TagManagementView: View {
    @StateObject private var tagStore = TagStore.shared
    @State private var selectedTab: Int = 0
    @State private var showingAddPlot: Bool = false
    @State private var showingAddTag: Bool = false
    @State private var editingPlot: Plot?
    @State private var editingTag: GroupTag?

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("标签管理", selection: $selectedTab) {
                        Text("地块").tag(0)
                        Text("标签").tag(1)
                        Text("状态").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)

                    // Tab Content
                    TabView(selection: $selectedTab) {
                        PlotListView(
                            plots: tagStore.plots,
                            treeCount: { tagStore.treeCount(forPlotId: $0) },
                            onEdit: { editingPlot = $0 },
                            onDelete: { tagStore.deletePlot(id: $0) }
                        )
                        .tag(0)

                        TagListView(
                            tags: tagStore.tags,
                            treeCount: { tagStore.treeCount(forTagId: $0) },
                            onEdit: { editingTag = $0 },
                            onDelete: { tagStore.deleteTag(id: $0) }
                        )
                        .tag(1)

                        StatusOverviewView(
                            assignments: tagStore.assignments
                        )
                        .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("标签管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if selectedTab == 0 {
                            showingAddPlot = true
                        } else if selectedTab == 1 {
                            showingAddTag = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(Design.Colors.forest)
                    }
                }
            }
            .sheet(isPresented: $showingAddPlot) {
                PlotEditView { plot in
                    tagStore.addPlot(name: plot.name, colorHex: plot.colorHex)
                }
            }
            .sheet(item: $editingPlot) { plot in
                PlotEditView(plot: plot) { updatedPlot in
                    tagStore.updatePlot(updatedPlot)
                }
            }
            .sheet(isPresented: $showingAddTag) {
                TagEditView { tag in
                    tagStore.addTag(name: tag.name, colorHex: tag.colorHex)
                }
            }
            .sheet(item: $editingTag) { tag in
                TagEditView(tag: tag) { updatedTag in
                    tagStore.updateTag(updatedTag)
                }
            }
        }
    }
}

// MARK: - PlotListView

struct PlotListView: View {
    let plots: [Plot]
    let treeCount: (UUID) -> Int
    let onEdit: (Plot) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        if plots.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(plots) { plot in
                    PlotRowView(
                        plot: plot,
                        treeCount: treeCount(plot.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEdit(plot)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        onDelete(plots[index].id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(Design.Colors.pebble)

            Text("暂无地块")
                .font(Design.Typography.headline)
                .foregroundColor(Color(hex: "3D3A36"))

            Text("点击右上角 + 添加地块")
                .font(Design.Typography.subheadline)
                .foregroundColor(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.bgBase)
    }
}

// MARK: - PlotRowView

struct PlotRowView: View {
    let plot: Plot
    let treeCount: Int

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Circle()
                .fill(Color(hex: plot.colorHex))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(plot.name)
                    .font(Design.Typography.headline)
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text("\(treeCount) 棵树")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Color(hex: "8E8E93"))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.pebble)
        }
        .padding(.vertical, Design.Space.sm)
    }
}

// MARK: - TagListView

struct TagListView: View {
    let tags: [GroupTag]
    let treeCount: (UUID) -> Int
    let onEdit: (GroupTag) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        if tags.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(tags) { tag in
                    TagRowView(
                        tag: tag,
                        treeCount: treeCount(tag.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEdit(tag)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        onDelete(tags[index].id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundColor(Design.Colors.pebble)

            Text("暂无标签")
                .font(Design.Typography.headline)
                .foregroundColor(Color(hex: "3D3A36"))

            Text("点击右上角 + 添加标签")
                .font(Design.Typography.subheadline)
                .foregroundColor(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.bgBase)
    }
}

// MARK: - TagRowView

struct TagRowView: View {
    let tag: GroupTag
    let treeCount: Int

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(tag.name)
                    .font(Design.Typography.headline)
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text("\(treeCount) 棵树")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Color(hex: "8E8E93"))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.pebble)
        }
        .padding(.vertical, Design.Space.sm)
    }
}

// MARK: - StatusOverviewView

struct StatusOverviewView: View {
    let assignments: [TreeAssignment]

    var body: some View {
        List {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                StatusRowView(
                    status: status,
                    count: assignments.filter { $0.status == status }.count
                )
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - StatusRowView

struct StatusRowView: View {
    let status: ScanStatus
    let count: Int

    private var icon: String {
        switch status {
        case .notScanned: return "circle"
        case .scanned: return "checkmark.circle"
        case .reviewing: return "arrow.clockwise.circle"
        case .completed: return "checkmark.seal.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .notScanned: return Color(hex: "8E8E93")
        case .scanned: return Color(hex: "007AFF")
        case .reviewing: return Color(hex: "FF9500")
        case .completed: return Color(hex: "34C759")
        }
    }

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(status.rawValue)
                    .font(Design.Typography.headline)
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text("\(count) 棵树")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Color(hex: "8E8E93"))
            }

            Spacer()
        }
        .padding(.vertical, Design.Space.sm)
    }
}

#Preview {
    TagManagementView()
}