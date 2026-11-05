// Theme.swift
// Fruit Tree Scanner — Instrument design system
//
// 一套为“果园三维测量仪器”建立的视觉语言，而不是通用 App 主题。
//
// 原则：
//   1. 纸面优先。暖中性纸底 + 白色承载面 + 1px 发丝线，取代白底白卡与投影。
//   2. 颜色有唯一职责。信号青=系统与操作，琥珀=产量与复核，锈红=失败，
//      深绿=可靠融合，钢蓝=信息。颜色不重复承担同一语义。
//   3. 数字先于图形。所有读数使用等宽数字，单位降级，标签为仪器式小字。
//   4. 层级靠留白与线条，不靠色块和渐变。没有装饰性渐变。

import SwiftUI

// MARK: - Design Tokens
struct Design {
    struct Brand {
        static let productName = "Fruit Tree Scanner"
        static let productTagline = "Orchard LiDAR Scanner"
    }

    // MARK: Color Palette
    struct Colors {
        // —— 信号青：系统、选中、可操作 ——
        static let signal = Color(hex: "0E6B78")
        static let signalDeep = Color(hex: "0A5560")
        static let signalSoft = Color(hex: "E4F0F1")

        // —— 琥珀：产量、重量、待复核 ——
        static let harvest = Color(hex: "8F5B0E")
        static let harvestLight = Color(hex: "C78A2C")
        static let harvestDark = Color(hex: "7E4E09")

        // —— 锈红：失败、不可用、被拒证据 ——
        static let fault = Color(hex: "A3382A")
        static let apple = Color(hex: "A3382A")

        // —— 深绿：可靠融合证据 ——
        static let reliable = Color(hex: "2C6A46")
        static let forest = Color(hex: "2C6A46")

        // —— 钢蓝：中性信息 ——
        static let information = Color(hex: "3F5B70")
        static let earth = Color(hex: "3F5B70")

        // —— 纸面与墨色 ——
        static let paper = Color(hex: "F4F3EF")
        static let stone = Color(hex: "F4F3EF")
        static let sand = Color(hex: "E4E2DB")
        static let charcoal = Color(hex: "151A1C")
        static let slate = Color(hex: "4C565B")

        // Semantic — 语义色（与上面对应，不引入新色相）
        static let success = Color(hex: "2C6A46")
        static let warning = Color(hex: "8F5B0E")
        static let error = Color(hex: "A3382A")
        static let info = Color(hex: "3F5B70")

        // Background - 背景层次
        static let bgBase = Color(hex: "F4F3EF")
        static let bgSurface = Color(hex: "FFFFFF")
        static let bgElevated = Color(hex: "FFFFFF")
    }

    // MARK: Typography
    // 全部使用语义字样，确保动态字号生效；仪器小字另由 Instrument 命名空间提供。
    struct Typography {
        // Heading
        static var title1: Font { .largeTitle.weight(.semibold) }
        static var title2: Font { .title2.weight(.semibold) }
        static var title3: Font { .title3.weight(.semibold) }

        // Body
        static var headline: Font { .headline }
        static var body: Font { .body }
        static var subheadline: Font { .subheadline }
        static var subheadlineMedium: Font { .subheadline.weight(.medium) }
        static var footnote: Font { .footnote }
        static var label: Font { .footnote.weight(.medium) }

        // Caption
        static var caption: Font { .footnote }
        static var captionMedium: Font { .footnote.weight(.medium) }

        // Mono - 数据展示
        static var mono: Font { .system(.body, design: .monospaced).weight(.medium) }
        static var monoSmall: Font { .system(.footnote, design: .monospaced).weight(.medium) }
    }

    // MARK: Spacing (4dp rhythm)
    struct Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radii
    // 小圆角 = 仪器感，避免消费级 App 的“气泡感”。
    struct Radius {
        static let control: CGFloat = 6
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 16
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

    // MARK: Shadows
    // 浅色层级不使用投影；仅保留极轻的浮起阴影给临时元素。
    struct Shadow {
        static let subtle = (color: Color.black.opacity(0.05), radius: CGFloat(8), y: CGFloat(2))
        static let floating = (color: Color.black.opacity(0.10), radius: CGFloat(18), y: CGFloat(6))
    }
}

// MARK: - Divider - 发丝分隔线
struct DividerLine: View {
    var inset: CGFloat = 0
    var color: Color = Color(hex: "DFDDD6")
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
            .padding(.leading, inset)
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
            (a, r, g, b) = (255, int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF)
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
