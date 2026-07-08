import SwiftUI

struct StepNavigationBar: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let canGoNext: Bool
    var isLaunching: Bool = false
    let onBack: () -> Void
    let onNext: () -> Void

    private var isLastStep: Bool { currentStep == totalSteps }

    var body: some View {
        HStack {
            if canGoBack {
                backButton
            }

            Spacer()

            Text("\(currentStep) / \(totalSteps)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            nextButton
        }
        .padding(.vertical, Design.Space.sm)
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                Text("上一步")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
        .accessibilityIdentifier("start.back")
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 4) {
                Text(isLaunching ? "启动中..." : (isLastStep ? "开始扫描" : "下一步"))
                    .font(.system(size: 15, weight: .semibold))
                if isLaunching {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                } else if !isLastStep {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .medium))
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
        .accessibilityIdentifier(isLastStep ? "start.launchScan" : "start.next")
    }
}
