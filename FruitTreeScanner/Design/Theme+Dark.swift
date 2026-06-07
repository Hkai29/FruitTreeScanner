// Theme+Dark.swift
// 专业扫描软件暗色主题扩展

import SwiftUI

// MARK: - Dark Theme Extension
extension Design.Colors {
    /// 专业扫描软件暗色主题颜色
    struct Dark {
        // 背景层次
        static let bgDeep = Color(hex: "10130F")           // 主背景
        static let bgSurface = Color(hex: "191D17")        // 页面表面
        static let bgElevated = Color(hex: "242A21")       // 控件表面

        // 强调色
        static let glow = Design.Colors.harvest

        // 文字颜色
        static let textPrimary = Color.white.opacity(0.95)   // 主要文字 (WCAG AAA)
        static let textSecondary = Color.white.opacity(0.7) // 次要文字 (WCAG AA 4.5:1+)
        static let textMuted = Color.white.opacity(0.5)    // 弱化文字 (WCAG AA 3:1+)

        // 玻璃效果
        static let glassBorder = Color(hex: "30382D")       // 深色细边框
        static let glassHighlight = Color.white.opacity(0.04)
        static let glassFill = Color(hex: "1C211A")

        // 状态色
        static let success = Design.Colors.forest           // 成功/追踪OK
        static let warning = Design.Colors.harvest          // 警告
        static let error = Design.Colors.apple              // 错误
        static let info = Design.Colors.earth               // 信息

        // HUD 专用
        static let hudBackground = Color(hex: "151912").opacity(0.94)
        static let hudBorder = Color(hex: "384133")
    }

    /// 暗色渐变
    static var darkGradient: LinearGradient {
        LinearGradient(
            colors: [Dark.bgDeep, Color(hex: "171B14")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

}

// MARK: - Glass Card Style
extension Design.Radius {
    /// 玻璃卡片专用圆角
    struct Glass {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 14
    }
}

// MARK: - Dark Shadow
extension Design.Shadow {
    /// 暗色主题阴影
    static let glassShadow = (
        color: Color.black.opacity(0.18),
        radius: CGFloat(10),
        y: CGFloat(4)
    )

}

// MARK: - View Modifiers for Dark Theme
extension View {
    /// 深色表面卡片样式
    func glassCardStyle(cornerRadius: CGFloat = Design.Radius.Glass.medium) -> some View {
        self
            .background(Design.Colors.Dark.glassFill)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }
}

// MARK: - Dark Button Style
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

    /// 深色主题标题
    static let darkHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let darkSubheadline = Font.system(size: 15, weight: .medium, design: .default)
    static let darkCaption = Font.system(size: 12, weight: .regular, design: .default)
}
