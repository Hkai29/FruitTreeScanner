// TagManagementView.swift
// 标签管理主页 - 地块、标签、状态三个视图。
//
// 三页都读同一份 TagStore：地块与标签显示真实树数，状态页显示真实状态分布。
// 新建、编辑、取消、删除的门禁与确认流程保持不变。

import SwiftUI

enum TagManagementDeletionRequest {
    case plot(Plot, affectedTreeCount: Int)
    case tag(GroupTag, affectedTreeCount: Int)

    var title: String {
        title(in: .main)
    }

    func title(in bundle: Bundle) -> String {
        switch self {
        case .plot(let plot, _):
            return L10n.TagManagement.plotDeletionTitle(name: plot.name, in: bundle)
        case .tag(let tag, _):
            return L10n.TagManagement.tagDeletionTitle(name: tag.name, in: bundle)
        }
    }

    var confirmationTitle: String {
        confirmationTitle(in: .main)
    }

    func confirmationTitle(in bundle: Bundle) -> String {
        switch self {
        case .plot:
            return L10n.TagManagement.text(.deletePlotAction, in: bundle)
        case .tag:
            return L10n.TagManagement.text(.deleteTagAction, in: bundle)
        }
    }

    var message: String {
        message(in: .main)
    }

    func message(in bundle: Bundle) -> String {
        switch self {
        case .plot(_, let affectedTreeCount):
            return L10n.TagManagement.plotDeletionMessage(
                treeCount: affectedTreeCount,
                in: bundle
            )
        case .tag(_, let affectedTreeCount):
            return L10n.TagManagement.tagDeletionMessage(
                treeCount: affectedTreeCount,
                in: bundle
            )
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
    @ObservedObject private var tagStore: TagStore
    var onStartScan: (() -> Void)? = nil
    var onScanTree: ((String) -> Void)? = nil
    @State private var selectedTab: Int = 0
    @State private var presentedSheet: TagManagementSheet?
    @State private var pendingDeletion: TagManagementDeletionRequest?

    @MainActor
    init(onStartScan: (() -> Void)? = nil, tagStore: TagStore = .shared, onScanTree: ((String) -> Void)? = nil) {
        self.onStartScan = onStartScan
        self.tagStore = tagStore
        self.onScanTree = onScanTree
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                    NavigationLink {
                        TreeSurveyCatalogView(catalog: .shared, onScanTree: onScanTree)
                    } label: {
                        HStack {
                            Image(systemName: "scope")
                            Text("单树定位")
                            Spacer()
                            Text("测量点与精度").font(.subheadline)
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .padding(.horizontal, 20)
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .accessibilityIdentifier("orchard.treeSurvey")
                    // 视图切换保留系统分段控件：它既是既有原生控件契约，
                    // 也在日光工作区上使用浅色外观。
                    Picker(L10n.TagManagement.tabPickerLabel, selection: $selectedTab) {
                        Text(L10n.TagManagement.plotsTab).tag(0)
                        Text(L10n.TagManagement.tagsTab).tag(1)
                        Text(L10n.TagManagement.statusTab).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                    content
                }
            }
            .workspacePage()
            .confirmationDialog(
                Text(pendingDeletion?.title ?? L10n.TagManagement.confirmDelete),
                isPresented: isDeletionDialogPresented,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { request in
                Button(request.confirmationTitle, role: .destructive) {
                    request.confirm(in: tagStore)
                }
                Button(L10n.TagManagement.cancel, role: .cancel) {}
            } message: { request in
                Text(request.message)
            }
            .navigationTitle(L10n.TagManagement.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.done) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.Workspace.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab != 2 {
                        Button(action: showAddSheet) {
                            Image(systemName: "plus")
                                .foregroundColor(Design.Colors.Workspace.accent)
                        }
                        .accessibilityLabel(
                            selectedTab == 0 ? L10n.TagManagement.addPlot : L10n.TagManagement.addTag
                        )
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
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case 0:
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
        case 1:
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
        default:
            StatusOverviewView(
                assignments: tagStore.assignments,
                onStartScan: onStartScan
            )
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
