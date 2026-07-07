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
                        value: presentation.clusterSensitivityLabel,
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
                        value: presentation.colorFilterDisplay,
                        detail: presentation.colorFilterDetail
                    )
                }
                ResultParameterRow(
                    title: "遮挡补偿",
                    value: presentation.occlusionDisplay,
                    detail: "根据扫描角度、冠层半径和深度估计被遮挡部分，避免只按正面可见果实计数。"
                )
                ResultParameterRow(
                    title: "估算路径",
                    value: presentation.methodDisplayName,
                    detail: presentation.methodDetail,
                    tint: Design.Colors.harvest
                )
            }
        }
    }
}
