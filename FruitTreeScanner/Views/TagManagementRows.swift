import SwiftUI

struct PlotRowView: View {
    let plot: Plot
    let treeCount: Int

    var body: some View {
        TagManagementRow(
            colorHex: plot.colorHex,
            title: plot.name,
            detail: "\(treeCount) 棵树"
        )
    }
}

struct TagRowView: View {
    let tag: GroupTag
    let treeCount: Int

    var body: some View {
        TagManagementRow(
            colorHex: tag.colorHex,
            title: tag.name,
            detail: "\(treeCount) 棵树"
        )
    }
}

private struct TagManagementRow: View {
    let colorHex: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: colorHex))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.vertical, 7)
        .listRowBackground(Design.Colors.Dark.bgDeep)
    }
}
