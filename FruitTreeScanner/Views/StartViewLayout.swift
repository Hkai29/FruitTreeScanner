// StartViewLayout.swift
// 新建扫描流程的页面骨架：纸面页 + 顶部导航 + 步骤进度轨 + 底部主操作带。
//
// 与工作台首页共用同一套令牌：纸面底、发丝线、信号青、每屏一个主操作。

import SwiftUI

struct StartFlowChromeLayoutPolicy: Equatable, Sendable {
    let stacksVertically: Bool

    init(isAccessibilitySize: Bool) {
        stacksVertically = isAccessibilitySize
    }
}

struct StartFlowToolHeaderContent {
    let imageName: String
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
}

struct StartViewLayout<StepContent: View>: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let canGoNext: Bool
    let isLaunchingScan: Bool
    let header: StartFlowToolHeaderContent
    let onCancel: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder let stepContent: () -> StepContent

    /// 内容最大宽度：iPad 上居中，窄屏铺满。
    private let contentWidth: CGFloat = 1080

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StepProgressView(currentStep: currentStep, totalSteps: totalSteps)

                    StartStepHeader(
                        step: currentStep,
                        totalSteps: totalSteps,
                        title: header.title,
                        subtitle: header.subtitle,
                        systemImage: header.icon
                    )

                    stepContent()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .id(currentStep)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                StartFlowNavigationHeader(
                    title: L10n.StartFlow.navigationTitle,
                    cancelTitle: L10n.StartFlow.cancel,
                    cancelIdentifier: "start.cancel",
                    onCancel: onCancel,
                    backTitle: canGoBack ? L10n.StartFlow.previous : nil,
                    onBack: canGoBack ? onBack : nil
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActionBand
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .workspacePage()
    }

    /// 底部动作带：每屏唯一的主操作。
    private var bottomActionBand: some View {
        StepNavigationBar(
            currentStep: currentStep,
            totalSteps: totalSteps,
            canGoNext: canGoNext,
            isLaunching: isLaunchingScan,
            onNext: onNext
        )
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
    }
}

/// 顶部导航：返回 + 流程名 + 取消。
///
/// 系统导航栏会把文字按钮压到 36pt 高，这里保持 44pt 的完整触控目标。
struct StartFlowNavigationHeader: View {
    let title: String
    var cancelTitle: String
    var cancelIdentifier: String
    var onCancel: () -> Void
    /// 非空时显示返回箭头（步骤 > 1）。
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let backTitle, let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Workspace.ink)
                        .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backTitle)
                .accessibilityIdentifier("start.back")
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Text(cancelTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .frame(minWidth: Design.Touch.minimumWidth, minHeight: Design.Touch.minimumHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(cancelIdentifier)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Design.Colors.Workspace.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
    }
}
