import SwiftUI

struct StepNavigationBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let canGoNext: Bool
    var isLaunching: Bool = false
    let onBack: () -> Void
    let onNext: () -> Void

    private var isLastStep: Bool { currentStep == totalSteps }

    private var layoutPolicy: StartFlowChromeLayoutPolicy {
        StartFlowChromeLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        Group {
            if layoutPolicy.stacksVertically {
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    stepCount

                    if canGoBack {
                        backButton
                    }

                    nextButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack {
                    if canGoBack {
                        backButton
                    }

                    Spacer()

                    stepCount

                    Spacer()

                    nextButton
                }
            }
        }
        .padding(.vertical, Design.Space.sm)
    }

    private var stepCount: some View {
        Text(L10n.StartFlow.stepCount(currentStep: currentStep, totalSteps: totalSteps))
            .font(.subheadline.weight(.medium))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .accessibilityLabel(
                L10n.StartFlow.stepCountAccessibility(
                    currentStep: currentStep,
                    totalSteps: totalSteps
                )
            )
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.medium))
                Text(L10n.StartFlow.previous)
                    .font(.body.weight(.medium))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
        .accessibilityLabel(L10n.StartFlow.previous)
        .accessibilityIdentifier("start.back")
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 4) {
                Text(nextButtonTitle)
                    .font(.body.weight(.semibold))
                if isLaunching {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                        .accessibilityHidden(true)
                } else if !isLastStep {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.medium))
                } else {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.medium))
                }
            }
            .foregroundColor(canGoNext ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textSecondary)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(canGoNext ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            )
        }
        .disabled(!canGoNext)
        .accessibilityLabel(nextButtonTitle)
        .accessibilityIdentifier(isLastStep ? "start.launchScan" : "start.next")
    }

    private var nextButtonTitle: String {
        if isLaunching {
            return L10n.StartFlow.launching
        }
        return isLastStep ? L10n.StartFlow.launch : L10n.StartFlow.next
    }
}
