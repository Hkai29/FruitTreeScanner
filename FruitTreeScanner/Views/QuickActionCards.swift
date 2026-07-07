import SwiftUI

struct QuickActionCard: View {
    let action: QuickAction
    var compactLandscape: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: compactLandscape ? 8 : 12) {
                DashboardFeatureImage(name: action.imageName, accent: action.color)
                    .frame(width: compactLandscape ? 42 : 76, height: compactLandscape ? 40 : 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: compactLandscape ? 13 : 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .lineLimit(1)
                    Text(action.description)
                        .font(.system(size: compactLandscape ? 10 : 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .lineLimit(compactLandscape ? 1 : 2)
                }

                Spacer(minLength: compactLandscape ? 4 : 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compactLandscape ? 8 : 10)
            .background(Design.Colors.Dark.bgElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.black.opacity(0.20), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title)，\(action.description)")
        .accessibilityIdentifier("dashboard.action.\(action.kind.rawValue)")
    }
}

struct DashboardToolGroup: View {
    let title: String
    let icon: String
    let actions: [QuickAction]
    var compactLandscape: Bool = false
    var onAction: ((QuickAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compactLandscape ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvestLight)
                    .frame(width: compactLandscape ? 24 : 26, height: compactLandscape ? 24 : 26)
                    .background(Design.Colors.harvest.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(title)
                    .font(.system(size: compactLandscape ? 12 : 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
            }

            ForEach(actions) { action in
                QuickActionCard(action: action, compactLandscape: compactLandscape) {
                    onAction?(action)
                }
            }
        }
        .padding(compactLandscape ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardSurface(cornerRadius: 10)
    }
}

struct QuickActionTile: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 6) {
                DashboardFeatureImage(name: action.imageName, accent: action.color, cornerRadius: 7)
                    .frame(height: 34)

                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(action.color)
                        .frame(width: 18, height: 18)

                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Text(action.description)
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .background(Design.Colors.Dark.bgElevated.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title)，\(action.description)")
        .accessibilityIdentifier("dashboard.action.\(action.kind.rawValue)")
    }
}
