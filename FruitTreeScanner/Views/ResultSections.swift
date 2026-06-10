import SwiftUI

struct ResultSummaryHeader: View {
    let treeID: String
    let result: YieldResult

    private var confidencePresentation: ResultConfidencePresentation {
        ResultConfidencePresentation(result.confidence)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.Result.scanResult)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text(treeID)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                Spacer()

                ConfidenceBadge(label: confidencePresentation.label, color: confidencePresentation.color)
            }

            ResultPrimaryMetric(
                title: L10n.Result.yieldTitle,
                value: ResultValueFormatter.finalYieldKg(result.yieldFinalKg),
                unit: "kg",
                color: confidencePresentation.color
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ResultSummaryPill(label: L10n.Result.fruit, value: "\(result.nLidar)")
                ResultSummaryPill(label: L10n.Result.pointCloud, value: result.pointCloudSize > 0 ? "\(result.pointCloudSize)" : "--")
                ResultSummaryPill(label: L10n.Result.methodLabel, value: result.methodUsed.isEmpty ? L10n.Result.methodEstimate : result.methodUsed)
            }

            if !result.note.isEmpty {
                Text(result.note)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .resultSurface(cornerRadius: 10)
        .padding(.horizontal, 18)
    }
}

struct ResultPrimaryMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(unit)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

struct FruitVolumeResultSection: View {
    let result: YieldResult

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.fruitVolumeMethod,
            icon: "circle.grid.3x3",
            color: Design.Colors.forest
        ) {
            ResultInfoRow(label: L10n.Result.correctedFruitCount, value: "\(result.nLidar) \(L10n.Result.unit)")
            if let nV = result.nVisual {
                ResultInfoRow(label: L10n.Result.visualCount, value: "\(nV) \(L10n.Result.unit)")
            }
            ResultInfoRow(label: L10n.Result.correctionFactor, value: ResultValueFormatter.correctionFactor(result.correctionK))
            ResultInfoRow(label: L10n.Result.visibleWeight, value: ResultValueFormatter.kilograms(result.yieldBVisibleKg))
            ResultInfoRow(label: L10n.Result.correctedWeight, value: ResultValueFormatter.kilograms(result.yieldBCorrectedKg), highlight: true)
            if result.meanDiameterCm > 0 {
                ResultInfoRow(label: L10n.Result.measuredDiameter, value: ResultValueFormatter.centimeters(result.meanDiameterCm))
            }
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

struct ResultDiagnosticsSection: View {
    let result: YieldResult

    private var diagnostics: ScanYieldDiagnostics {
        result.diagnostics
    }

    private var recommendations: [String] {
        DiagnosticRecommendation.recommendations(for: diagnostics.zeroYieldReasons)
    }

    private var imageModelStatusText: String {
        switch diagnostics.imageModelStatus {
        case "CoreML": return "本机模型"
        case "Fallback": return "备用模式"
        case "--": return "未知"
        default: return diagnostics.imageModelStatus
        }
    }

    var body: some View {
        ResultSectionCard(
            title: "0kg / 低置信度诊断",
            icon: "stethoscope",
            color: Design.Colors.warning
        ) {
            if !diagnostics.zeroYieldReasons.isEmpty {
                ForEach(diagnostics.zeroYieldReasons, id: \.self) { reason in
                    DiagnosticReasonRow(reason: reason)
                }
            } else if !result.note.isEmpty {
                DiagnosticReasonRow(reason: result.note)
            } else {
                DiagnosticReasonRow(reason: "有效果实数量不足，建议检查模型、深度和点云质量")
            }

            if !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Design.Colors.Dark.glassBorder)

                    Text("操作建议")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.bottom, 4)

                    ForEach(recommendations, id: \.self) { rec in
                        DiagnosticRecommendationRow(recommendation: rec)
                    }
                }
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            ResultInfoRow(label: "图像识别", value: imageModelStatusText)
            ResultInfoRow(label: "识别模型", value: diagnostics.imageModelName == "--" ? "未知" : diagnostics.imageModelName)
            if !diagnostics.imageFailureReason.isEmpty {
                ResultInfoRow(label: "图像检测失败", value: diagnostics.imageFailureReason)
            }
            ResultInfoRow(label: "点云点数", value: "\(diagnostics.pointCloudPointCount)")
            ResultInfoRow(label: "LiDAR 深度", value: diagnostics.depthAvailable ? "可用" : "不可用")
            ResultInfoRow(label: "图像处理帧", value: "\(diagnostics.imageFramesProcessed)")
            ResultInfoRow(label: "Observation 候选", value: "\(diagnostics.imageObservationCount)")
            ResultInfoRow(label: "置信度过滤", value: "\(diagnostics.imageConfidenceFilteredCount)")
            ResultInfoRow(label: "图像检测果实", value: "\(diagnostics.imageDetectionCount)")
            ResultInfoRow(label: "2D 去重后", value: "\(diagnostics.deduplicatedImageDetectionCount)")
            ResultInfoRow(label: "点云聚类候选", value: "\(diagnostics.pointCloudCandidateCount)")
            ResultInfoRow(label: "融合有效果实", value: "\(diagnostics.fusedFruitCount)")
            ResultInfoRow(label: "cloudOnly 保守模式", value: diagnostics.cloudOnlyConservativeMode ? "已进入" : "未进入")
        }
    }
}

