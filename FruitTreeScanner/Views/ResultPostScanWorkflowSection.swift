import SwiftUI

struct ResultPostScanWorkflowSection: View {
    let result: YieldResult

    private var advice: ResultPostScanWorkflowAdvice {
        ResultPostScanWorkflowAdvice(result: result)
    }

    var body: some View {
        ResultSectionCard(
            title: "扫描后处理建议",
            icon: "checklist",
            color: Design.Colors.harvest
        ) {
            ResultInfoRow(label: "当前置信度", value: advice.confidenceText, highlight: result.confidence == "high")
            ResultInfoRow(label: "下一步", value: advice.nextStepText)

            VStack(alignment: .leading, spacing: 8) {
                ResultWorkflowAdviceRow(icon: "archivebox", text: advice.primaryAdvice)
                ResultWorkflowAdviceRow(icon: "cube.transparent", text: advice.reviewFocus)
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
