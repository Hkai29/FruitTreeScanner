import SwiftUI

struct StepProgressView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let currentStep: Int
    let totalSteps: Int

    private var labels: [String] {
        L10n.StartFlow.progressLabels
    }

    private var layoutPolicy: StartFlowChromeLayoutPolicy {
        StartFlowChromeLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Design.Colors.Dark.bgElevated)
                        .frame(height: 3)

                    Capsule()
                        .fill(Design.Colors.harvest)
                        .frame(
                            width: proxy.size.width * progress,
                            height: 3
                        )
                }
            }
            .frame(height: 3)

            if layoutPolicy.stacksVertically {
                Text(progressAccessibilityText)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 0) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Text(labels[index])
                            .font(.caption2.weight(index + 1 == currentStep ? .semibold : .regular))
                            .foregroundColor(index + 1 <= currentStep ? Design.Colors.harvest : Design.Colors.Dark.textMuted)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityText)
    }

    private var progress: CGFloat {
        guard totalSteps > 1 else { return 1 }
        return CGFloat(currentStep - 1) / CGFloat(totalSteps - 1)
    }

    private var currentLabel: String {
        let index = min(max(currentStep - 1, 0), labels.count - 1)
        return labels[index]
    }

    private var progressAccessibilityText: String {
        L10n.StartFlow.progressAccessibility(
            currentStep: currentStep,
            totalSteps: totalSteps,
            label: currentLabel
        )
    }
}
