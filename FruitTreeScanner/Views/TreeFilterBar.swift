// TreeFilterBar.swift
// Horizontal filter controls for the tree list.

import SwiftUI

struct TreeFilterBar: View {
    @ObservedObject var tagStore: TagStore

    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus?

    private var selectedPlotTitle: String {
        guard let selectedPlotId else { return "全部地块" }
        return tagStore.getPlot(id: selectedPlotId)?.name ?? "地块"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Space.sm) {
                plotFilter
                tagFilter
                statusFilter
            }
        }
    }

    private var plotFilter: some View {
        FilterChip(title: selectedPlotTitle, isSelected: selectedPlotId != nil) {
            Button("全部地块") { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button(plot.name) { selectedPlotId = plot.id }
            }
        }
    }

    private var tagFilter: some View {
        FilterChip(
            title: selectedTagIds.isEmpty ? "全部标签" : "\(selectedTagIds.count) 个标签",
            isSelected: !selectedTagIds.isEmpty
        ) {
            Button("全部标签") { selectedTagIds.removeAll() }
            Divider()
            ForEach(tagStore.tags) { tag in
                Button {
                    toggleTag(tag.id)
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
    }

    private var statusFilter: some View {
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

    private func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
        } else {
            selectedTagIds.insert(tagId)
        }
    }
}
