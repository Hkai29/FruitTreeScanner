import SwiftUI

struct RecentScansSection: View {
    var scans: [ScanFileRecord]
    var onViewAll: (() -> Void)? = nil
    var onScanTap: ((ScanFileRecord) -> Void)? = nil
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                title: "最近扫描",
                actionTitle: "查看全部",
                onAction: onViewAll
            )

            if scans.isEmpty {
                emptyRecentScans
            } else {
                VStack(spacing: 12) {
                    ForEach(scans) { record in
                        Button {
                            onScanTap?(record)
                        } label: {
                            RecentScanCard(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看 \(record.treeID) 点云")
                    }
                }
            }
        }
        .padding(16)
        .dashboardSurface(cornerRadius: 12)
    }

    private var emptyRecentScans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("DashboardRecentEmpty")
                .resizable()
                .scaledToFill()
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.06),
                            Color.black.opacity(0.56)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("还没有扫描记录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text("完成第一次扫描后，这里会显示最近树体、产量和点云入口。")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onStartScan {
                Button(action: onStartScan) {
                    Label("开始第一次扫描", systemImage: "viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Design.Colors.harvest)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentScanCard: View {
    let record: ScanFileRecord

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.scanDate)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Design.Colors.harvest.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundColor(Design.Colors.harvestLight)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.treeID)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
                Text(dateString)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f kg", record.yieldKg))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text("\(record.fruitCount) 个果实")
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding(12)
        .background(Design.Colors.Dark.bgElevated.opacity(0.58))
        .cornerRadius(8)
    }
}

struct StatsOverviewSection: View {
    var records: [ScanFileRecord] = []

    private var summary: DashboardDailySummary { DashboardDailySummary(records: records) }

    private var todaysYield: Float {
        summary.yieldKg
    }

    private var todaysTrees: Int {
        summary.treeCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(title: "今日概览")
            HStack(spacing: 16) {
                StatCard(value: "\(summary.scanCount)", label: "扫描数量", icon: "viewfinder", color: Design.Colors.harvest)
                StatCard(value: String(format: "%.1f", todaysYield), label: "总产量/kg", icon: "scalemass.fill", color: Design.Colors.harvest)
                StatCard(value: "\(todaysTrees)", label: "树编号", icon: "tree.fill", color: Design.Colors.Dark.info)
            }
        }
        .padding(16)
        .dashboardSurface(cornerRadius: 12)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Design.Colors.Dark.bgElevated.opacity(0.58))
        .cornerRadius(8)
    }
}
