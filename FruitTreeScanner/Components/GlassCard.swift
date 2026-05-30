// GlassCard.swift
// 玻璃拟态卡片组件

import SwiftUI

// MARK: - Glass Card
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
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.2),
                Color.white.opacity(0.05),
                Color.white.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glass Section Header
struct GlassSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
            }

            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .tracking(2)

            Spacer()
        }
        .padding(.horizontal, Design.Space.xs)
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

                    Text(title)
                        .font(Design.Typography.darkHeadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(Design.Space.md)
            }
            .buttonStyle(DarkGlassButtonStyle())

            // Content
            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
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
                .fill(Color.white.opacity(isPressed ? 0.1 : 0.03))
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressed)
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

    var body: some View {
        GlassRow(icon: icon, title: title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Design.Colors.harvest)
        }
    }
}

// MARK: - Glass Picker Row
struct GlassPickerRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        GlassRow(icon: icon, title: title) {
            Text(value)
                .font(Design.Typography.darkCaption)
                .foregroundColor(Design.Colors.harvest)
        }
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
    }
}

// MARK: - Glass Slider Row (不使用 GlassRow，避免手势冲突)
struct GlassSliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: String

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            // 标题行
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

            // Slider 独立，不被手势干扰
            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.harvest)
                .padding(.horizontal, Design.Space.md)
                .padding(.bottom, Design.Space.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Color.white.opacity(0.03))
        )
    }
}

#Preview {
    ZStack {
        Design.Colors.Dark.bgDeep.ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                VStack(alignment: .leading) {
                    GlassSectionHeader("设备", icon: "cpu")
                    GlassReadonlyRow(icon: "rectangle", title: "分辨率", value: "1920×1080")
                    GlassDivider()
                    GlassPickerRow(icon: "speedometer", title: "检测频率", value: "60fps")
                }
            }

            GlassExpandableSection(title: "数据", icon: "externaldrive", isExpanded: .constant(true)) {
                GlassToggleRow(icon: "doc.text", title: "自动导出", isOn: .constant(true))
            }
        }
        .padding()
    }
}
