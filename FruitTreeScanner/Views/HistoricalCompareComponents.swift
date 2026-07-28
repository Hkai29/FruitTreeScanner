import SwiftUI

struct HistoricalCompareEmptyState: View {
    let scanCount: Int
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        DashboardSheetEmptyState(
            icon: "arrow.left.arrow.right",
            imageName: "FeatureCompare",
            title: "至少需要两条完整扫描",
            message: "当前只有 \(scanCount) 条可用记录。完成两次扫描并保存完整结果后，就可以比较产量、果数和日期变化。",
            accent: Design.Colors.harvest,
            primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
            outerPadding: false
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct HistoricalComparePrompt: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.forest)
                .frame(width: 24, height: 24)

            Text("选择两条扫描记录后，会显示产量、果实数和日期的并排对比。")
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct ScanSelectionCard: View {
    let scan: ScanItem?
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Design.Space.md) {
                if let scan {
                    selectedContent(scan)
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.md)
            .padding(.horizontal, Design.Space.sm)
            .background(Design.Colors.Dark.bgSurface)
            .cornerRadius(10)
            .overlay(border)
        }
        .buttonStyle(.plain)
    }

    private func selectedContent(_ scan: ScanItem) -> some View {
        VStack(spacing: 4) {
            Text("树 #\(scan.treeID)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(scan.dateFormatted)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(scan.yieldFormatted)
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.Dark.glow)
        }
    }

    private var emptyContent: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
            Text("选择扫描")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Design.Colors.Dark.textSecondary)
        .frame(minHeight: 54)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(scan != nil ? Design.Colors.Dark.glow.opacity(0.3) : Design.Colors.sand, lineWidth: 1.5)
    }
}

struct StatCompareCard: View {
    let title: String
    let value1: String
    let value2: String
    let unit: String
    let icon: String
    let trend: TrendDirection

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            header
            values
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(10)
    }

    private var header: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(title)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var values: some View {
        HStack {
            CompareValueColumn(value: value1, unit: unit, alignment: .leading)

            Spacer()

            Image(systemName: trend.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(trend.color)

            Spacer()

            CompareValueColumn(value: value2, unit: unit, alignment: .trailing)
        }
    }
}

private struct CompareValueColumn: View {
    let value: String
    let unit: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
            if !unit.isEmpty && value != "--" {
                Text(unit)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
    }
}
