// DashboardPrimaryActions.swift
// 工作台主操作。已并入工作台底部动作带，此处保留同一套视觉以备复用。

import SwiftUI

struct DashboardPrimaryActions: View {
    let onStartScan: () -> Void
    let onQuickScan: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStartScan) {
                Label("新建扫描", systemImage: "viewfinder")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .fill(Design.Colors.Workspace.accent)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onQuickScan) {
                Label("快速采集", systemImage: "bolt")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .fill(Design.Colors.Workspace.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
