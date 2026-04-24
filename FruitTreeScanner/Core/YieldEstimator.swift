// YieldEstimator.swift
// 产量估算引擎（Swift 原生实现，对应 Python 双路线）
// 无第三方依赖，全部跑在 iPad 本地

import Foundation
import simd

// MARK: - 果种配置

enum FruitType: String, CaseIterable {
    case appleRed    = "红苹果"
    case appleGreen  = "青苹果"
    case citrus      = "柑橘"
    case pear        = "梨"
    case peach       = "桃"

    /// 果实密度（g/cm³）
    var density: Float {
        switch self {
        case .appleRed:   return 0.85
        case .appleGreen: return 0.84
        case .citrus:     return 0.88
        case .pear:       return 0.93
        case .peach:      return 0.91
        }
    }

    /// RGB 颜色阈值（归一化 0~1）
    var colorFilter: ColorFilter {
        switch self {
        case .appleRed:
            return ColorFilter(rMin: 0.45, gMax: 0.42, bMax: 0.38)
        case .appleGreen:
            return ColorFilter(rMin: 0.25, gMin: 0.38, gMax: 0.65, bMax: 0.38)
        case .citrus:
            return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25)
        case .pear:
            return ColorFilter(rMin: 0.38, gMin: 0.35, bMax: 0.32)
        case .peach:
            return ColorFilter(rMin: 0.50, gMin: 0.22, bMax: 0.35)
        }
    }

    /// DBSCAN eps（果实直径约 5~9cm，单位 m）
    var clusterEps: Float { 0.05 }

    /// 合理果实直径范围（m）
    var diamMin: Float { 0.03 }
    var diamMax: Float { 0.18 }
}

struct ColorFilter {
    var rMin: Float = 0; var rMax: Float = 1
    var gMin: Float = 0; var gMax: Float = 1
    var bMin: Float = 0; var bMax: Float = 1

    init(rMin: Float = 0, rMax: Float = 1,
         gMin: Float = 0, gMax: Float = 1,
         bMin: Float = 0, bMax: Float = 1) {
        self.rMin = rMin; self.rMax = rMax
        self.gMin = gMin; self.gMax = gMax
        self.bMin = bMin; self.bMax = bMax
    }

    func matches(r: Float, g: Float, b: Float) -> Bool {
        r >= rMin && r <= rMax &&
        g >= gMin && g <= gMax &&
        b >= bMin && b <= bMax
    }
}

// MARK: - 点（位置 + 颜色）

struct ColoredPoint {
    let pos: SIMD3<Float>
    let r: Float
    let g: Float
    let b: Float
}

// MARK: - 单果信息

struct FruitInfo {
    let center: SIMD3<Float>
    let radiusM: Float
    let diameterCm: Float
    let volumeCm3: Float
    let weightG: Float
    let pointCount: Int
}

// MARK: - 估算结果

struct YieldResult {
    // 路线B（果实体积法）
    var nLidar: Int = 0           // LiDAR 检测到的果实数
    var nVisual: Int? = nil       // AI 视觉计数（可选）
    var correctionK: Float = 1.0  // 遮挡校正系数
    var yieldBVisibleKg: Float = 0  // 可见部分重量
    var yieldBCorrectedKg: Float = 0 // 遮挡校正后重量
    var meanDiameterCm: Float = 0
    var meanVolumeCm3: Float = 0

    // 路线A（冠层回归，可选）
    var yieldAKg: Float? = nil

    // 融合结果
    var yieldFinalKg: Float = 0
    var confidence: String = "low"  // "high" | "medium" | "low" | "manual_review"
    var methodUsed: String = ""
    var note: String = ""

    // 结构参数
    var treeHeightM: Float = 0
    var crownVolM3: Float = 0
}

// MARK: - 主估算器

class YieldEstimator {

    // ── 路线A 系数（训练后更新）─────────────────────
    // Y = b0 + b1*DBH + b2*H + b3*V_canopy + b4*D_EW + b5*D_NS
    // 默认全 0，采集称重数据训练后填入
    var regressionCoef: [Float] = [0, 0, 0, 0, 0, 0]
    var regressionTrained = false

    // ── 融合阈值 ──────────────────────────────────
    let diffThresholdHigh: Float = 0.15
    let diffThresholdMedium: Float = 0.30
    let weightA: Float = 0.4
    let weightB: Float = 0.6

    // MARK: 路线B：果实分割 + 体积计算

