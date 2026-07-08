import SwiftUI

struct CalibrationParametersCard: View {
    @Binding var maxDiameter: Double
    @Binding var minClusterPoints: Double
    @Binding var sphericity: Double

    let onCommitMinClusterPoints: () -> Void
    let onCommitMaxDiameter: () -> Void
    let onCommitSphericity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            header

            Divider().background(Design.Colors.Dark.glassBorder)

            CalibrationSliderRow(
                title: "最小聚类点数",
                valueText: "\(Int(minClusterPoints))",
                value: $minClusterPoints,
                range: 3...150,
                step: 1,
                onCommit: onCommitMinClusterPoints
            )

            CalibrationSliderRow(
                title: "最大聚类直径 (m)",
                valueText: String(format: "%.3f m", maxDiameter),
                value: $maxDiameter,
                range: 0.04...0.20,
                step: 0.005,
                onCommit: onCommitMaxDiameter
            )

            CalibrationSliderRow(
                title: "最小球形度",
                valueText: String(format: "%.2f", sphericity),
                value: $sphericity,
                range: 0.2...0.8,
                step: 0.02,
                onCommit: onCommitSphericity
            )

            CalibrationHSVSummary()
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Design.Colors.Dark.glow)

            Text("算法参数")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()
        }
    }
}

private struct CalibrationSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack {
                Text(title)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()

                Text(valueText)
                    .font(Design.Typography.mono)
                    .foregroundColor(Design.Colors.Dark.glow)
            }

            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: commitWhenEditingEnds
            )
            .tint(Design.Colors.Dark.glow)
        }
    }

    private func commitWhenEditingEnds(_ isEditing: Bool) {
        if !isEditing {
            onCommit()
        }
    }
}

private struct CalibrationHSVSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text("HSV 色调范围")
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            HStack {
                Text("H: \(Int(SettingsStore.shared.hsvHMin))° - \(Int(SettingsStore.shared.hsvHMax))°")
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Spacer()

                Text("S≥\(String(format: "%.0f%%", SettingsStore.shared.hsvSMin * 100)) V≥\(String(format: "%.0f%%", SettingsStore.shared.hsvVMin * 100))")
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
    }
}
