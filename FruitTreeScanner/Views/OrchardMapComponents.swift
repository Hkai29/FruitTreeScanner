import SwiftUI

struct OrchardMapEmptyState: View {
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "map",
                imageName: "FeatureMap",
                title: "暂无定位扫描",
                message: "带 GPS 的扫描记录会显示在果园地图中，用于查看产量分布。",
                accent: Design.Colors.Dark.info,
                primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
                outerPadding: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 84)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
        .ignoresSafeArea()
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct OrchardMapTopBar: View {
    let treeCount: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }

            Spacer()

            if treeCount > 0 {
                Text("\(treeCount) 棵果树")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Capsule())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }
        }
    }
}

struct OrchardMapBottomPanel: View {
    let selectedTree: TreeAnnotation?
    let filteredTrees: [TreeAnnotation]
    @Binding var filterYieldLevel: YieldLevel?
    let onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: Design.Space.md) {
            OrchardMapLegend(filterYieldLevel: $filterYieldLevel)

            if let selectedTree {
                TreeDetailCard(tree: selectedTree, onClose: onClearSelection)
            } else {
                TreeCountCard(filteredTrees: filteredTrees)
            }
        }
    }
}

struct OrchardMapLegend: View {
    @Binding var filterYieldLevel: YieldLevel?

    var body: some View {
        HStack(spacing: Design.Space.lg) {
            ForEach([YieldLevel.high, .medium, .low], id: \.self) { level in
                Button {
                    toggle(level)
                } label: {
                    HStack(spacing: Design.Space.xs) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 10, height: 10)

                        Text(level.label)
                            .font(Design.Typography.caption)
                            .foregroundColor(filterYieldLevel == level ? level.color : Design.Colors.Dark.textPrimary)
                    }
                    .padding(.horizontal, Design.Space.sm)
                    .padding(.vertical, Design.Space.xs)
                    .background(filterYieldLevel == level ? level.color.opacity(0.1) : Color.clear)
                    .cornerRadius(Design.Radius.full)
                }
            }

            Spacer()

            if filterYieldLevel != nil {
                Button {
                    filterYieldLevel = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private func toggle(_ level: YieldLevel) {
        filterYieldLevel = filterYieldLevel == level ? nil : level
    }
}

struct TreeCountCard: View {
    private let summary: TreeYieldSummary

    init(filteredTrees: [TreeAnnotation]) {
        self.summary = TreeYieldSummary(trees: filteredTrees)
    }

    var body: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("园区树木")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text("\(summary.totalCount) 棵")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Spacer()

            HStack(spacing: Design.Space.lg) {
                YieldStatMini(level: .high, count: summary.count(for: .high))
                YieldStatMini(level: .medium, count: summary.count(for: .medium))
                YieldStatMini(level: .low, count: summary.count(for: .low))
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }
}

struct TreeDetailCard: View {
    let tree: TreeAnnotation
    let onClose: () -> Void

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

    private var confidence: (label: String, color: Color) {
        switch tree.confidence {
        case "high": return ("高", Design.Colors.Dark.success)
        case "medium": return ("中", Design.Colors.Dark.warning)
        default: return ("低", Design.Colors.Dark.error)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

private var orchardFloatingSurface: some View {
    RoundedRectangle(cornerRadius: Design.Radius.large)
        .fill(Design.Colors.Dark.bgSurface)
        .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
}
