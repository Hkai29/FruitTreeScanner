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
            contentLayout

            if primaryAction != nil || secondaryAction != nil {
                actionLayout
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .padding(outerPadding ? Design.Space.lg : 0)
        .frame(maxWidth: .infinity, maxHeight: outerPadding ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private var contentLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                featureImage(width: nil, height: 112)
                textContent
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                featureImage(width: 96, height: 76)
                textContent
            }
        }
    }

    @ViewBuilder
    private func featureImage(width: CGFloat?, height: CGFloat) -> some View {
        if let imageName {
            DashboardFeatureImage(name: imageName, accent: accent)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(message)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(message))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var actionLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalActions
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalActions
                verticalActions
            }
        }
    }

    private var horizontalActions: some View {
        HStack(spacing: 10) {
            if let primaryAction {
                actionButton(primaryAction, isPrimary: true)
            }
            if let secondaryAction {
                actionButton(secondaryAction, isPrimary: false)
            }
        }
    }

    private var verticalActions: some View {
        VStack(spacing: 10) {
            if let primaryAction {
                actionButton(primaryAction, isPrimary: true)
            }
            if let secondaryAction {
                actionButton(secondaryAction, isPrimary: false)
            }
        }
    }

    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
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
        .accessibilityLabel(Text(action.title))
    }
}
