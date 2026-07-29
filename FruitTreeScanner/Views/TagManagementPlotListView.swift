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
                    title: "暂无地块",
                    message: "添加地块后，可把果树扫描记录归到具体区域。",
                    primaryAction: DashboardSheetAction(title: "添加地块", icon: "plus", action: onAdd)
                )
            }
        }
    }
}
