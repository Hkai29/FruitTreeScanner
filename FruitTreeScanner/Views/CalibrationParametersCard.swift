// CalibrationParametersCard.swift
// 校准参数面板：滑杆改的是本地草稿，结束编辑时由上层提交。
//
// 名称与读数由滑杆自身承载，旁边的文字对无障碍隐藏，
// 这样读屏只会念一次标题，数值走 accessibilityValue。

import SwiftUI

struct CalibrationParametersCard: View {
    @Binding var maxDiameter: Double
    @Binding var minClusterPoints: Double
    @Binding var sphericity: Double

    let onCommitMinClusterPoints: () -> Void
    let onCommitMaxDiameter: () -> Void
    let onCommitSphericity: () -> Void
    @ObservedObject var settings: SettingsStore = .shared

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.parametersTitle,
            systemImage: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                CalibrationSliderRow(
                    title: L10n.Calibration.minimumClusterPoints,
                    valueText: "\(Int(minClusterPoints))",
                    value: $minClusterPoints,
                    range: 3...150,
                    step: 1,
                    onCommit: onCommitMinClusterPoints
                )

                DividerLine()

                CalibrationSliderRow(
                    title: L10n.Calibration.maximumClusterDiameter,
                    valueText: String(format: "%.3f m", maxDiameter),
                    value: $maxDiameter,
                    range: 0.04...0.20,
                    step: 0.005,
                    onCommit: onCommitMaxDiameter
                )

                DividerLine()

                CalibrationSliderRow(
                    title: L10n.Calibration.minimumSphericity,
                    valueText: String(format: "%.2f", sphericity),
                    value: $sphericity,
                    range: 0.2...0.8,
                    step: 0.02,
                    onCommit: onCommitSphericity
                )

                DividerLine()

                CalibrationHSVSummary(settings: settings)
            }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }

            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: commitWhenEditingEnds
            )
            .tint(Design.Colors.Workspace.accent)
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
    }

    private func commitWhenEditingEnds(_ isEditing: Bool) {
        if !isEditing {
            onCommit()
        }
    }
}

/// 颜色过滤范围：直接显示 SettingsStore 里的真实 HSV 阈值。
private struct CalibrationHSVSummary: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Calibration.hsvRange)
                .instrumentLabel()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    hueText
                    Spacer(minLength: 8)
                    saturationText
                }
                VStack(alignment: .leading, spacing: 3) {
                    hueText
                    saturationText
                }
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var hueText: some View {
        Text("H: \(Int(settings.hsvHMin))° - \(Int(settings.hsvHMax))°")
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .foregroundColor(Design.Colors.Workspace.secondary)
    }

    private var saturationText: some View {
        Text("S≥\(String(format: "%.0f%%", settings.hsvSMin * 100)) V≥\(String(format: "%.0f%%", settings.hsvVMin * 100))")
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .foregroundColor(Design.Colors.Workspace.secondary)
    }
}
