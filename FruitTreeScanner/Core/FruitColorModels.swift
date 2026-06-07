// FruitColorModels.swift
// 果实颜色过滤与 HSV 颜色判断

import Foundation
import simd

struct ColorFilter {
    var rMin: Float = 0
    var rMax: Float = 1
    var gMin: Float = 0
    var gMax: Float = 1
    var bMin: Float = 0
    var bMax: Float = 1

    var hsvFilter: HSVFilter?

    init(rMin: Float = 0, rMax: Float = 1,
         gMin: Float = 0, gMax: Float = 1,
         bMin: Float = 0, bMax: Float = 1) {
        self.rMin = rMin
        self.rMax = rMax
        self.gMin = gMin
        self.gMax = gMax
        self.bMin = bMin
        self.bMax = bMax
    }

    func matches(r: Float, g: Float, b: Float) -> Bool {
        let rgbMatch = r >= rMin && r <= rMax &&
            g >= gMin && g <= gMax &&
            b >= bMin && b <= bMax

        guard let hsv = hsvFilter else { return rgbMatch }
        let hsvColor = FruitCategory.rgbToHSV(SIMD3<Float>(r, g, b))
        let hsvMatch = hsv.matches(h: hsvColor.x, s: hsvColor.y, v: hsvColor.z)

        return rgbMatch || hsvMatch
    }

    var description: String {
        var parts: [String] = []
        if rMin > 0 { parts.append("R≥\(String(format: "%.2f", rMin))") }
        if rMax < 1 { parts.append("R≤\(String(format: "%.2f", rMax))") }
        if gMin > 0 { parts.append("G≥\(String(format: "%.2f", gMin))") }
        if gMax < 1 { parts.append("G≤\(String(format: "%.2f", gMax))") }
        if bMin > 0 { parts.append("B≥\(String(format: "%.2f", bMin))") }
        if bMax < 1 { parts.append("B≤\(String(format: "%.2f", bMax))") }
        if let hsv = hsvFilter {
            parts.append(hsv.description)
        }
        return parts.joined(separator: ", ")
    }
}

struct HSVFilter {
    var hMin: Float = 0
    var hMax: Float = 360
    var sMin: Float = 0
    var vMin: Float = 0

    func matches(h: Float, s: Float, v: Float) -> Bool {
        let hMatch: Bool
        if hMin <= hMax {
            hMatch = h >= hMin && h <= hMax
        } else {
            hMatch = h >= hMin || h <= hMax
        }
        return hMatch && s >= sMin && v >= vMin
    }

    var description: String {
        "H:\(Int(hMin))°-\(Int(hMax))° S≥\(String(format: "%.0f%%", sMin * 100)) V≥\(String(format: "%.0f%%", vMin * 100))"
    }
}

extension FruitCategory {
    var colorFilter: ColorFilter {
        switch self {
        case .apple: return ColorFilter(rMin: 0.25, gMin: 0.22, bMax: 0.42)
        case .orange: return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25)
        case .mandarin: return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25)
        case .pomelo: return ColorFilter(rMin: 0.45, gMin: 0.35, gMax: 0.60, bMax: 0.30)
        case .pear: return ColorFilter(rMin: 0.38, gMin: 0.35, bMax: 0.32)
        case .peach: return ColorFilter(rMin: 0.50, gMin: 0.22, bMax: 0.35)
        case .cherry: return ColorFilter(rMin: 0.40, gMax: 0.25, bMax: 0.25)
        case .grape: return ColorFilter(rMin: 0.20, gMax: 0.25, bMin: 0.20)
        case .persimmon: return ColorFilter(rMin: 0.50, gMin: 0.20, gMax: 0.45, bMax: 0.25)
        case .mango: return ColorFilter(rMin: 0.55, gMin: 0.40, bMax: 0.30)
        case .kiwi: return ColorFilter(rMax: 0.40, gMin: 0.30, bMax: 0.30)
        case .plum: return ColorFilter(rMin: 0.25, gMax: 0.20, bMin: 0.15)
        case .pomegranate: return ColorFilter(rMin: 0.40, gMax: 0.30, bMax: 0.25)
        case .loquat: return ColorFilter(rMin: 0.50, gMin: 0.30, gMax: 0.55, bMax: 0.25)
        case .lychee: return ColorFilter(rMin: 0.50, gMax: 0.35, bMax: 0.25)
        case .longan: return ColorFilter(rMin: 0.35, gMin: 0.25, gMax: 0.45, bMax: 0.25)
        case .bayberry: return ColorFilter(rMin: 0.30, gMax: 0.20, bMax: 0.20)
        case .jujube: return ColorFilter(rMin: 0.45, gMax: 0.30, bMax: 0.20)
        case .hawthorn: return ColorFilter(rMin: 0.50, gMax: 0.25, bMax: 0.20)
        case .fig: return ColorFilter(rMin: 0.35, gMin: 0.20, gMax: 0.50, bMax: 0.25)
        case .papaya: return ColorFilter(rMin: 0.55, gMin: 0.35, gMax: 0.55, bMax: 0.25)
        case .chestnut: return ColorFilter(rMin: 0.25, gMin: 0.15, gMax: 0.35, bMax: 0.20)
        case .mulberry: return ColorFilter(rMin: 0.20, gMax: 0.15, bMin: 0.15)
        case .blueberry: return ColorFilter(rMax: 0.25, gMax: 0.20, bMin: 0.25)
        case .strawberry: return ColorFilter(rMin: 0.50, gMax: 0.30, bMax: 0.25)
        case .coconut: return ColorFilter(rMin: 0.30, gMin: 0.25, gMax: 0.45, bMax: 0.25)
        }
    }

    static func rgbToHSV(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let r = rgb.x
        let g = rgb.y
        let b = rgb.z
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        var h: Float = 0
        let s: Float = maxVal == 0 ? 0 : delta / maxVal
        let v: Float = maxVal

        if delta != 0 {
            if maxVal == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxVal == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }

        return SIMD3<Float>(h, s, v)
    }

    static func isFruitColor(_ rgb: SIMD3<Float>) -> Bool {
        let hsv = rgbToHSV(rgb)
        let h = hsv.x
        let s = hsv.y
        let v = hsv.z

        if v < 0.10 || v > 0.98 { return false }
        if s < 0.06 { return false }

        if (h >= 0 && h <= 25) || (h >= 335 && h <= 360) {
            if s >= 0.18 && v >= 0.18 { return true }
        }
        if h >= 15 && h <= 50 {
            if s >= 0.25 && v >= 0.25 { return true }
        }
        if h >= 45 && h <= 95 {
            if s >= 0.10 && v >= 0.25 { return true }
        }
        if h >= 80 && h <= 150 {
            if s >= 0.12 && v >= 0.12 && v <= 0.70 { return true }
        }
        if h >= 240 && h <= 300 {
            if s >= 0.12 && v >= 0.12 { return true }
        }
        if h >= 300 && h <= 340 {
            if s >= 0.12 && v >= 0.12 { return true }
        }
        if h >= 10 && h <= 50 {
            if s >= 0.10 && s <= 0.55 && v >= 0.15 && v <= 0.55 { return true }
        }
        if (h >= 0 && h <= 20) || (h >= 340 && h <= 360) {
            if s >= 0.30 && v >= 0.12 && v <= 0.50 { return true }
        }

        return false
    }
}
