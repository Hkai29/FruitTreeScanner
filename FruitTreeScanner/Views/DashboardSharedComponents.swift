// DashboardSharedComponents.swift
// 仪表盘共享组件。统一为仪器式排版：发丝线、小标签、等宽读数。

import SwiftUI

struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .instrumentLabel()
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSurface(cornerRadius: Design.Radius.medium)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

struct DashboardSectionHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        headerLayout {
            Text(title)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }
}

/// 工具页标题。取代原先的“图片 + 暗色渐变”英雄块。
struct DashboardToolHeader: View {
    let imageName: String
    let title: String
    let subtitle: String
    var icon: String
    var accent: Color = Design.Colors.Workspace.accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(accent.opacity(0.10))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Mini Icon Badge

struct DashboardMiniIcon: View {
    let icon: String
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .regular))
            .foregroundColor(Design.Colors.Workspace.accent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.accentSoft)
            )
    }
}

struct DashboardSheetAction {
    let title: String
    let icon: String
    let action: () -> Void
}

extension View {
    func darkSurface(
        cornerRadius: CGFloat,
        fill: Color = Design.Colors.Dark.bgSurface.opacity(0.96)
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }

    func dashboardSurface(cornerRadius: CGFloat) -> some View {
        workspaceSurface(cornerRadius: cornerRadius)
    }
}
