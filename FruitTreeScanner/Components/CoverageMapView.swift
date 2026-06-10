import SwiftUI

struct CoverageMapView: View {
    let completion: ScanCompletion

    private let maxGridCount = 10

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                mainRing
                statusInfo
            }

            if completion.overall > 0.1 {
                scoreIndicators
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.Colors.Dark.hudBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var mainRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                .frame(width: 56, height: 56)

            Circle()
                .trim(from: 0, to: CGFloat(completion.overall))
                .stroke(
                    statusColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: completion.overall)

            VStack(spacing: 0) {
                Text("\(completion.overallPercent)%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusColor)
                Text(completion.formattedDuration)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
    }

    private var statusInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(completion.statusTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(completion.statusHint)
                .font(.system(size: 11))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            if completion.voxelCount > 0 {
                Text("\(completion.voxelCount) 个空间采样")
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary.opacity(0.7))
            }
        }
    }

    private var scoreIndicators: some View {
        HStack(spacing: 16) {
            ScoreIndicator(
                label: "时长",
                value: completion.timeScore,
                color: Design.Colors.Dark.info
            )
            ScoreIndicator(
                label: "树冠",
                value: completion.voxelScore,
                color: Design.Colors.harvest
            )
            ScoreIndicator(
                label: "稳定",
                value: completion.stabilityScore,
                color: statusColor
            )
        }
    }

    private var statusColor: Color {
        if completion.overall >= 0.85 { return Design.Colors.harvest }
        if completion.overall >= 0.6 { return Design.Colors.success }
        if completion.overall >= 0.3 { return Design.Colors.warning }
        return Design.Colors.error
    }
}

private struct ScoreIndicator: View {
    let label: String
    let value: Float
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: geo.size.height * CGFloat(value))
                }
            }
            .frame(width: 24, height: 20)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}
