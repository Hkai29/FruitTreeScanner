// TagManagementView.swift
// 标签管理主页 - 地块、标签、状态三个标签页

import SwiftUI

struct TagManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tagStore = TagStore.shared
    var onStartScan: (() -> Void)? = nil
    @State private var selectedTab: Int = 0
    @State private var showingAddPlot: Bool = false
    @State private var showingAddTag: Bool = false
    @State private var editingPlot: Plot?
    @State private var editingTag: GroupTag?

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
                            onEdit: { editingPlot = $0 },
                            onDelete: { tagStore.deletePlot(id: $0) },
                            onAdd: { showingAddPlot = true }
                        )
                        .tag(0)

                        TagListView(
                            tags: tagStore.tags,
                            treeCount: { tagStore.treeCount(forTagId: $0) },
                            onEdit: { editingTag = $0 },
                            onDelete: { tagStore.deleteTag(id: $0) },
                            onAdd: { showingAddTag = true }
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

    private func showAddSheet() {
        if selectedTab == 0 {
            showingAddPlot = true
        } else if selectedTab == 1 {
            showingAddTag = true
        }
    }
}
