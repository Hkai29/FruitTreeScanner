// GlassCard.swift
// 共享容器与设置行。统一为发丝线 + 纸面 + 等宽读数的仪器排版。

import SwiftUI

// MARK: - Surface Card
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = Design.Radius.medium,
        padding: CGFloat = Design.Space.md,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .workspaceSurface(cornerRadius: cornerRadius)
    }
}

// MARK: - Glass Expandable Section
struct GlassExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: Design.Animation.standard)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    Text(title)
                        .instrumentLabel()
                        .foregroundColor(Design.Colors.Workspace.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Design.Colors.Workspace.faint)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? L10n.Settings.sectionExpanded : L10n.Settings.sectionCollapsed)
            .accessibilityHint(L10n.Settings.sectionToggleHint)

            // Content
            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

// MARK: - Glass Row
struct GlassRow<Right: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let right: () -> Right

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.ink)

            Spacer()

            right()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: Design.Touch.minimumHeight)
        .background(isPressed ? Design.Colors.Workspace.inset.opacity(0.6) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Glass Divider
struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(height: 0.5)
            .padding(.leading, 46)
    }
}

// MARK: - Glass Toggle Row
struct GlassToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var accessibilityHint: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
            }
            .tint(Design.Colors.Workspace.accent)
            .accessibilityHint(accessibilityHint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - Glass Readonly Row
struct GlassReadonlyRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        GlassRow(icon: icon, title: title) {
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Glass Slider Row (不使用 GlassRow，避免手势冲突)
struct GlassSliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    var displayValue: String { customDisplayValue ?? defaultDisplayValue }
    var customDisplayValue: String?
    var accessibilityHint: String = ""

    private var defaultDisplayValue: String {
        if step >= 1 {
            return "\(Int(value))"
        }
        return String(format: "%.3f", value)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)

                Spacer()

                Text(displayValue)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                .tint(Design.Colors.Workspace.accent)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
                .accessibilityHint(accessibilityHint)
        }
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}