struct ResultPostScanWorkflowSection: View {
    let result: YieldResult

    private var confidenceText: String {
        ResultConfidencePresentation(result.confidence).label
    }

    private var primaryAdvice: String {
        switch result.confidence {
        case "high":
            return "结果可直接入库；建议补充地块和状态标签后继续下一棵。"
        case "medium":
            return "结果可用但建议抽查点云预览，确认树冠背面和果实密集区没有明显缺口。"
        default:
            return "建议保留本次记录作为原始点云，并从主干到树冠背面补扫一次。"
        }
    }

    private var reviewFocus: String {
        if result.yieldFinalKg == 0 || result.confidence == "low" {
            return "优先检查 LiDAR 深度、点云数量、图像帧和果实是否清晰可见。"
        }
        if result.nLidar == 0 {
            return "点云已生成但果实候选不足，建议查看果实密集区是否进入画面。"
        }
        return "抽查树冠轮廓、果实密集区和冠幅估算，确认符合田间记录。"
    }

    var body: some View {
        ResultSectionCard(
            title: "扫描后处理建议",
            icon: "checklist",
            color: Design.Colors.harvest
        ) {
            ResultInfoRow(label: "当前置信度", value: confidenceText, highlight: result.confidence == "high")
            ResultInfoRow(label: "下一步", value: result.confidence == "low" ? "复扫或人工复核" : "保存并继续")

            VStack(alignment: .leading, spacing: 8) {
                ResultWorkflowAdviceRow(icon: "archivebox", text: primaryAdvice)
                ResultWorkflowAdviceRow(icon: "cube.transparent", text: reviewFocus)
                ResultWorkflowAdviceRow(icon: "tag", text: "完成后给记录补地块、品种和扫描状态，便于历史比较和批量导出。")
            }
        }
    }
}

private struct ResultWorkflowAdviceRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 18)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct DiagnosticReasonRow: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.warning)
                .padding(.top, 2)
            Text(reason)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct CrownVolumeResultSection: View {
    let result: YieldResult

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.crownVolumeMethod,
            icon: "tree.fill",
            color: Design.Colors.harvest
        ) {
            if let yA = result.yieldAKg {
                ResultInfoRow(label: L10n.Result.crownYield, value: ResultValueFormatter.kilograms(yA), highlight: true)
                ResultInfoRow(label: L10n.Result.crownVolume, value: ResultValueFormatter.cubicMeters(result.crownVolM3))
                ResultInfoRow(label: L10n.Result.treeHeight, value: ResultValueFormatter.meters(result.treeHeightM))
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text(L10n.Result.crownNotTrained)
                        .font(.system(size: 13))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }
}

struct AlgorithmParametersResultSection: View {
    let result: YieldResult

