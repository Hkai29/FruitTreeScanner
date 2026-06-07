// YieldEstimator.swift
// 产量估算引擎（Swift 原生实现，对应 Python 双路线）
// 无第三方依赖，全部跑在 iPad 本地

import Foundation
import simd

// MARK: - 单果信息

struct FruitInfo {
    let center: SIMD3<Float>
    let radiusM: Float
    let diameterCm: Float
    let volumeCm3: Float
    let weightG: Float
    let pointCount: Int
    let massEstimate: FruitMassEstimate?
}

// MARK: - 估算结果

struct YieldResult: Sendable {
    var nLidar: Int = 0
    var nVisual: Int? = nil
    var correctionK: Float = 1.0
    var yieldBVisibleKg: Float = 0
    var yieldBCorrectedKg: Float = 0
    var meanDiameterCm: Float = 0
    var meanVolumeCm3: Float = 0

    var yieldAKg: Float? = nil

    var yieldFinalKg: Float = 0
    var confidence: String = "low"
    var methodUsed: String = ""
    var note: String = ""

    var treeHeightM: Float = 0
    var crownVolM3: Float = 0

    var clusterEps: Float = 0
    var clusterMinPoints: Int = 0
    var fruitCategory: String = ""
    var colorFilterDesc: String = ""
    var occlusionK: Float = 1.0
    var pointCloudSize: Int = 0
    var diagnostics: ScanYieldDiagnostics = ScanYieldDiagnostics()
    var fruitMassEstimates: [FruitMassEstimate] = []
}

struct ScanYieldDiagnostics: Sendable, Equatable {
    var pointCloudPointCount: Int = 0
    var imageDetectionCount: Int = 0
    var deduplicatedImageDetectionCount: Int = 0
    var pointCloudCandidateCount: Int = 0
    var fusedFruitCount: Int = 0
    var cloudOnlyConservativeMode: Bool = false
    var depthAvailable: Bool = false
    var imageFramesProcessed: Int = 0
    var imageObservationCount: Int = 0
    var imageConfidenceFilteredCount: Int = 0
    var imageMappedFruitCount: Int = 0
    var imageModelStatus: String = "--"
    var imageModelName: String = "--"
    var imageFailureReason: String = ""
    var zeroYieldReasons: [String] = []

    var shortStatus: String {
        if zeroYieldReasons.isEmpty {
            return fusedFruitCount > 0 ? "融合有效" : "等待估算"
        }
        return zeroYieldReasons.joined(separator: "；")
    }
}

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

enum Season { case mature, off }
