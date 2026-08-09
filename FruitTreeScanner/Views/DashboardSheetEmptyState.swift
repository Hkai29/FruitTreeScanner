import SwiftUI

struct DashboardSheetEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if let imageName, !dynamicTypeSize.isAccessibilitySize {
                    DashboardFeatureImage(name: imageName, accent: accent)
                        .frame(width: 96, height: 76)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(accent)
                            .padding(6)
                            .background(accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)

                        Text(title)
                            .font(.headline)
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            if primaryAction != nil || secondaryAction != nil {
                actionLayout {
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

    private var actionLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(spacing: 10))
        }
        return AnyLayout(HStackLayout(spacing: 10))
    }

    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            actionLabel(action)
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 4 : 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(isPrimary ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }

    @ViewBuilder
    private func actionLabel(_ action: DashboardSheetAction) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(action.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } else {
            Label(action.title, systemImage: action.icon)
                .font(.caption.weight(.semibold))
        }
    }
}
