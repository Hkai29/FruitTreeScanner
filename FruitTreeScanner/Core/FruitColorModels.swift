// FruitColorModels.swift
// 果实颜色过滤与 HSV/Lab 颜色判断

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
    var labFilter: LabFilter?

    init(rMin: Float = 0, rMax: Float = 1,
         gMin: Float = 0, gMax: Float = 1,
         bMin: Float = 0, bMax: Float = 1,
         labFilter: LabFilter? = nil) {
        self.rMin = rMin
        self.rMax = rMax
        self.gMin = gMin
        self.gMax = gMax
        self.bMin = bMin
        self.bMax = bMax
        self.labFilter = labFilter
    }

    func matches(r: Float, g: Float, b: Float) -> Bool {
        let rgbMatch = r >= rMin && r <= rMax &&
            g >= gMin && g <= gMax &&
            b >= bMin && b <= bMax

        let hsvMatch: Bool
        if let hsv = hsvFilter {
            let hsvColor = FruitCategory.rgbToHSV(SIMD3<Float>(r, g, b))
            hsvMatch = hsv.matches(h: hsvColor.x, s: hsvColor.y, v: hsvColor.z)
        } else {
            hsvMatch = false
        }

        guard rgbMatch || hsvMatch else { return false }
        guard let lab = labFilter else { return true }

        let labColor = FruitCategory.rgbToLab(SIMD3<Float>(r, g, b))
        return lab.matches(l: labColor.x, a: labColor.y, labB: labColor.z)
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
        if let lab = labFilter {
            parts.append(lab.description)
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

struct LabFilter {
    var lMin: Float = 0
    var lMax: Float = 100
    var aMin: Float = -128
    var aMax: Float = 127
    var bMin: Float = -128
    var bMax: Float = 127

    func matches(l: Float, a: Float, labB: Float) -> Bool {
        l >= lMin && l <= lMax &&
            a >= aMin && a <= aMax &&
            labB >= bMin && labB <= bMax
    }

    var description: String {
        "Lab L:\(Int(lMin))-\(Int(lMax)) a:\(Int(aMin))-\(Int(aMax)) b:\(Int(bMin))-\(Int(bMax))"
    }
}

extension FruitCategory {
    var colorFilter: ColorFilter {
        switch self {
        case .apple:
            return ColorFilter(rMin: 0.25, gMin: 0.22, bMax: 0.42, labFilter: .redYellowFruit)
        case .orange:
            return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25, labFilter: .orangeYellowFruit)
        case .mandarin:
            return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25, labFilter: .orangeYellowFruit)
        case .pomelo:
            return ColorFilter(rMin: 0.45, gMin: 0.35, gMax: 0.60, bMax: 0.30, labFilter: .orangeYellowFruit)
        case .pear: return ColorFilter(rMin: 0.38, gMin: 0.35, bMax: 0.32)
        case .peach:
            return ColorFilter(rMin: 0.50, gMin: 0.22, bMax: 0.35, labFilter: .redYellowFruit)
        case .cherry:
            return ColorFilter(rMin: 0.40, gMax: 0.25, bMax: 0.25, labFilter: .redFruit)
        case .grape: return ColorFilter(rMin: 0.20, gMax: 0.25, bMin: 0.20)
        case .persimmon:
            return ColorFilter(rMin: 0.50, gMin: 0.20, gMax: 0.45, bMax: 0.25, labFilter: .orangeYellowFruit)
        case .mango:
            return ColorFilter(rMin: 0.55, gMin: 0.40, bMax: 0.30, labFilter: .orangeYellowFruit)
        case .kiwi: return ColorFilter(rMax: 0.40, gMin: 0.30, bMax: 0.30)
        case .plum: return ColorFilter(rMin: 0.25, gMax: 0.20, bMin: 0.15)
        case .pomegranate:
            return ColorFilter(rMin: 0.40, gMax: 0.30, bMax: 0.25, labFilter: .redFruit)
        case .loquat:
            return ColorFilter(rMin: 0.50, gMin: 0.30, gMax: 0.55, bMax: 0.25, labFilter: .orangeYellowFruit)
        case .lychee:
            return ColorFilter(rMin: 0.50, gMax: 0.35, bMax: 0.25, labFilter: .redFruit)
        case .longan: return ColorFilter(rMin: 0.35, gMin: 0.25, gMax: 0.45, bMax: 0.25)
        case .bayberry: return ColorFilter(rMin: 0.30, gMax: 0.20, bMax: 0.20)
        case .jujube:
            return ColorFilter(rMin: 0.45, gMax: 0.30, bMax: 0.20, labFilter: .redFruit)
        case .hawthorn:
            return ColorFilter(rMin: 0.50, gMax: 0.25, bMax: 0.20, labFilter: .redFruit)
        case .fig: return ColorFilter(rMin: 0.35, gMin: 0.20, gMax: 0.50, bMax: 0.25)
        case .papaya:
            return ColorFilter(rMin: 0.55, gMin: 0.35, gMax: 0.55, bMax: 0.25, labFilter: .orangeYellowFruit)
        case .chestnut: return ColorFilter(rMin: 0.25, gMin: 0.15, gMax: 0.35, bMax: 0.20)
        case .mulberry: return ColorFilter(rMin: 0.20, gMax: 0.15, bMin: 0.15)
        case .blueberry: return ColorFilter(rMax: 0.25, gMax: 0.20, bMin: 0.25)
        case .strawberry:
            return ColorFilter(rMin: 0.50, gMax: 0.30, bMax: 0.25, labFilter: .redFruit)
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

    static func rgbToLab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let r = linearizedSRGB(rgb.x)
        let g = linearizedSRGB(rgb.y)
        let b = linearizedSRGB(rgb.z)

        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

        let fx = labPivot(x)
        let fy = labPivot(y)
        let fz = labPivot(z)

        return SIMD3<Float>(
            116 * fy - 16,
            500 * (fx - fy),
            200 * (fy - fz)
        )
    }

    private static func linearizedSRGB(_ component: Float) -> Float {
        let clamped = min(max(component, 0), 1)
        if clamped <= 0.04045 {
            return clamped / 12.92
        }
        return pow((clamped + 0.055) / 1.055, 2.4)
    }

    private static func labPivot(_ value: Float) -> Float {
        if value > 0.008856 {
            return pow(value, 1.0 / 3.0)
        }
        return 7.787 * value + 16.0 / 116.0
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

private extension LabFilter {
    static let redYellowFruit = LabFilter(lMin: 18, lMax: 95, aMin: 0, aMax: 90, bMin: 8, bMax: 95)
    static let orangeYellowFruit = LabFilter(lMin: 20, lMax: 95, aMin: -5, aMax: 90, bMin: 18, bMax: 100)
    static let redFruit = LabFilter(lMin: 12, lMax: 90, aMin: 8, aMax: 100, bMin: -10, bMax: 95)
}
