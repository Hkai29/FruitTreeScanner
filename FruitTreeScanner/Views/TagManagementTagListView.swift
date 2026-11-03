// TagManagementTagListView.swift
// 标签列表：白底列表组 + 发丝线分隔，树数来自真实分配关系。

import SwiftUI

struct TagListView: View {
    let tags: [GroupTag]
    let treeCount: (UUID) -> Int
    let onEdit: (GroupTag) -> Void
    let onDelete: (GroupTag) -> Void
    let onAdd: () -> Void

    private let contentWidth: CGFloat = 1080

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                } else {
                    InstrumentRowGroup {
                        ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                            TagRowView(
                                tag: tag,
                                treeCount: treeCount(tag.id),
                                onEdit: { onEdit(tag) },
                                onDelete: { onDelete(tag) }
                            )
                            if index < tags.count - 1 {
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
