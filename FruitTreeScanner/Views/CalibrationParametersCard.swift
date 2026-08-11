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
                title: L10n.Calibration.minimumClusterPoints,
                valueText: "\(Int(minClusterPoints))",
                value: $minClusterPoints,
                range: 3...150,
                step: 1,
                onCommit: onCommitMinClusterPoints
            )

            CalibrationSliderRow(
                title: L10n.Calibration.maximumClusterDiameter,
                valueText: String(format: "%.3f m", maxDiameter),
                value: $maxDiameter,
                range: 0.04...0.20,
                step: 0.005,
                onCommit: onCommitMaxDiameter
            )

            CalibrationSliderRow(
                title: L10n.Calibration.minimumSphericity,
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
                .accessibilityHidden(true)

            Text(L10n.Calibration.parametersTitle)
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
    }
}

private struct CalibrationSliderRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    valueLabels
                }
            } else {
                HStack {
                    valueLabels
                }
            }

            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: commitWhenEditingEnds
            )
            .tint(Design.Colors.Dark.glow)
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
    }

    @ViewBuilder
    private var valueLabels: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityHidden(true)

            Text(valueText)
                .font(Design.Typography.mono)
                .foregroundColor(Design.Colors.Dark.glow)
                .accessibilityHidden(true)
        } else {
            Text(title)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Text(valueText)
                .font(Design.Typography.mono)
                .foregroundColor(Design.Colors.Dark.glow)
                .accessibilityHidden(true)
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
            Text(L10n.Calibration.hsvRange)
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
        .accessibilityElement(children: .combine)
    }
}
