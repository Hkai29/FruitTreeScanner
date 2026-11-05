import SwiftUI

struct ResultPostScanWorkflowSection: View {
    let result: YieldResult

    private var advice: ResultPostScanWorkflowAdvice {
        ResultPostScanWorkflowAdvice(result: result)
    }

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.detail(.workflowTitle),
            icon: "checklist",
            color: Design.Colors.Workspace.accent
        ) {
            ResultInfoRow(label: L10n.Result.detail(.workflowConfidenceLabel), value: advice.confidenceText, highlight: result.confidence == "high")
            ResultInfoRow(label: L10n.Result.detail(.workflowNextStepLabel), value: advice.nextStepText)

            VStack(alignment: .leading, spacing: 8) {
                ResultWorkflowAdviceRow(icon: "archivebox", text: advice.primaryAdvice)
                ResultWorkflowAdviceRow(icon: "cube.transparent", text: advice.reviewFocus)
                ResultWorkflowAdviceRow(icon: "tag", text: L10n.Result.detail(.workflowTaggingAdvice))
            }
        }
    }
}

private struct ResultWorkflowAdviceRow: View {
    let icon: String
    let text: String

    @ScaledMetric(relativeTo: .caption) private var iconFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var textFontSize: CGFloat = 13

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundColor(Design.Colors.Workspace.accent)
                .frame(minWidth: 18)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: textFontSize))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
