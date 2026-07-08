import SwiftUI

struct QuickActionsGrid: View {
    var compactLandscape: Bool = false
    var onAction: ((QuickAction) -> Void)? = nil

    var body: some View {
        if compactLandscape {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    DashboardSectionHeader(title: "功能")

                    ScrollView(showsIndicators: false) {
                        LazyVGrid(
                            columns: landscapeColumns(for: proxy.size.width),
                            spacing: 10
                        ) {
                            ForEach(landscapeActions) { action in
                                QuickActionTile(action: action) {
                                    onAction?(action)
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
                .padding(14)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .dashboardSurface(cornerRadius: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                DashboardSectionHeader(title: "功能")
                VStack(spacing: 10) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        DashboardToolGroup(
                            title: mode.title,
                            icon: mode.icon,
                            actions: quickActions(for: mode),
                            onAction: onAction
                        )
                    }
                }
            }
        }
    }

    private var landscapeActions: [QuickAction] {
        quickActions(for: .scan) + quickActions(for: .history) + quickActions(for: .analytics)
    }

    private func landscapeColumns(for width: CGFloat) -> [GridItem] {
        let horizontalPadding: CGFloat = 28
        let spacing: CGFloat = 10
        let availableWidth = max(0, width - horizontalPadding)
        let minimumTileWidth: CGFloat = availableWidth >= 520 ? 118 : 104
        let rawCount = Int((availableWidth + spacing) / (minimumTileWidth + spacing))
        let count = max(2, min(4, rawCount))

        return Array(
            repeating: GridItem(.flexible(minimum: minimumTileWidth), spacing: spacing),
            count: count
        )
    }

    private func quickActions(for mode: AppMode) -> [QuickAction] {
        switch mode {
        case .scan:
            return [
                QuickAction(kind: .calibration, title: "校准参数", icon: "slider.horizontal.3", color: Design.Colors.Dark.info, description: "水果尺寸、聚类与误差记录"),
                QuickAction(kind: .importFile, title: "导入点云", icon: "square.and.arrow.down", color: Design.Colors.Dark.info, description: "加入已有 PLY 扫描文件")
            ]
        case .history:
            return [
                QuickAction(kind: .scanHistory, title: "扫描记录", icon: "folder", color: Design.Colors.harvest, description: "查看、删除和分享记录"),
                QuickAction(kind: .pointCloud, title: "点云查看", icon: "cube", color: Design.Colors.Dark.info, description: "打开最近或指定点云"),
                QuickAction(kind: .tagManagement, title: "地块标签", icon: "tag", color: Design.Colors.harvest, description: "维护地块、标签和状态"),
                QuickAction(kind: .batchExport, title: "批量导出", icon: "doc.richtext", color: Design.Colors.harvest, description: "导出多条扫描数据")
            ]
        case .analytics:
            return [
                QuickAction(kind: .yieldReport, title: "产量报告", icon: "chart.pie", color: Design.Colors.harvest, description: "汇总果数和重量"),
                QuickAction(kind: .compare, title: "树体对比", icon: "arrow.left.arrow.right", color: Design.Colors.harvest, description: "横向比较扫描结果"),
                QuickAction(kind: .trends, title: "趋势", icon: "chart.xyaxis.line", color: Design.Colors.Dark.info, description: "观察产量变化"),
                QuickAction(kind: .map, title: "果园地图", icon: "map", color: Design.Colors.Dark.info, description: "按位置查看树体")
            ]
        }
    }
}
