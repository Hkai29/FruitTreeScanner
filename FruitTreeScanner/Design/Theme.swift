// Theme.swift
// FruitScanner Design System
// Organic Precision — Warm, natural, professional

import SwiftUI

// MARK: - Design Tokens
struct Design {
    // MARK: Color Palette
    struct Colors {
        // Primary - Deep Forest Green (softer)
        static let forest = Color(hex: "3D6B5C")
        static let forestLight = Color(hex: "5A8A7A")
        static let forestDark = Color(hex: "2D5144")

        // Secondary - Warm Sage
        static let sage = Color(hex: "52796F")
        static let sageLight = Color(hex: "84A98C")

        // Accent - Harvest Gold
        static let harvest = Color(hex: "D4A373")
        static let harvestLight = Color(hex: "E9C46A")
        static let harvestDark = Color(hex: "BC6C25")

        // Neutrals - Warm scale
        static let cream = Color(hex: "F7F5F3")
        static let stone = Color(hex: "F0EEEB")
        static let sand = Color(hex: "E4E1DD")
        static let pebble = Color(hex: "C8C5C0")
        static let slate = Color(hex: "8A8785")
        static let charcoal = Color(hex: "4A4845")

        // Semantic
        static let success = Color(hex: "5A9A82")
        static let warning = Color(hex: "D4B87A")
        static let error = Color(hex: "C98B8E")
        static let info = Color(hex: "6B9AB8")

        // Background layers
        static let bgBase = Color(hex: "FAF8F5")
        static let bgSurface = Color.white
        static let bgElevated = Color.white
        static let bgOverlay = Color.black.opacity(0.05)
    }

    // MARK: Typography
    struct Typography {
        // Display - for large numbers and hero text
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

        // Mono - for data displays
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

    // MARK: Radii
    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 24
        static let full: CGFloat = 999
    }

    // MARK: Shadows
    struct Shadow {
        static let subtle = (color: Color.black.opacity(0.04), radius: CGFloat(8), y: CGFloat(2))
        static let small = (color: Color.black.opacity(0.06), radius: CGFloat(12), y: CGFloat(4))
        static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(16), y: CGFloat(8))
        static let large = (color: Color.black.opacity(0.10), radius: CGFloat(24), y: CGFloat(12))
    }
}

// MARK: - Backward Compatibility Aliases
struct Theme {
    static let primary = Design.Colors.forest
    static let primaryDark = Design.Colors.forestDark
    static let primaryLight = Design.Colors.sageLight

    static let background = Design.Colors.bgBase
    static let backgroundLight = Design.Colors.bgSurface
    static let backgroundLighter = Design.Colors.stone
    static let backgroundTertiary = Design.Colors.sand

    static let textPrimary = Design.Colors.charcoal
    static let textSecondary = Design.Colors.slate
    static let textTertiary = Design.Colors.pebble

    static let border = Design.Colors.sand
    static let borderLight = Design.Colors.pebble.opacity(0.5)
    static let cardBorder = Design.Colors.sand.opacity(0.8)
    static let cardBackground = Design.Colors.bgSurface

    static let success = Design.Colors.success
    static let warning = Design.Colors.warning
    static let error = Design.Colors.error
    static let info = Design.Colors.info

    static let primaryGradient = LinearGradient(
        colors: [Design.Colors.forest, Design.Colors.forestLight],
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
            .padding(Design.Space.lg)
            .background(Design.Colors.bgSurface)
            .cornerRadius(Design.Radius.large)
            .shadow(
                color: Design.Shadow.subtle.color,
                radius: Design.Shadow.subtle.radius,
                y: Design.Shadow.subtle.y
            )
    }

    func surfaceStyle() -> some View {
        self
            .background(Design.Colors.bgSurface)
            .cornerRadius(Design.Radius.large)
    }

    func elevatedStyle() -> some View {
        self
            .background(Design.Colors.bgElevated)
            .cornerRadius(Design.Radius.large)
            .shadow(
                color: Design.Shadow.medium.color,
                radius: Design.Shadow.medium.radius,
                y: Design.Shadow.medium.y
            )
    }
}

// MARK: - Button Styles
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
                    .fill(isEnabled ? Design.Colors.forest : Design.Colors.pebble)
            )
            .shadow(
                color: isEnabled ? Design.Colors.forest.opacity(0.3) : .clear,
                radius: 8,
                y: 4
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

// MARK: - Input Field Style
struct InputFieldStyle: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .font(Design.Typography.body)
            .foregroundColor(Design.Colors.charcoal)
            .padding(Design.Space.md)
            .background(Design.Colors.bgSurface)
            .cornerRadius(Design.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .stroke(
                        text.isEmpty ? Design.Colors.sand : Design.Colors.forest.opacity(0.5),
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

// MARK: - Divider
struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Design.Colors.sand)
            .frame(height: 1)
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
            content.font(Design.Typography.title2).foregroundColor(Design.Colors.charcoal)
        case .headline:
            content.font(Design.Typography.headline).foregroundColor(Design.Colors.charcoal)
        case .body:
            content.font(Design.Typography.body).foregroundColor(Design.Colors.charcoal)
        case .caption:
            content.font(Design.Typography.caption).foregroundColor(Design.Colors.slate)
        }
    }
}

extension View {
    func labelStyle(_ style: LabelStyle.Style) -> some View {
        modifier(LabelStyle(style: style))
    }
}