    func estimateRouteB(points: [ColoredPoint],
                        fruitType: FruitType,
                        nVisual: Int?) -> (fruits: [FruitInfo], result: YieldResult) {
        var result = YieldResult()
        result.nVisual = nVisual

        // Step 1: 颜色过滤
        let filter = fruitType.colorFilter
        print("🔴 [YieldEstimator] 颜色过滤: \(fruitType.rawValue), 过滤条件 r>=\(filter.rMin), g<=\(filter.gMax), b<=\(filter.bMax)")
        let filtered = points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
        print("🔴 [YieldEstimator] 颜色过滤后: \(filtered.count) / \(points.count) 点通过")
        guard filtered.count >= 10 else {
            result.note = "颜色过滤后点数不足（\(filtered.count)），无法检测果实"
            return ([], result)
        }

        // Step 2: 简单网格聚类（轻量版 DBSCAN 替代）
        let clusters = gridCluster(points: filtered, eps: fruitType.clusterEps,
                                   minPoints: 15)

        // Step 3: 按尺寸过滤 + 球体拟合
        var fruits: [FruitInfo] = []
        print("🔴 [YieldEstimator] 聚类后: \(clusters.count) 个候选")
        for cluster in clusters {
            guard let info = fitSphere(cluster: cluster,
                                       density: fruitType.density,
                                       diamMin: fruitType.diamMin,
                                       diamMax: fruitType.diamMax) else { continue }
            fruits.append(info)
        }

        result.nLidar = fruits.count
        print("🔴 [YieldEstimator] 尺寸过滤后: \(fruits.count) 个果实")

        guard !fruits.isEmpty else {
            result.note = "未检测到符合尺寸的果实"
            return ([], result)
        }

        // Step 4: 遮挡校正
        let k: Float
        if let nV = nVisual, result.nLidar > 0 {
            k = Float(nV) / Float(result.nLidar)
        } else {
            k = 1.0
        }
        result.correctionK = k

        // Step 5: 汇总
        let totalWeightG = fruits.reduce(0) { $0 + $1.weightG }
        let totalVolCm3  = fruits.reduce(0) { $0 + $1.volumeCm3 }

        result.yieldBVisibleKg   = totalWeightG / 1000
        result.yieldBCorrectedKg = totalWeightG * k / 1000
        guard !fruits.isEmpty else { return ([], result) }
        result.meanDiameterCm    = fruits.reduce(0) { $0 + $1.diameterCm } / Float(fruits.count)
        result.meanVolumeCm3     = totalVolCm3 / Float(fruits.count)

        return (fruits, result)
    }

    // MARK: 路线A：冠层结构回归

    func estimateRouteA(dbhCm: Float, heightM: Float,
                        crownVolM3: Float, dEW: Float, dNS: Float) -> Float? {
        guard regressionTrained else { return nil }
        let c = regressionCoef
        let y = c[0] + c[1]*dbhCm + c[2]*heightM + c[3]*crownVolM3 + c[4]*dEW + c[5]*dNS
        return max(0, y)
    }

    // MARK: 双路线融合

    func fuse(yieldA: Float?, yieldBCorrected: Float?) -> (finalKg: Float, confidence: String, method: String, note: String) {
        // 只有 A
        if yieldBCorrected == nil {
            guard let a = yieldA else {
                return (0, "low", "none", "无数据")
            }
            return (a, "medium", "A_only", "非成熟期，仅冠层回归")
        }
        let b = yieldBCorrected!

        // 只有 B
        guard let a = yieldA else {
            return (b, "medium", "B_only", "路线A未训练，仅果实体积法")
        }

        // 双路线
        let meanAB = (a + b) / 2
        let relDiff = abs(a - b) / (meanAB + 1e-6)

        if relDiff < diffThresholdHigh {
            let final_ = weightA * a + weightB * b
            return (final_, "high", "weighted_AB",
                    String(format: "双路线差异 %.1f%%<15%%，加权平均", relDiff*100))
        } else if relDiff < diffThresholdMedium {
            return (meanAB, "medium", "average_AB",
                    String(format: "双路线差异 %.1f%%（15~30%%），取均值", relDiff*100))
        } else {
            return (meanAB, "manual_review", "flagged",
                    String(format: "⚠️ 差异 %.1f%%>30%%，需人工复核（A=%.1fkg B=%.1fkg）",
                           relDiff*100, a, b))
        }
    }

