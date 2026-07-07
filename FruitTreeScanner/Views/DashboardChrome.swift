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
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Design.Colors.harvest.opacity(0.18), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Design.Brand.productName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(Design.Brand.productTagline)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: { onHistoryTap?() }) {
                HStack(spacing: 6) {
                    DashboardMiniIcon(icon: "clock.arrow.circlepath", size: 28)
                        .accessibilityHidden(true)
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
                DashboardMiniIcon(icon: "gearshape.fill", size: 44)
            }
            .accessibilityLabel("设置")
        }
    }
}
