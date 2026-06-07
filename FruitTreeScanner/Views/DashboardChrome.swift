import SwiftUI

struct TopNavigationBar: View {
    let onSettingsTap: () -> Void
    var onHistoryTap: (() -> Void)? = nil
    var historyCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            brand
            Spacer()
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Design.Colors.Dark.bgElevated)
                    .frame(width: 44, height: 44)
                Image(systemName: "cube.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Design.Colors.harvest, Design.Colors.harvestLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("FruitScanner")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text("果树 LiDAR 扫描")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: { onHistoryTap?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    if historyCount > 0 {
                        Text("\(historyCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "1C1C1E"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Design.Colors.harvest)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(Capsule())
                .frame(minWidth: Design.Touch.minimumWidth, minHeight: Design.Touch.minimumHeight)
            }
            .accessibilityLabel("扫描历史\(historyCount > 0 ? "，\(historyCount)条记录" : "")")

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Design.Colors.Dark.bgElevated)
                    .clipShape(Circle())
            }
            .accessibilityLabel("设置")
        }
    }
}

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

struct DashboardHeroPanel: View {
    let records: [ScanFileRecord]
    let onStartScan: () -> Void
    let onQuickScan: () -> Void

    private var summary: DashboardDailySummary {
        DashboardDailySummary(records: records)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("DashboardHero")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 226)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.74),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("果园扫描工作台")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                        Text("LiDAR 采集 · 点云记录 · 产量分析")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("现场")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.32))
                    .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    DashboardHeroMetric(title: "今日", value: "\(summary.scanCount)", suffix: "次")
                    DashboardHeroMetric(title: "产量", value: String(format: "%.1f", summary.yieldKg), suffix: "kg")
                    DashboardHeroMetric(title: "树体", value: "\(summary.treeCount)", suffix: "棵")
                }

                HStack(spacing: 10) {
                    DashboardHeroButton(
                        title: "新建扫描",
                        icon: "viewfinder",
                        imageName: "FeatureStartScan",
                        isPrimary: true,
                        action: onStartScan
                    )

                    DashboardHeroButton(
                        title: "快速采集",
                        icon: "bolt.fill",
                        imageName: "FeatureQuickScan",
                        isPrimary: false,
                        action: onQuickScan
                    )
                }
            }
            .padding(16)
        }
        .frame(height: 226)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: Color.black.opacity(0.22),
            radius: 12,
            y: 5
        )
    }
}

private struct DashboardHeroMetric: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(suffix)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct DashboardHeroButton: View {
    let title: String
    let icon: String
    let imageName: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                DashboardFeatureImage(
                    name: imageName,
                    accent: isPrimary ? Design.Colors.harvestDark : Design.Colors.Dark.info,
                    cornerRadius: 7
                )
                .frame(width: 34, height: 30)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
                .foregroundColor(isPrimary ? Color(hex: "171B14") : Design.Colors.Dark.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isPrimary ? Design.Colors.harvestLight : Color.black.opacity(0.34))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Design.Colors.harvest.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(ScaleButtonStyle())
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

struct DashboardPrimaryActions: View {
    let onStartScan: () -> Void
    let onQuickScan: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStartScan) {
                Label("新建扫描", systemImage: "viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.Colors.harvest)

            Button(action: onQuickScan) {
                Label("快速采集", systemImage: "bolt")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(Design.Colors.Dark.textPrimary)
        }
    }
}