    @ViewBuilder
    var body: some View {
        if result.clusterEps > 0 || result.pointCloudSize > 0 {
            ResultSectionCard(
                title: "采集与识别质量",
                icon: "slider.horizontal.3",
                color: Color(hex: "8E8E93")
            ) {
                if !result.fruitCategory.isEmpty {
                    ResultParameterRow(
                        title: "识别对象",
                        value: result.fruitCategory,
                        detail: "使用当前选择的果实类别、尺寸范围和重量参数进行估算。"
                    )
                }
                if result.pointCloudSize > 0 {
                    ResultParameterRow(
                        title: "有效点云",
                        value: "\(ResultValueFormatter.integer(result.pointCloudSize)) \(L10n.Result.unitPoints)",
                        detail: "进入分析的 RGB-D 点数。点数越高，冠层结构和单果候选越稳定。",
                        tint: Design.Colors.forest
                    )
                }
                if result.clusterEps > 0 {
                    ResultParameterRow(
                        title: "聚类灵敏度",
                        value: clusterSensitivityLabel,
                        detail: "按果实尺寸把相邻点合并为单果候选，当前邻域约 \(ResultValueFormatter.dbscanEps(result.clusterEps))。"
                    )
                }
                if result.clusterMinPoints > 0 {
                    ResultParameterRow(
                        title: "单果确认",
                        value: "\(result.clusterMinPoints) 点以上",
                        detail: "候选果实需同时满足点数、尺寸和形状约束，降低枝叶误检。"
                    )
                }
                if !result.colorFilterDesc.isEmpty {
                    ResultParameterRow(
                        title: "颜色校验",
                        value: colorFilterDisplay,
                        detail: colorFilterDetail
                    )
                }
                ResultParameterRow(
                    title: "遮挡补偿",
                    value: occlusionDisplay,
                    detail: "根据扫描角度、冠层半径和深度估计被遮挡部分，避免只按正面可见果实计数。"
                )
                ResultParameterRow(
                    title: "估算路径",
                    value: methodDisplayName,
                    detail: methodDetail,
                    tint: Design.Colors.harvest
                )
            }
        }
    }

    private var clusterSensitivityLabel: String {
        switch result.clusterEps {
        case ..<0.018:
            return "精细"
        case ..<0.05:
            return "标准"
        default:
            return "宽松"
        }
    }

    private var colorFilterDisplay: String {
        if result.colorFilterDesc == "N/A" {
            return "未启用"
        }
        return "已启用"
    }

    private var colorFilterDetail: String {
        guard !result.colorFilterDesc.isEmpty, result.colorFilterDesc != "N/A" else {
            return "本次未使用颜色范围过滤，主要依赖模型和几何特征。"
        }
        return "结合当前果类成熟色范围筛选候选点；技术范围：\(result.colorFilterDesc)。"
    }

    private var occlusionDisplay: String {
        result.occlusionK > 1.01
            ? "补偿 ×\(ResultValueFormatter.occlusionK(result.occlusionK))"
            : "未放大"
    }

    private var methodDisplayName: String {
        switch result.methodUsed {
        case "weighted_AB":
            return "双路线加权"
        case "average_AB":
            return "双路线均值"
        case "A_only":
            return "冠层回归"
        case "B_only":
            return "果实体积"
        case "fusion_only":
            return "RGB + LiDAR 融合"
        case "flagged":
            return "人工复核"
        case "none", "":
            return "未形成估算"
        default:
            return result.methodUsed
        }
    }

    private var methodDetail: String {
        switch result.methodUsed {
        case "weighted_AB", "average_AB":
            return "综合冠层结构和可见果实体积，两条路线一致性越高置信度越高。"
        case "A_only":
            return "当前仅使用冠层结构回归，适合非成熟期或果实不可见场景。"
        case "B_only":
            return "当前以可见果实体积为主，结合遮挡补偿得到最终产量。"
        case "fusion_only":
            return "当前结果来自图像识别、LiDAR 点云聚类和遮挡补偿的融合。"
        case "flagged":
            return "两条估算路线差异较大，建议结合现场抽样复核。"
        default:
            return "显示本次最终产量采用的证据组合和估算策略。"
        }
    }
}
