import SwiftUI

enum DashboardSheetEmptyStateLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize, adaptsForAccessibility: Bool) {
        self = adaptsForAccessibility && dynamicTypeSize.isAccessibilitySize
            ? .stacked
            : .horizontal
    }
}

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
    var adaptsForAccessibility: Bool = false

    private var layout: DashboardSheetEmptyStateLayout {
        DashboardSheetEmptyStateLayout(
            dynamicTypeSize: dynamicTypeSize,
            adaptsForAccessibility: adaptsForAccessibility
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if primaryAction != nil || secondaryAction != nil {
                actionSection
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
    private var header: some View {
        if layout == .stacked {
            VStack(alignment: .leading, spacing: 12) {
                featureImage
                textContent
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                featureImage
                textContent
            }
        }
    }

    @ViewBuilder
    private var featureImage: some View {
        if let imageName {
            if layout == .stacked {
                DashboardFeatureImage(name: imageName, accent: accent)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(adaptsForAccessibility)
            } else {
                DashboardFeatureImage(name: imageName, accent: accent)
                    .frame(width: 96, height: 76)
                    .accessibilityHidden(adaptsForAccessibility)
            }
        }
    }

    @ViewBuilder
    private var textContent: some View {
        if adaptsForAccessibility {
            textContentBody
                .accessibilityElement(children: .combine)
        } else {
            textContentBody
        }
    }

    private var textContentBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(adaptsForAccessibility)

                Text(title)
                    .font(adaptsForAccessibility ? .headline : .system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Text(message)
                .font(adaptsForAccessibility ? .body : .system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if layout == .stacked {
            VStack(spacing: 10) {
                actionButtons
            }
        } else {
            HStack(spacing: 10) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let primaryAction {
            actionButton(primaryAction, isPrimary: true)
        }
        if let secondaryAction {
            actionButton(secondaryAction, isPrimary: false)
        }
    }

    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            actionLabel(action)
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .background(isPrimary ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionLabel(_ action: DashboardSheetAction) -> some View {
        if adaptsForAccessibility {
            Label(action.title, systemImage: action.icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: Design.Touch.minimumHeight)
        } else {
            Label(action.title, systemImage: action.icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
        }
    }
}
