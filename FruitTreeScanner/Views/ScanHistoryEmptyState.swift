import SwiftUI

/// 扫描档案空状态。
///
/// 两种空状态必须分开：
/// - 档案里一条记录都没有（`onStartScan` / `onImportFile` 可用）；
/// - 有记录但当前筛选没有命中（调用方不传动作）。
/// 两者都用仪器式空状态表达，不与"筛选无结果"混为一谈。
struct ScanHistoryEmptyState: View {
    let title: String
    let message: String
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    /// 次要动作（例如「清除搜索」）：与主操作分开，样式也更轻。
    ///
    /// 它只做**它自己**那件事：清搜索就只清搜索，不动地块与状态筛选 ——
    /// 用户的地块筛选是自己挑的，不该被一个「清空」顺手带走。
    var secondaryAction: (title: String, action: () -> Void)? = nil
    /// 次要动作的无障碍标识：「清除搜索」与「清除筛选」是两个出口，不能共用一个标识。
    var secondaryActionIdentifier: String? = nil
    var outerPadding = true

    var body: some View {
        InstrumentEmptyState(
            systemImage: "square.stack.3d.up",
            title: title,
            message: message
        ) {
            actions
        }
        .padding(outerPadding ? Design.Space.lg : 0)
    }

    @ViewBuilder
    private var actions: some View {
        if onStartScan != nil || onImportFile != nil || secondaryAction != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let onStartScan {
                    Button(action: onStartScan) {
                        Label(L10n.History.startScan, systemImage: "viewfinder")
                    }
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                }
                if let onImportFile {
                    Button(action: onImportFile) {
                        Label(L10n.History.importPLY, systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                }
                if let secondaryAction {
                    Button(action: secondaryAction.action) {
                        Text(secondaryAction.title)
                    }
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                    .accessibilityIdentifier(secondaryActionIdentifier ?? "historyEmpty.secondaryAction")
                }
            }
            .padding(.top, 4)
        }
    }
}
