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
                let count = treeCount(tag.id)
                Button {
                    onEdit(tag)
                } label: {
                    TagRowView(tag: tag, treeCount: count)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.name)
                .accessibilityValue(L10n.TagManagement.treeCount(count))
                .accessibilityHint(L10n.TagManagement.editTagHint)
                .accessibilityAction(named: Text(L10n.TagManagement.deleteTagAction)) {
                    onDelete(tag)
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
                    title: L10n.TagManagement.tagsEmptyTitle,
                    message: L10n.TagManagement.tagsEmptyMessage,
                    primaryAction: DashboardSheetAction(
                        title: L10n.TagManagement.addTag,
                        icon: "plus",
                        action: onAdd
                    )
                )
            }
        }
    }
}
