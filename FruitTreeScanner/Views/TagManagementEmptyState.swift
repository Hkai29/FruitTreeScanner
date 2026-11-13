// TagManagementEmptyState.swift
// 标签管理空状态：说明缺什么，并给出真实的创建 / 扫描入口。

import SwiftUI

struct TagManagementEmptyState: View {
    let icon: String
    /// 保留旧参数以兼容既有调用；新设计改用系统符号，不再使用插图资源。
    var imageName: String? = nil
    let title: String
    let message: String
    var primaryAction: DashboardSheetAction? = nil

    var body: some View {
        InstrumentEmptyState(
            systemImage: icon,
            title: title,
            message: message
        ) {
            if let primaryAction {
                Button(action: primaryAction.action) {
                    Label(primaryAction.title, systemImage: primaryAction.icon)
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }
}
