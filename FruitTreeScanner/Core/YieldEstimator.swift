// YieldEstimator.swift
// 产量估算引擎（Swift 原生实现，对应 Python 双路线）
// 无第三方依赖，全部跑在 iPad 本地

import Foundation

// MARK: - 主估算器

class YieldEstimator {

    var regressionCoef: [Float] = [0, 0, 0, 0, 0, 0]
    var regressionTrained = false

    let diffThresholdHigh: Float = 0.15
    let diffThresholdMedium: Float = 0.30
    let weightA: Float = 0.4
    let weightB: Float = 0.6

    // MARK: 路线B：果实分割 + 体积计算

    func estimateRouteB(points: [ColoredPoint],
                        fruitCategory: FruitCategory,
                        varietyParams: FruitVarietyParams? = nil,
                        nVisual: Int?,
                        colorFilter: ColorFilter? = nil) -> (fruits: [FruitInfo], result: YieldResult) {
        var result = YieldResult()
        result.nVisual = nVisual
        result.fruitCategory = fruitCategory.displayName
        result.pointCloudSize = points.count
        let params = varietyParams ?? FruitVarietyParams(category: fruitCategory)
        result.clusterEps = params.clusterEps
        result.clusterMinPoints = 15

        let filter = colorFilter ?? fruitCategory.colorFilter
        result.colorFilterDesc = filter.description
        let filtered = points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
        guard filtered.count >= 10 else {
            result.note = "颜色过滤后点数不足（\(filtered.count)），无法检测果实"
            return ([], result)
        }

        let clusterConfig = ClusterConfig(
            minPoints: 15,
            minDiameter: params.diamMin,
            maxDiameter: params.diamMax,
            baseEps: params.clusterEps,
            sphericityThreshold: params.sphericityThreshold
        )
        let clusterer = PointCloudCluster(config: clusterConfig)

        var fruits: [FruitInfo] = []
        let candidates = clusterer.processSync(points: filtered)
        for candidate in candidates {
            let massEstimate = SimpleFruitGeometryEstimator.estimate(
                candidate: candidate,
                fruitCategory: fruitCategory,
                densityGPerCm3: params.density
            )
            let info = FruitInfo(
                center: candidate.position,
                radiusM: candidate.diameter / 2,
                diameterCm: massEstimate.equivalentDiameterCm,
                volumeCm3: massEstimate.selectedVolumeCm3,
                weightG: massEstimate.estimatedWeightG,
                pointCount: candidate.pointCount,
                massEstimate: massEstimate
            )
            fruits.append(info)
        }

        result.nLidar = fruits.count

        guard !fruits.isEmpty else {
            result.note = "未检测到符合尺寸的果实"
            return ([], result)
        }

        let k: Float
        if let nV = nVisual, result.nLidar > 0, nV > 0 {
            k = Float(nV) / Float(result.nLidar)
        } else {
            k = 1.0
        }
        result.correctionK = k
        result.occlusionK = k

        let totalWeightG = fruits.reduce(0) { $0 + $1.weightG }
        let totalVolCm3  = fruits.reduce(0) { $0 + $1.volumeCm3 }

        result.yieldBVisibleKg   = totalWeightG / 1000
        result.yieldBCorrectedKg = totalWeightG * k / 1000
        result.meanDiameterCm    = fruits.reduce(0) { $0 + $1.diameterCm } / Float(fruits.count)
        result.meanVolumeCm3     = totalVolCm3 / Float(fruits.count)
        result.fruitMassEstimates = fruits.compactMap(\.massEstimate)

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
        if yieldBCorrected == nil {
            guard let a = yieldA else {
                return (0, "low", "none", "无数据")
            }
            return (a, "medium", "A_only", "非成熟期，仅冠层回归")
        }
        guard let b = yieldBCorrected else {
            return (0, "low", "none", "无数据")
        }

        guard let a = yieldA else {
            return (b, "medium", "B_only", "路线A未训练，仅果实体积法")
        }

        let meanAB = (a + b) / 2
        let scale = max(abs(a), abs(b), 1e-6)
        let relDiff = abs(a - b) / scale

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
             fruitCategory: FruitCategory?,
             varietyParams: FruitVarietyParams? = nil,
             nVisual: Int?,
             dbhCm: Float = 0, heightM: Float = 0,
             crownVolM3: Float = 0, dEW: Float = 0, dNS: Float = 0,
             season: Season = .mature,
             colorFilter: ColorFilter? = nil) -> (fruits: [FruitInfo], result: YieldResult) {

        var result = YieldResult()
        result.treeHeightM = heightM
        result.crownVolM3 = crownVolM3

        result.yieldAKg = estimateRouteA(dbhCm: dbhCm, heightM: heightM,
                                          crownVolM3: crownVolM3, dEW: dEW, dNS: dNS)

        var fruits: [FruitInfo] = []
        if season == .mature, let fc = fruitCategory {
            let (f, bResult) = estimateRouteB(
                points: points,
                fruitCategory: fc,
                varietyParams: varietyParams,
                nVisual: nVisual,
                colorFilter: colorFilter
            )
            fruits = f
            result.nLidar            = bResult.nLidar
            result.nVisual           = bResult.nVisual
            result.correctionK       = bResult.correctionK
            result.yieldBVisibleKg   = bResult.yieldBVisibleKg
            result.yieldBCorrectedKg = bResult.yieldBCorrectedKg
            result.meanDiameterCm    = bResult.meanDiameterCm
            result.meanVolumeCm3     = bResult.meanVolumeCm3
            result.clusterEps        = bResult.clusterEps
            result.clusterMinPoints  = bResult.clusterMinPoints
            result.fruitCategory     = bResult.fruitCategory
            result.colorFilterDesc   = bResult.colorFilterDesc
            result.occlusionK        = bResult.occlusionK
            result.pointCloudSize    = bResult.pointCloudSize
            result.fruitMassEstimates = bResult.fruitMassEstimates
        }

        let yieldBVal: Float? = (season == .mature && fruitCategory != nil && result.nLidar > 0)
            ? result.yieldBCorrectedKg : nil
        let (final_, conf, method, note) = fuse(yieldA: result.yieldAKg, yieldBCorrected: yieldBVal)
        result.yieldFinalKg = final_
        result.confidence   = conf
        result.methodUsed   = method
        result.note         = note

        return (fruits, result)
    }
}
