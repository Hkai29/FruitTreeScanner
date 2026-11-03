// TreeFilterBar.swift
// 果树档案筛选条：地块、标签、状态。
//
// 地块与标签是"从库里挑一个"的集合，用菜单型筛选片；
// 状态只有固定几种，直接用筛选片一行排开，所见即所得。

import SwiftUI

struct TreeFilterBar: View {
    @ObservedObject var tagStore: TagStore

    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus?

    private var selectedPlotTitle: String {
        guard let selectedPlotId else { return TreeFilterText.allPlots }
        return tagStore.getPlot(id: selectedPlotId)?.name ?? L10n.History.plotFallback
    }

    private var selectedTagTitle: String {
        selectedTagIds.isEmpty
            ? TreeFilterText.allTags
            : TreeFilterText.selectedTagsFormat(selectedTagIds.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                plotFilter
                tagFilter
            }

            FlowLayout(spacing: 8) {
                statusChips
            }
        }
    }

    private var plotFilter: some View {
        FilterChip(title: selectedPlotTitle, isSelected: selectedPlotId != nil) {
            Button(TreeFilterText.allPlots) { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button(plot.name) { selectedPlotId = plot.id }
            }
        }
    }

    private var tagFilter: some View {
        FilterChip(title: selectedTagTitle, isSelected: !selectedTagIds.isEmpty) {
            Button(TreeFilterText.allTags) { selectedTagIds.removeAll() }
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

    private var statusChips: some View {
        Group {
            InstrumentChip(title: TreeFilterText.allStatuses, isSelected: selectedStatus == nil) {
                selectedStatus = nil
            }
            ForEach(ScanStatus.allCases, id: \.self) { status in
                InstrumentChip(
                    title: L10n.History.statusName(for: status),
                    isSelected: selectedStatus == status
                ) {
                    selectedStatus = status
                }
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
