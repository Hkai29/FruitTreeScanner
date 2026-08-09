// TagManagementView.swift
// 标签管理主页 - 地块、标签、状态三个标签页

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
                        title: L10n.TagManagement.headerTitle,
                        subtitle: L10n.TagManagement.headerSubtitle,
                        icon: "tag",
                        accent: Design.Colors.harvest
                    )
                    .padding(.horizontal, Design.Space.md)
                    .padding(.top, Design.Space.md)

                    // Tab Picker
                    Picker(L10n.TagManagement.tabPickerLabel, selection: $selectedTab) {
                        Text(L10n.TagManagement.plotsTab).tag(0)
                        Text(L10n.TagManagement.tagsTab).tag(1)
                        Text(L10n.TagManagement.statusTab).tag(2)
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
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.done) {
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
