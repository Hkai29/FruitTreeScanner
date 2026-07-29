// GlassCard.swift
// 深色表面组件

import SwiftUI

// MARK: - Surface Card
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = Design.Radius.Glass.medium,
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
            .darkSurface(cornerRadius: cornerRadius)
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.harvest)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(Design.Typography.darkHeadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .padding(Design.Space.md)
            }
            .buttonStyle(DarkGlassButtonStyle())
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
        .background(Design.Colors.Dark.glassFill)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.Glass.medium))
    }
}

// MARK: - Glass Row
struct GlassRow<Right: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let right: () -> Right

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)

            Text(title)
                .font(Design.Typography.darkSubheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            right()
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(isPressed ? Color.white.opacity(0.07) : Design.Colors.Dark.bgElevated.opacity(0.55))
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: Design.Animation.micro), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Glass Divider
struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Design.Colors.Dark.glassBorder)
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

// MARK: - Glass Toggle Row
struct GlassToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var accessibilityHint: String = ""

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Toggle(isOn: $isOn) {
                Text(title)
                    .font(Design.Typography.darkSubheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }
            .tint(Design.Colors.harvest)
            .accessibilityHint(accessibilityHint)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.bgElevated.opacity(0.55))
        )
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
                .font(Design.Typography.darkCaption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
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
        VStack(spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(width: 24)

                Text(title)
                    .font(Design.Typography.darkSubheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()

                Text(displayValue)
                    .font(Design.Typography.hudValue)
                    .foregroundColor(Design.Colors.harvest)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm + 2)
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                .tint(Design.Colors.harvest)
                .padding(.horizontal, Design.Space.md)
                .padding(.bottom, Design.Space.sm)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
                .accessibilityHint(accessibilityHint)
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.bgElevated.opacity(0.55))
        )
    }
}
