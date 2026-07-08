import SwiftUI

struct BatchExportEmptyState: View {
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "tray",
                imageName: "FeatureBatchExport",
                title: "暂无可导出的记录",
                message: "扫描或导入 PLY 文件后，可在这里批量选择并导出 CSV 或 Excel 兼容表格。",
                primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
                secondaryAction: action(title: "导入 PLY", icon: "square.and.arrow.down", handler: onImportFile)
            )

            Spacer()
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}
