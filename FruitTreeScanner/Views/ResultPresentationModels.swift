import SwiftUI

struct ResultConfidencePresentation {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var label: String {
        switch rawValue {
        case "high": return L10n.Result.confidenceHigh
        case "medium": return L10n.Result.confidenceMedium
        case "manual_review": return L10n.Result.confidenceManualReview
        default: return L10n.Result.confidenceLow
        }
    }

    var color: Color {
        switch rawValue {
        case "high": return Design.Colors.forest
        case "medium": return Design.Colors.harvest
        case "manual_review": return Design.Colors.apple
        default: return Design.Colors.slate
        }
    }
}

enum ResultValueFormatter {
    static func finalYieldKg(_ value: Float) -> String {
        String(format: "%.1f", value)
    }

    static func correctionFactor(_ value: Float) -> String {
        String(format: "×%.2f", value)
    }

    static func kilograms(_ value: Float) -> String {
        String(format: "%.2f kg", value)
    }

    static func centimeters(_ value: Float) -> String {
        String(format: "%.1f cm", value)
    }

    static func cubicMeters(_ value: Float) -> String {
        String(format: "%.3f m³", value)
    }

    static func meters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    static func dbscanEps(_ value: Float) -> String {
        String(format: "%.3f m", value)
    }

    static func occlusionK(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

enum ResultReviewPolicy {
    static func needsReview(_ confidence: String) -> Bool {
        switch confidence {
        case "high", "medium":
            return false
        default:
            return true
        }
    }
}

enum DiagnosticRecommendation {
    private static let reasonToRecommendation: [String: [String]] = [
        "模型未加载": [
            "请重启应用以重新初始化本机 CoreML 识别模型",
            "检查 CoreML 模型文件 FruitsDetector.mlmodelc 是否完整"
        ],
        "深度不可用": [
            "当前设备可能不支持 LiDAR，建议使用 iPhone/iPad Pro",
            "如设备支持 LiDAR 但提示不可用，请重启应用"
        ],
        "点云数量不足": [
            "建议放慢扫描速度，从多个角度充分覆盖树冠",
            "确保 LiDAR 传感器清洁无障碍，采集更多点云数据"
        ],
        "未处理图像检测帧": [
            "请确保摄像头朝向果树，保持设备稳定 2-3 秒",
            "避免快速移动，给图像检测留出稳定画面"
        ],
        "图像检测无结果": [
            "建议在白天光线充足的条件下扫描",
            "确保果实清晰可见，避免逆光和强烈阴影"
        ],
        "候选被置信度过滤": [
            "图像检测发现疑似果实，但置信度过低被过滤",
            "建议调整拍摄距离和角度，确保果实清晰可见"
        ],
        "模型标签未映射到水果类别": [
            "检测到的类别未能匹配目标水果，请检查 fruit_mapping.json",
            "确认当前水果品类与扫描的水果一致"
        ],
        "点云聚类无候选": [
            "点云稀疏导致 DBSCAN 无法形成有效聚类",
            "建议扫描更长时间，从更多角度覆盖以增加点云密度"
        ],
        "融合验证失败": [
            "图像检测与点云位置未能匹配，可能因扫描抖动过大",
            "建议保持平稳的扫描速度和角度，避免剧烈移动"
        ],
        "cloudOnly 保守模式未接受候选": [
            "图像检测置信度过低，系统进入纯点云保守模式",
            "建议改善光照条件，确保果实清晰可见后重新扫描"
        ]
    ]

    static func recommendations(for reasons: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for reason in reasons {
            guard let recs = reasonToRecommendation[reason] else { continue }
            for rec in recs {
                if seen.insert(rec).inserted {
                    result.append(rec)
                }
            }
        }
        if result.isEmpty {
            result.append("建议检查本机 CoreML 识别模型、LiDAR 深度和点云质量后重新扫描")
        }
        return result
    }
}

struct ResultPostScanWorkflowAdvice {
    let result: YieldResult

    var confidenceText: String {
        ResultConfidencePresentation(result.confidence).label
    }

    var nextStepText: String {
        ResultReviewPolicy.needsReview(result.confidence) ? "复扫或人工复核" : "保存并继续"
    }

    var primaryAdvice: String {
        switch result.confidence {
        case "high":
            return "结果可直接入库；建议补充地块和状态标签后继续下一棵。"
        case "medium":
            return "结果可用但建议抽查点云预览，确认树冠背面和果实密集区没有明显缺口。"
        default:
            return "建议保留本次记录作为原始点云，并从主干到树冠背面补扫一次。"
        }
    }

    var reviewFocus: String {
        if result.yieldFinalKg == 0 || ResultReviewPolicy.needsReview(result.confidence) {
            return "优先检查 LiDAR 深度、点云数量、图像帧和果实是否清晰可见。"
        }
        if result.nLidar == 0 {
            return "点云已生成但果实候选不足，建议查看果实密集区是否进入画面。"
        }
        return "抽查树冠轮廓、果实密集区和冠幅估算，确认符合田间记录。"
    }
}

struct ResultAlgorithmParametersPresentation {
    let result: YieldResult

    var clusterSensitivityLabel: String {
        switch result.clusterEps {
        case ..<0.018:
            return "精细"
        case ..<0.05:
            return "标准"
        default:
            return "宽松"
        }
    }

    var colorFilterDisplay: String {
        if result.colorFilterDesc == "N/A" {
            return "未启用"
        }
        return "已启用"
    }

    var colorFilterDetail: String {
        guard !result.colorFilterDesc.isEmpty, result.colorFilterDesc != "N/A" else {
            return "本次未使用颜色范围过滤，主要依赖模型和几何特征。"
        }
        return "结合当前果类成熟色范围筛选候选点；技术范围：\(result.colorFilterDesc)。"
    }

    var occlusionDisplay: String {
        result.occlusionK > 1.01
            ? "补偿 ×\(ResultValueFormatter.occlusionK(result.occlusionK))"
            : "未放大"
    }

    var methodDisplayName: String {
        if result.methodUsed.hasSuffix("_coverage_review") {
            return "覆盖不足复核"
        }
        if result.methodUsed.hasSuffix("_coverage_limited") {
            return "有限覆盖估算"
        }

        switch result.methodUsed {
        case "weighted_AB":
            return "双路线加权"
        case "average_AB":
            return "双路线均值"
        case "A_only":
            return "冠层回归"
        case "B_only":
            return "果实体积"
        case "fusion_only", "fusion_visual_calibrated":
            return "RGB + LiDAR 融合"
        case "tracked_image_visual_calibrated":
            return "多帧视觉估计"
        case "image_visual_calibrated":
            return "视觉检测估计"
        case "cloud_only_calibrated":
            return "点云候选估计"
        case "flagged":
            return "人工复核"
        case "crown_untrained":
            return "冠层模型待标定"
        case "none", "":
            return "未形成估算"
        default:
            return result.methodUsed
        }
    }

    var methodDetail: String {
        if result.methodUsed.hasSuffix("_coverage_review") {
            return "遮挡校正依赖有限扫描角度，结果已标记为需要复扫或人工复核。"
        }
        if result.methodUsed.hasSuffix("_coverage_limited") {
            return "本次扫描覆盖有限，估产仍可参考，但建议抽查树冠背面和果实密集区。"
        }

        switch result.methodUsed {
        case "weighted_AB", "average_AB":
            return "综合冠层结构和可见果实体积，两条路线一致性越高置信度越高。"
        case "A_only":
            return "当前仅使用冠层结构回归，适合非成熟期或果实不可见场景。"
        case "B_only":
            return "当前以可见果实体积为主，结合遮挡补偿得到最终产量。"
        case "fusion_only", "fusion_visual_calibrated":
            return "当前结果来自图像识别、LiDAR 点云聚类和遮挡补偿的融合。"
        case "tracked_image_visual_calibrated":
            return "当前主要依赖多帧视觉轨迹和深度候选，适合点云较稀疏但画面稳定的扫描。"
        case "image_visual_calibrated":
            return "当前主要依赖视觉检测和品类平均参数，建议结合点云预览复核。"
        case "cloud_only_calibrated":
            return "当前主要依赖点云几何候选，建议确认果实颜色和图像检测条件。"
        case "flagged":
            return "两条估算路线差异较大，建议结合现场抽样复核。"
        case "crown_untrained":
            return "冠层回归尚未使用真实收获数据标定，本次不提供产量结论。"
        default:
            return "显示本次最终产量采用的证据组合和估算策略。"
        }
    }
}
