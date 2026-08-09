import SwiftUI

struct PlotListView: View {
    let plots: [Plot]
    let treeCount: (UUID) -> Int
    let onEdit: (Plot) -> Void
    let onDelete: (Plot) -> Void
    let onAdd: () -> Void

    var body: some View {
        List {
            ForEach(plots) { plot in
                let count = treeCount(plot.id)
                Button {
                    onEdit(plot)
                } label: {
                    PlotRowView(plot: plot, treeCount: count)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(plot.name)
                .accessibilityValue(L10n.TagManagement.treeCount(count))
                .accessibilityHint(L10n.TagManagement.editPlotHint)
                .accessibilityAction(named: Text(L10n.TagManagement.deletePlotAction)) {
                    onDelete(plot)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    onDelete(plots[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
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
            }
        }
    }
}
