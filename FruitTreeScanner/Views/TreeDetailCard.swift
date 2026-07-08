import SwiftUI

struct TreeDetailCard: View {
    let tree: TreeAnnotation
    let onClose: () -> Void

    private var confidence: (label: String, color: Color) {
        switch tree.confidence {
        case "high": return ("高", Design.Colors.Dark.success)
        case "medium": return ("中", Design.Colors.Dark.warning)
        default: return ("低", Design.Colors.Dark.error)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            header
            DividerLine()
            statsRow
            yieldBadgeRow
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private var header: some View {
        HStack {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: tree.yieldLevel.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(tree.yieldLevel.color)

                Text("树 #\(tree.treeID)")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: Design.Space.xl) {
            TreeStatItem(label: "预估产量", value: String(format: "%.1f kg", tree.weight), color: Design.Colors.Dark.glow)
            TreeStatItem(label: "果实数", value: "\(tree.fruitCount) 个", color: Design.Colors.Dark.glow)
            TreeStatItem(label: "置信度", value: confidence.label, color: confidence.color)
            TreeStatItem(label: "扫描日期", value: formatDate(tree.scanDate), color: Design.Colors.Dark.textSecondary)
        }
    }

    private var yieldBadgeRow: some View {
        HStack {
            Text("产量等级")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            HStack(spacing: Design.Space.xs) {
                Circle()
                    .fill(tree.yieldLevel.color)
                    .frame(width: 8, height: 8)

                Text(tree.yieldLevel.label)
                    .font(Design.Typography.captionMedium)
                    .foregroundColor(tree.yieldLevel.color)
            }
            .padding(.horizontal, Design.Space.sm)
            .padding(.vertical, Design.Space.xs)
            .background(tree.yieldLevel.color.opacity(0.1))
            .cornerRadius(Design.Radius.full)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}
