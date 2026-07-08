import SwiftUI

struct AlgorithmParametersResultSection: View {
    let result: YieldResult

    private var presentation: ResultAlgorithmParametersPresentation {
        ResultAlgorithmParametersPresentation(result: result)
    }

    @ViewBuilder
    var body: some View {
        if result.clusterEps > 0 || result.pointCloudSize > 0 {
            ResultSectionCard(
                title: "采集摘要",
                icon: "checklist",
                color: Color(hex: "8E8E93")
            ) {
                if !result.fruitCategory.isEmpty {
                    ResultParameterRow(
                        title: "识别对象",
                        value: result.fruitCategory,
                        detail: "按当前果类参数完成本次估算。"
                    )
                }
                if result.pointCloudSize > 0 {
                    ResultParameterRow(
                        title: "采集质量",
                        value: "\(ResultValueFormatter.integer(result.pointCloudSize)) \(L10n.Result.unitPoints)",
                        detail: "深度\(result.diagnostics.depthAvailable ? "可用" : "不可用")，置信度为 \(ResultConfidencePresentation(result.confidence).label)。",
                        tint: Design.Colors.forest
                    )
                }
                ResultParameterRow(
                    title: "估算路径",
                    value: presentation.methodDisplayName,
                    detail: presentation.methodDetail,
                    tint: Design.Colors.harvest
                )
                if result.occlusionK > 1.01 {
                    ResultParameterRow(
                        title: "遮挡补偿",
                        value: presentation.occlusionDisplay,
                        detail: "扫描覆盖不足时才放大可见果实估计。"
                    )
                }
            }
        }
    }
}
