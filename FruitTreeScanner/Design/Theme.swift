// Theme.swift
// FruitScanner Design System
// 自然有机风格 — Warm Earth Tones + Forest Green
// 温暖、专业、可信赖

import SwiftUI

// MARK: - Design Tokens
struct Design {
    // MARK: Color Palette - iOS 设置风格（清爽白绿）
    struct Colors {
        // Primary - iOS 蓝绿色（清新科技感）
        static let forest = Color(hex: "34C759")            // iOS 绿色
        static let forestLight = Color(hex: "30D158")      // 亮绿色
        static let forestDark = Color(hex: "248A3D")      // 深绿色

        // Secondary - iOS 蓝色系
        static let earth = Color(hex: "007AFF")            // iOS 蓝色
        static let earthLight = Color(hex: "5AC8FA")       // 浅蓝色
        static let earthDark = Color(hex: "0056B3")        // 深蓝色

        // Accent - 强调色
        static let harvest = Color(hex: "FF9500")          // iOS 橙色
        static let harvestLight = Color(hex: "FF9F0A")     // 浅橙色
        static let harvestDark = Color(hex: "CC7700")      // 深橙色

        // Fruit - 果实色系
        static let apple = Color(hex: "FF3B30")            // iOS 红色
        static let appleLight = Color(hex: "FF6961")       // 浅红色
        static let citrus = Color(hex: "FFCC00")          // iOS 黄色

        // Neutrals - 暖白色系
        static let cream = Color(hex: "FAF8F5")             // 米白
        static let stone = Color(hex: "F5F3EF")             // 暖灰白
        static let sand = Color(hex: "E8E4DD")               // 暖沙色
        static let pebble = Color(hex: "D4CFC7")            // 暖卵石色
        static let slate = Color(hex: "8E8E93")             // 中灰
        static let charcoal = Color(hex: "3D3A36")          // 深灰棕

        // Semantic - 语义色
        static let success = Color(hex: "34C759")           // 成功绿
        static let warning = Color(hex: "FF9500")           // 警告橙
        static let error = Color(hex: "FF3B30")             // 错误红
        static let info = Color(hex: "007AFF")              // 信息蓝

        // Background - 背景层次
        static let bgBase = Color(hex: "FAF8F5")            // 米白底色
        static let bgSurface = Color(hex: "FFFFFF")         // 卡片表面（纯白）
        static let bgElevated = Color(hex: "FFFFFF")        // 浮起表面
        static let bgOverlay = Color.black.opacity(0.04)    // 遮罩层
        static let bgGrouped = Color(hex: "F5F3EF")         // 分组背景

