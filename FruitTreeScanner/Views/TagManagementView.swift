// TagManagementView.swift
// 标签管理主页 - 地块、标签、状态三个标签页

import SwiftUI

enum TagManagementDeletionRequest {
    case plot(Plot, affectedTreeCount: Int)
    case tag(GroupTag, affectedTreeCount: Int)

    var title: String {
        switch self {
        case .plot(let plot, _):
            return "删除地块“\(plot.name)”？"
        case .tag(let tag, _):
            return "删除标签“\(tag.name)”？"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .plot:
            return "删除地块"
        case .tag:
            return "删除标签"
        }
    }

    var message: String {
        switch self {
        case .plot(_, let affectedTreeCount):
            return "该操作会取消 \(affectedTreeCount) 棵树的地块归属，但不会删除扫描记录。"
        case .tag(_, let affectedTreeCount):
            return "该操作会从 \(affectedTreeCount) 棵树移除此标签，但不会删除扫描记录。"
        }
    }

    @MainActor
    func confirm(in store: TagStore) {
        switch self {
        case .plot(let plot, _):
            store.deletePlot(id: plot.id)
        case .tag(let tag, _):
            store.deleteTag(id: tag.id)
        }
    }
}

struct TagManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tagStore = TagStore.shared
    var onStartScan: (() -> Void)? = nil
    @State private var selectedTab: Int = 0
    @State private var presentedSheet: TagManagementSheet?
    @State private var pendingDeletion: TagManagementDeletionRequest?

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                VStack(spacing: 12) {
                    DashboardToolHeader(
                        imageName: "FeatureTagManagement",
                        title: "地块标签",
                        subtitle: "维护地块、标签和扫描状态，让每棵树都有清晰归属。",
                        icon: "tag",
                        accent: Design.Colors.harvest
                    )
                    .padding(.horizontal, Design.Space.md)
                    .padding(.top, Design.Space.md)

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
                            onEdit: { presentedSheet = .editPlot($0) },
                            onDelete: { plot in
                                pendingDeletion = .plot(
                                    plot,
                                    affectedTreeCount: tagStore.treeCount(forPlotId: plot.id)
                                )
                            },
                            onAdd: { presentedSheet = .addPlot }
                        )
                        .tag(0)

                        TagListView(
                            tags: tagStore.tags,
                            treeCount: { tagStore.treeCount(forTagId: $0) },
                            onEdit: { presentedSheet = .editTag($0) },
                            onDelete: { tag in
                                pendingDeletion = .tag(
                                    tag,
                                    affectedTreeCount: tagStore.treeCount(forTagId: tag.id)
                                )
                            },
                            onAdd: { presentedSheet = .addTag }
                        )
                        .tag(1)

                        StatusOverviewView(
                            assignments: tagStore.assignments,
                            onStartScan: onStartScan
                        )
                        .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .confirmationDialog(
                Text(pendingDeletion?.title ?? "确认删除"),
                isPresented: isDeletionDialogPresented,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { request in
                Button(request.confirmationTitle, role: .destructive) {
                    request.confirm(in: tagStore)
                }
                Button("取消", role: .cancel) {}
            } message: { request in
                Text(request.message)
            }
            .navigationTitle("标签管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.harvest)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab != 2 {
                        Button(action: showAddSheet) {
                            Image(systemName: "plus")
                                .foregroundColor(Design.Colors.harvest)
                        }
                        .accessibilityLabel(selectedTab == 0 ? "添加地块" : "添加标签")
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addPlot:
                    PlotEditView { plot in
                        tagStore.addPlot(name: plot.name, colorHex: plot.colorHex)
                    }
                case .editPlot(let plot):
                    PlotEditView(plot: plot) { updatedPlot in
                        tagStore.updatePlot(updatedPlot)
                    }
                case .addTag:
                    TagEditView { tag in
                        tagStore.addTag(name: tag.name, colorHex: tag.colorHex)
                    }
                case .editTag(let tag):
                    TagEditView(tag: tag) { updatedTag in
                        tagStore.updateTag(updatedTag)
                    }
                }
            }
        }
    }

    private var isDeletionDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private func showAddSheet() {
        if selectedTab == 0 {
            presentedSheet = .addPlot
        } else if selectedTab == 1 {
            presentedSheet = .addTag
        }
    }
}

private enum TagManagementSheet: Identifiable {
    case addPlot
    case editPlot(Plot)
    case addTag
    case editTag(GroupTag)

    var id: String {
        switch self {
        case .addPlot:
            return "add-plot"
        case .editPlot(let plot):
            return "edit-plot-\(plot.id.uuidString)"
        case .addTag:
            return "add-tag"
        case .editTag(let tag):
            return "edit-tag-\(tag.id.uuidString)"
        }
    }
}
