// TagManagementPlotListView.swift
// 地块列表：白底列表组 + 发丝线分隔，树数来自真实分配关系。

import SwiftUI

struct PlotListView: View {
    let plots: [Plot]
    let treeCount: (UUID) -> Int
    let onEdit: (Plot) -> Void
    let onDelete: (Plot) -> Void
    let onAdd: () -> Void

    private let contentWidth: CGFloat = 1080

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if plots.isEmpty {
                    TagManagementEmptyState(
                        icon: "map",
                        imageName: "FeatureTagManagement",
                        title: L10n.TagManagement.plotsEmptyTitle,
                        message: L10n.TagManagement.plotsEmptyMessage,
                        primaryAction: DashboardSheetAction(
                            title: L10n.TagManagement.addPlot,
                            icon: "plus",
                            action: onAdd
                        )
                    )
                } else {
                    InstrumentRowGroup {
                        ForEach(Array(plots.enumerated()), id: \.element.id) { index, plot in
                            PlotRowView(
                                plot: plot,
                                treeCount: treeCount(plot.id),
                                onEdit: { onEdit(plot) },
                                onDelete: { onDelete(plot) }
                            )
                            if index < plots.count - 1 {
                                DividerLine(inset: 0)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}
