// Theme.swift
// Fruit Tree Scanner Design System
// 自然有机风格 — Warm Earth Tones + Forest Green
// 温暖、专业、可信赖

import SwiftUI

// MARK: - Design Tokens
struct Design {
    struct Brand {
        static let productName = "Fruit Tree Scanner"
        static let productTagline = "Orchard LiDAR Scanner"
    }

    // MARK: Color Palette - Orchard field-tool theme
    struct Colors {
        // Primary - 低饱和叶绿
        static let forest = Color(hex: "6F8F63")

        // Secondary - 测绘灰蓝
        static let earth = Color(hex: "4D7588")

        // Accent - 成熟果实的赭金色
        static let harvest = Color(hex: "B8843A")
        static let harvestLight = Color(hex: "D3A15A")
        static let harvestDark = Color(hex: "815D28")

        // Fruit - 果实色系
        static let apple = Color(hex: "B8564B")

        // Neutrals - 暖白色系
        static let stone = Color(hex: "F4F1EA")
        static let sand = Color(hex: "E2D8C8")
        static let slate = Color(hex: "7E8580")
        static let charcoal = Color(hex: "34362F")

        // Semantic - 语义色
        static let success = Color(hex: "6F8F63")
        static let warning = Color(hex: "B8843A")
        static let error = Color(hex: "B8564B")
        static let info = Color(hex: "4D7588")

        // Background - 背景层次
        static let bgBase = Color(hex: "F7F4EE")
        static let bgSurface = Color(hex: "FFFFFF")
        static let bgElevated = Color(hex: "FFFFFF")
    }

    // MARK: Typography
    struct Typography {
        // Heading
        static let title1 = Font.system(size: 28, weight: .semibold, design: .default)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .default)

        // Body
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let subheadlineMedium = Font.system(size: 15, weight: .medium, design: .default)

        // Caption
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)

        // Mono - 数据展示
        static let mono = Font.system(size: 17, weight: .medium, design: .monospaced)
        static let monoSmall = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    // MARK: Spacing (4/8dp rhythm)
    struct Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radii
    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }

    // MARK: Animation
    struct Animation {
        static let micro: Double = 0.15
        static let standard: Double = 0.2
    }

    // MARK: Touch Targets
    struct Touch {
        static let minimumHeight: CGFloat = 44
        static let minimumWidth: CGFloat = 44
    }

    // MARK: Shadows - iOS 柔和阴影
    struct Shadow {
        static let subtle = (color: Color.black.opacity(0.04), radius: CGFloat(6), y: CGFloat(2))
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
