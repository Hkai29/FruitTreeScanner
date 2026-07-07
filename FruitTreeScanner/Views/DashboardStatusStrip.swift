import SwiftUI

struct DashboardStatusStrip: View {
    let records: [ScanFileRecord]

    private var summary: DashboardDailySummary {
        DashboardDailySummary(records: records)
    }

    var body: some View {
        HStack(spacing: 10) {
            DashboardStatusItem(title: "今日", value: "\(summary.scanCount)", suffix: "次")
            DashboardStatusItem(title: "产量", value: String(format: "%.1f", summary.yieldKg), suffix: "kg")
            DashboardStatusItem(title: "树体", value: "\(summary.treeCount)", suffix: "棵")
        }
    }
}

private struct DashboardStatusItem: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(suffix)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Dark.bgElevated.opacity(0.55))
        .cornerRadius(8)
    }
}
