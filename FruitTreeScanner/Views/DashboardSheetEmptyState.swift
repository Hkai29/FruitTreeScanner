import SwiftUI

/// 空状态版式：常规字号横排，辅助字号竖排。
enum DashboardSheetEmptyStateLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize, adaptsForAccessibility: Bool) {
        self = adaptsForAccessibility && dynamicTypeSize.isAccessibilitySize
            ? .stacked
            : .horizontal
    }
}

/// 统一的空状态。
///
/// 只说三件事：现在没有什么、为什么、下一步做什么。
/// 不画不存在的图表，不用插图磁贴。
struct DashboardSheetEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    var imageName: String? = nil
    let title: String
    let message: String
    var accent: Color = Design.Colors.Workspace.accent
    var primaryAction: DashboardSheetAction? = nil
    var secondaryAction: DashboardSheetAction? = nil
    var outerPadding: Bool = true
    var adaptsForAccessibility: Bool = true

    private var layout: DashboardSheetEmptyStateLayout {
        DashboardSheetEmptyStateLayout(
            dynamicTypeSize: dynamicTypeSize,
            adaptsForAccessibility: adaptsForAccessibility
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentLayout

            if primaryAction != nil || secondaryAction != nil {
                actionLayout
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(outerPadding ? Design.Space.lg : 0)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var contentLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(
                    accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(message))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var actionLayout: some View {
        if layout == .stacked {
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

    @ViewBuilder
    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        let button = Button(action: action.action) {
            Label(action.title, systemImage: action.icon)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }

        if isPrimary {
            button.buttonStyle(WorkspacePrimaryButtonStyle())
        } else {
            button.buttonStyle(WorkspaceSecondaryButtonStyle())
        }
    }
}
