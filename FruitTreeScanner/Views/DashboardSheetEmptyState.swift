import SwiftUI

struct DashboardSheetEmptyState: View {
    let icon: String
    var imageName: String? = nil
    let title: String
    let message: String
    var accent: Color = Design.Colors.harvest
    var primaryAction: DashboardSheetAction? = nil
    var secondaryAction: DashboardSheetAction? = nil
    var outerPadding: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let imageName {
                    DashboardFeatureImage(name: imageName, accent: accent)
                        .frame(width: 96, height: 76)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 26, height: 26)
                            .background(accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                    }

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 10) {
                    if let primaryAction {
                        actionButton(primaryAction, isPrimary: true)
                    }
                    if let secondaryAction {
                        actionButton(secondaryAction, isPrimary: false)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .padding(outerPadding ? Design.Space.lg : 0)
        .frame(maxWidth: .infinity, maxHeight: outerPadding ? .infinity : nil, alignment: .top)
    }

    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isPrimary ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