        // Gradient - iOS 风格渐变
        static let forestGradient = LinearGradient(
            colors: [forest, forestLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let earthGradient = LinearGradient(
            colors: [earth, earthLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let harvestGradient = LinearGradient(
            colors: [harvest, harvestLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Typography
    struct Typography {
        // Display - 大号数字/英雄文本
        static let display = Font.system(size: 56, weight: .heavy, design: .rounded)
        static let displayMedium = Font.system(size: 44, weight: .bold, design: .rounded)
        static let displaySmall = Font.system(size: 36, weight: .bold, design: .rounded)

        // Heading
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .semibold, design: .default)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)

        // Body
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 17, weight: .medium, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let subheadlineMedium = Font.system(size: 15, weight: .medium, design: .default)

        // Caption
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let footnoteMedium = Font.system(size: 13, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)

        // Mono - 数据展示
        static let mono = Font.system(size: 17, weight: .medium, design: .monospaced)
        static let monoSmall = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    // MARK: Spacing
    struct Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: Radii - iOS 风格圆角
    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 14
        static let full: CGFloat = 999
    }

    // MARK: Shadows - iOS 柔和阴影
    struct Shadow {
        static let subtle = (color: Color.black.opacity(0.04), radius: CGFloat(6), y: CGFloat(2))
        static let small = (color: Color.black.opacity(0.06), radius: CGFloat(8), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(12), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.12), radius: CGFloat(16), y: CGFloat(6))
    }
}

// MARK: - Backward Compatibility Aliases
struct Theme {
    static let primary = Design.Colors.forest
    static let primaryDark = Design.Colors.forestDark
    static let primaryLight = Design.Colors.forestLight

    static let background = Color(hex: "FAF8F5")
    static let backgroundLight = Color(hex: "FFFFFF")
    static let backgroundLighter = Color(hex: "F5F3EF")
    static let backgroundTertiary = Color(hex: "E8E4DD")

    static let textPrimary = Color(hex: "3D3A36")
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "D4CFC7")

    static let border = Color(hex: "E8E4DD")
    static let borderLight = Color(hex: "D4CFC7").opacity(0.5)
    static let cardBorder = Color(hex: "E8E4DD")
    static let cardBackground = Color(hex: "FFFFFF")

    static let success = Color(hex: "34C759")
    static let warning = Color(hex: "FF9500")
    static let error = Color(hex: "FF3B30")
    static let info = Color(hex: "007AFF")

    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "34C759"), Color(hex: "30D158")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppFont {
    static let largeTitle = Design.Typography.largeTitle
    static let title1 = Design.Typography.title1
    static let title2 = Design.Typography.title2
    static let title3 = Design.Typography.title3
    static let headline = Design.Typography.headline
    static let body = Design.Typography.body
    static let subheadline = Design.Typography.subheadline
    static let footnote = Design.Typography.footnote
    static let caption = Design.Typography.caption
    static let caption2 = Design.Typography.captionMedium

    static let displayLarge = Design.Typography.display
    static let displayMedium = Design.Typography.displayMedium
    static let displaySmall = Design.Typography.displaySmall
}

struct Spacing {
    static let xs: CGFloat = Design.Space.xs
    static let sm: CGFloat = Design.Space.sm
    static let md: CGFloat = Design.Space.md
    static let lg: CGFloat = Design.Space.lg
    static let xl: CGFloat = Design.Space.xl
    static let xxl: CGFloat = Design.Space.xxl
}

struct CornerRadius {
    static let small: CGFloat = Design.Radius.small
    static let medium: CGFloat = Design.Radius.medium
    static let large: CGFloat = Design.Radius.large
    static let full: CGFloat = Design.Radius.full
}

// MARK: - View Modifiers
extension View {
    func cardStyle() -> some View {
        self
            .padding(Design.Space.md)
            .background(Color.white)
            .cornerRadius(Design.Radius.large)
            .shadow(
                color: Design.Shadow.subtle.color,
                radius: Design.Shadow.subtle.radius,
                y: Design.Shadow.subtle.y
            )
    }

    func surfaceStyle() -> some View {
        self
            .background(Color.white)
            .cornerRadius(Design.Radius.large)
    }

    func elevatedStyle() -> some View {
        self
            .background(Color.white)
            .cornerRadius(Design.Radius.large)
            .shadow(
                color: Design.Shadow.medium.color,
                radius: Design.Shadow.medium.radius,
                y: Design.Shadow.medium.y
            )
    }
}

// MARK: - Button Styles - iOS 风格
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(isEnabled ? Design.Colors.forest : Color(hex: "C7C7CC"))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.headline)
            .foregroundColor(Design.Colors.forest)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .strokeBorder(Design.Colors.forest, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.subheadlineMedium)
            .foregroundColor(Design.Colors.forest)
            .padding(.vertical, Design.Space.sm)
            .padding(.horizontal, Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.forest.opacity(configuration.isPressed ? 0.1 : 0.08))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Input Field Style - iOS 风格
struct InputFieldStyle: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .font(Design.Typography.body)
            .foregroundColor(Color(hex: "1C1C1E"))
            .padding(Design.Space.md)
            .background(Color.white)
            .cornerRadius(Design.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .stroke(
                        text.isEmpty ? Color(hex: "E5E5EA") : Color(hex: "34C759").opacity(0.5),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func inputFieldStyle(text: Binding<String>) -> some View {
        modifier(InputFieldStyle(text: text))
    }
}

// MARK: - Divider - iOS 风格分隔线
struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "E5E5EA"))
            .frame(height: 0.5)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Label Styles
struct LabelStyle: ViewModifier {
    enum Style {
        case title, headline, body, caption
    }

    let style: Style

    func body(content: Content) -> some View {
        switch style {
        case .title:
            content.font(Design.Typography.title2).foregroundColor(Color(hex: "1C1C1E"))
        case .headline:
            content.font(Design.Typography.headline).foregroundColor(Color(hex: "1C1C1E"))
        case .body:
            content.font(Design.Typography.body).foregroundColor(Color(hex: "1C1C1E"))
        case .caption:
            content.font(Design.Typography.caption).foregroundColor(Color(hex: "8E8E93"))
        }
    }
}

extension View {
    func labelStyle(_ style: LabelStyle.Style) -> some View {
        modifier(LabelStyle(style: style))
    }
}