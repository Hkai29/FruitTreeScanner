import SwiftUI

struct StepProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    private let labels = ["编号", "地块", "季节", "标签", "确认"]

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

            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Text(labels[index])
                        .font(.system(size: 11, weight: index + 1 == currentStep ? .semibold : .regular))
                        .foregroundColor(index + 1 <= currentStep ? Design.Colors.harvest : Design.Colors.Dark.textMuted)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Design.Space.lg)
    }

    private var progress: CGFloat {
        guard totalSteps > 1 else { return 1 }
        return CGFloat(currentStep - 1) / CGFloat(totalSteps - 1)
    }
}
