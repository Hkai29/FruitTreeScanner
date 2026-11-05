// Theme+Dark.swift
// 采集画布与点云视口：深色仪器显示层。
// 与日光工作区共享字形、线宽与状态语义，只切换明度底座。

import SwiftUI

// MARK: - Dark Theme Extension
extension Design.Colors {
    /// 采集与点云共用的暗色画布。
    struct Dark {
        // 背景层次
        static let bgDeep = Color(hex: "0E1214")        // 采集画布
        static let bgSurface = Color(hex: "161B1E")     // 面板表面
        static let bgElevated = Color(hex: "1E2529")    // 控件表面

        // 强调色：LiDAR 信号青
        static let glow = Color(hex: "17B2C4")
        /// 点云几何着色（仅限深色视口内使用）
        static let lidar = Color(hex: "17B2C4")

        // 文字颜色
        static let textPrimary = Color(hex: "F0F3F3")    // 主要文字
        static let textSecondary = Color(hex: "9EA9AC")  // 次要文字
        static let textMuted = Color(hex: "829095")      // 弱化文字

        // 玻璃效果
        static let glassBorder = Color(hex: "2C3438")
        static let glassHighlight = Color.white.opacity(0.04)
        static let glassFill = Color(hex: "161B1E")

        // 状态色（暗底上提亮，保持同一语义）
        static let success = Color(hex: "6FC08C")
        static let warning = Color(hex: "E0A94A")
        static let error = Color(hex: "E58B7B")
        static let info = Color(hex: "8FB6CC")

        // HUD 专用
        static let hudBackground = Color(hex: "12181B").opacity(0.96)
        static let hudBorder = Color(hex: "2C3438")

        // 采集与点云浏览共用的中性工具表面。
        static let controlSurface = Color(hex: "1B2225")
        static let pointCloudControls = controlSurface
    }

    /// 暗色渐变（仅用于画布纵深，不用于装饰面板）
    static var darkGradient: LinearGradient {
        LinearGradient(
            colors: [Dark.bgDeep, Color(hex: "0A0E10")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glass Card Style
extension Design.Radius {
    /// 暗色面板圆角
    struct Glass {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 14
    }
}

// MARK: - Dark Shadow
extension Design.Shadow {
    /// 暗色浮起阴影
    static let glassShadow = (
        color: Color.black.opacity(0.34),
        radius: CGFloat(14),
        y: CGFloat(6)
    )
}

// MARK: - View Modifiers for Dark Theme
extension View {
    /// 深色表面面板：实底 + 1px 描边，不用大面积玻璃模糊。
    func glassCardStyle(cornerRadius: CGFloat = Design.Radius.Glass.medium) -> some View {
        self
            .background(Design.Colors.Dark.glassFill)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
    }
}

// MARK: - Dark Button Style
struct DarkGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Typography for Dark Theme
extension Design.Typography {
    /// HUD 等宽字体
    static var hudLabel: Font { .system(size: 10, weight: .medium, design: .monospaced) }
    static var hudValue: Font { .system(size: 14, weight: .bold, design: .monospaced) }

    /// 深色面板标题
    static var darkHeadline: Font { .system(.headline, design: .default).weight(.semibold) }
    static var darkSubheadline: Font { .system(.subheadline, design: .default).weight(.medium) }
    static var darkCaption: Font { .system(.caption, design: .default) }
}
