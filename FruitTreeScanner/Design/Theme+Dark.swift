// Theme+Dark.swift
// 专业扫描软件暗色主题扩展

import SwiftUI

// MARK: - Dark Theme Extension
extension Design.Colors {
    /// 专业扫描软件暗色主题颜色
    struct Dark {
        // 背景层次
        static let bgDeep = Color(hex: "0A0A0F")           // 极深背景
        static let bgSurface = Color(hex: "14141A")        // 卡片表面
        static let bgElevated = Color(hex: "1E1E26")       // 浮起元素

        // 发光效果 - 橙色 (Harvest)
        static let glow = Design.Colors.harvest             // #FF9500
        static let glowLight = Design.Colors.harvestLight   // #FF9F0A

        // 文字颜色
        static let textPrimary = Color.white.opacity(0.9)   // 主要文字
        static let textSecondary = Color.white.opacity(0.6) // 次要文字
        static let textMuted = Color.white.opacity(0.4)    // 弱化文字

        // 玻璃效果
        static let glassBorder = Color.white.opacity(0.15)  // 玻璃边框
        static let glassHighlight = Color.white.opacity(0.08) // 高光
        static let glassFill = Color.white.opacity(0.05)    // 玻璃填充

        // 状态色
        static let success = Color(hex: "00FF88")          // 成功/追踪OK
        static let warning = Design.Colors.harvest          // 警告
        static let error = Design.Colors.apple              // 错误
        static let info = Color(hex: "00D4FF")             // 信息

        // HUD 专用
        static let hudBackground = Color.white.opacity(0.1) // HUD背景
        static let hudBorder = Color.white.opacity(0.2)    // HUD边框
    }

    /// 暗色渐变
    static var darkGradient: LinearGradient {
        LinearGradient(
            colors: [Dark.bgDeep, Dark.bgSurface, Dark.bgDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 发光渐变 (橙色)
    static var glowGradient: RadialGradient {
        RadialGradient(
            colors: [harvest.opacity(0.4), harvest.opacity(0.1), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 100
        )
    }
}

// MARK: - Glass Card Style
extension Design.Radius {
    /// 玻璃卡片专用圆角
    struct Glass {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xl: CGFloat = 24
    }
}

// MARK: - Dark Shadow
extension Design.Shadow {
    /// 暗色主题阴影
    static let glassShadow = (
        color: Color.black.opacity(0.4),
        radius: CGFloat(20),
        y: CGFloat(10)
    )

    static let hudShadow = (
        color: Color.black.opacity(0.3),
        radius: CGFloat(12),
        y: CGFloat(6)
    )
}

// MARK: - View Modifiers for Dark Theme
extension View {
    /// 玻璃拟态卡片样式
    func glassCardStyle(cornerRadius: CGFloat = Design.Radius.Glass.medium) -> some View {
        self
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }

    /// 暗色背景
    func darkBackground() -> some View {
        self
            .background(Design.Colors.darkGradient)
            .ignoresSafeArea()
    }

    /// HUD 样式
    func hudStyle() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Design.Colors.Dark.hudBackground)
            )
    }
}

// MARK: - Dark Button Style
struct DarkPrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .fill(isEnabled ? Design.Colors.harvest : Color.gray)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DarkSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.headline)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DarkGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Typography for Dark Theme
extension Design.Typography {
    /// HUD 等宽字体
    static let hudLabel = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let hudValue = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let hudValueLarge = Font.system(size: 20, weight: .bold, design: .monospaced)

    /// 深色主题标题
    static let darkHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let darkSubheadline = Font.system(size: 15, weight: .medium, design: .default)
    static let darkCaption = Font.system(size: 12, weight: .regular, design: .default)
}
