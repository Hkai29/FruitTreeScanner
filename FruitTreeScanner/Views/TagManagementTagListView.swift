import SwiftUI

struct TagListView: View {
    let tags: [GroupTag]
    let treeCount: (UUID) -> Int
    let onEdit: (GroupTag) -> Void
    let onDelete: (GroupTag) -> Void
    let onAdd: () -> Void

    var body: some View {
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
                    onDelete(tags[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if tags.isEmpty {
                TagManagementEmptyState(
                    icon: "tag",
                    imageName: "FeatureTagManagement",
                    title: "暂无标签",
                    message: "标签用于标记试验组、品种批次或管理状态。",
                    primaryAction: DashboardSheetAction(title: "添加标签", icon: "plus", action: onAdd)
                )
            }
        }
    }
}
