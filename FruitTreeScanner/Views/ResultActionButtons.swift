// ResultActionButtons.swift
// 结果页底部动作：主操作 + 返回首页。

import SwiftUI

struct ResultActionButtons: View {
    let isDisabled: Bool
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onDismiss) {
                Label(L10n.Result.continueNext, systemImage: "plus")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .accessibilityIdentifier("result.continueNext")

            Button(action: onDismissToHome) {
                Label(L10n.Result.backToHome, systemImage: "house")
            }
            .buttonStyle(WorkspaceQuietButtonStyle(tint: Design.Colors.Workspace.secondary))
            .frame(minHeight: Design.Touch.minimumHeight)
            .accessibilityIdentifier("result.backToHome")
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
