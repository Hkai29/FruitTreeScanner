// StartProgressView.swift
// 步骤进度轨：显示当前步骤名称、步序与分段轨道。
//
// 轨道是"仪器刻度"而不是装饰进度条：已完成与当前步骤为信号青，未到达为发丝线。

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
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if layoutPolicy.stacksVertically {
                    VStack(alignment: .leading, spacing: 2) {
                        stepName
                        stepCount
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        stepName
                        Spacer(minLength: 8)
                        stepCount
                    }
                }
            }

            rail
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.StartFlow.stepCountAccessibility(currentStep: currentStep, totalSteps: totalSteps))
        .accessibilityValue(currentLabel)
    }

    private var stepName: some View {
        Text(currentLabel)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepCount: some View {
        Text(L10n.StartFlow.stepCount(currentStep: currentStep, totalSteps: totalSteps))
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundColor(Design.Colors.Workspace.muted)
            .fixedSize(horizontal: true, vertical: true)
    }

    /// 分段轨道：每一段对应一步。
    private var rail: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < currentStep
                          ? Design.Colors.Workspace.accent
                          : Design.Colors.Workspace.line)
                    .frame(height: 3)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var segmentCount: Int {
        max(totalSteps, 1)
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
