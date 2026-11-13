// StartNavigationBar.swift
// 底部主操作带：每屏唯一的主操作（下一步 / 开始扫描）。
//
// 视觉沿用工作台的信号青实心按钮；返回由顶部导航的箭头承担，
// 因此这里不再重复放置"上一步"，避免同一动作出现两处。

import SwiftUI

struct StepNavigationBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let currentStep: Int
    let totalSteps: Int
    let canGoNext: Bool
    var isLaunching: Bool = false
    let onNext: () -> Void

    private var isLastStep: Bool { currentStep == totalSteps }

    private var layoutPolicy: StartFlowChromeLayoutPolicy {
        StartFlowChromeLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        Group {
            if layoutPolicy.stacksVertically && verticalSizeClass != .compact {
                nextButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                nextButton
            }
        }
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 6) {
                Text(nextButtonTitle)
                    .font(.headline)
                if isLaunching {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                        .accessibilityHidden(true)
                } else if isLastStep {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(canGoNext ? .white : Design.Colors.Workspace.secondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(canGoNext ? Design.Colors.Workspace.accent : Design.Colors.Workspace.inset)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