    // MARK: 一站式入口

    func run(points: [ColoredPoint],
             fruitType: FruitType?,
             nVisual: Int?,
             dbhCm: Float = 0, heightM: Float = 0,
             crownVolM3: Float = 0, dEW: Float = 0, dNS: Float = 0,
             season: Season = .mature) -> (fruits: [FruitInfo], result: YieldResult) {

        var result = YieldResult()
        result.treeHeightM = heightM
        result.crownVolM3 = crownVolM3

        // 路线A
        result.yieldAKg = estimateRouteA(dbhCm: dbhCm, heightM: heightM,
                                          crownVolM3: crownVolM3, dEW: dEW, dNS: dNS)

        // 路线B（成熟期才跑）
        var fruits: [FruitInfo] = []
        if season == .mature, let ft = fruitType {
            let (f, bResult) = estimateRouteB(points: points, fruitType: ft, nVisual: nVisual)
            fruits = f
            result.nLidar            = bResult.nLidar
            result.nVisual           = bResult.nVisual
            result.correctionK       = bResult.correctionK
            result.yieldBVisibleKg   = bResult.yieldBVisibleKg
            result.yieldBCorrectedKg = bResult.yieldBCorrectedKg
            result.meanDiameterCm    = bResult.meanDiameterCm
            result.meanVolumeCm3     = bResult.meanVolumeCm3
        }

        // 融合
        let yieldBVal: Float? = (season == .mature && fruitType != nil && result.nLidar > 0)
            ? result.yieldBCorrectedKg : nil
        let (final_, conf, method, note) = fuse(yieldA: result.yieldAKg, yieldBCorrected: yieldBVal)
        result.yieldFinalKg = final_
        result.confidence   = conf
        result.methodUsed   = method
        result.note         = note

        return (fruits, result)
    }

    // MARK: - 轻量聚类（网格哈希法）

    /// 用网格哈希替代 DBSCAN，O(N) 复杂度，适合 iPad 实时跑
    private func gridCluster(points: [ColoredPoint], eps: Float, minPoints: Int) -> [[ColoredPoint]] {
        var grid: [String: [ColoredPoint]] = [:]
        let inv = 1.0 / eps
        for p in points {
            let key = "\(Int(p.pos.x * inv))_\(Int(p.pos.y * inv))_\(Int(p.pos.z * inv))"
            grid[key, default: []].append(p)
        }
        // 合并相邻格子
        var visited = Set<String>()
        var clusters: [[ColoredPoint]] = []

        for (key, cell) in grid {
            if visited.contains(key) { continue }
            var cluster = cell
            visited.insert(key)

            // 检查 26 个相邻格子
            let parts = key.split(separator: "_").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        if dx == 0 && dy == 0 && dz == 0 { continue }
                        let nk = "\(parts[0]+dx)_\(parts[1]+dy)_\(parts[2]+dz)"
                        if !visited.contains(nk), let neighbors = grid[nk] {
                            cluster.append(contentsOf: neighbors)
                            visited.insert(nk)
                        }
                    }
                }
            }
            if cluster.count >= minPoints {
                clusters.append(cluster)
            }
        }
        return clusters
    }

    // MARK: - 球体拟合

    private func fitSphere(cluster: [ColoredPoint],
                           density: Float,
                           diamMin: Float, diamMax: Float) -> FruitInfo? {
        let n = Float(cluster.count)
        let cx = cluster.reduce(0) { $0 + $1.pos.x } / n
        let cy = cluster.reduce(0) { $0 + $1.pos.y } / n
        let cz = cluster.reduce(0) { $0 + $1.pos.z } / n
        let center = SIMD3<Float>(cx, cy, cz)

        // 到中心距离的 85th percentile 作为半径
        let dists = cluster.map { simd_distance($0.pos, center) }.sorted()
        let idx85 = max(0, Int(Float(dists.count) * 0.85) - 1)
        let radius = dists[idx85]
        let diam = radius * 2

        guard diam >= diamMin && diam <= diamMax else { return nil }

        let diamCm = diam * 100
        let rCm = diamCm / 2
        let volCm3 = (4.0 / 3.0) * Float.pi * rCm * rCm * rCm
        let weightG = volCm3 * density

        return FruitInfo(center: center, radiusM: radius, diameterCm: diamCm,
                         volumeCm3: volCm3, weightG: weightG, pointCount: cluster.count)
    }
}

enum Season { case mature, off }
