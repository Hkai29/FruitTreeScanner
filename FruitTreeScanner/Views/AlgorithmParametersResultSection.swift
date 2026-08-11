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
                title: L10n.Result.detail(.algorithmSummaryTitle),
                icon: "checklist",
                color: Color(hex: "8E8E93")
            ) {
                if !result.fruitCategory.isEmpty {
                    ResultParameterRow(
                        title: L10n.Result.detail(.algorithmTargetLabel),
                        value: result.fruitCategory,
                        detail: L10n.Result.detail(.algorithmTargetDetail)
                    )
                }
                if result.pointCloudSize > 0 {
                    ResultParameterRow(
                        title: L10n.Result.detail(.algorithmQualityLabel),
                        value: "\(ResultValueFormatter.integer(result.pointCloudSize)) \(L10n.Result.unitPoints)",
                        detail: L10n.Result.detailFormat(
                            .algorithmQualityDetailFormat,
                            arguments: [
                                L10n.Result.detail(
                                    result.diagnostics.depthAvailable ? .depthAvailableShort : .depthUnavailableShort
                                ),
                                ResultConfidencePresentation(result.confidence).label
                            ]
                        ),
                        tint: Design.Colors.forest
                    )
                }
                ResultParameterRow(
                    title: L10n.Result.detail(.algorithmPathLabel),
                    value: presentation.methodDisplayName,
                    detail: presentation.methodDetail,
                    tint: Design.Colors.harvest
                )
                if result.occlusionK > 1.01 {
                    ResultParameterRow(
                        title: L10n.Result.detail(.algorithmOcclusionLabel),
                        value: presentation.occlusionDisplay,
                        detail: L10n.Result.detail(.algorithmOcclusionDetail)
                    )
                }
            }
        }
    }
}
