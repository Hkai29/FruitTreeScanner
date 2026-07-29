import SwiftUI

struct QuickActionsGrid: View {
    var compactLandscape: Bool = false
    var onAction: ((QuickAction) -> Void)? = nil

    var body: some View {
        if compactLandscape {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    DashboardSectionHeader(title: L10n.Dashboard.tools)

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
                DashboardSectionHeader(title: L10n.Dashboard.tools)
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
                QuickAction(kind: .calibration, title: L10n.Dashboard.calibrationTitle, icon: "slider.horizontal.3", color: Design.Colors.Dark.info, description: L10n.Dashboard.calibrationDescription),
                QuickAction(kind: .importFile, title: L10n.Dashboard.importFileTitle, icon: "square.and.arrow.down", color: Design.Colors.Dark.info, description: L10n.Dashboard.importFileDescription)
            ]
        case .history:
            return [
                QuickAction(kind: .scanHistory, title: L10n.Dashboard.scanHistoryTitle, icon: "folder", color: Design.Colors.harvest, description: L10n.Dashboard.scanHistoryDescription),
                QuickAction(kind: .pointCloud, title: L10n.Dashboard.pointCloudTitle, icon: "cube", color: Design.Colors.Dark.info, description: L10n.Dashboard.pointCloudDescription),
                QuickAction(kind: .tagManagement, title: L10n.Dashboard.tagManagementTitle, icon: "tag", color: Design.Colors.harvest, description: L10n.Dashboard.tagManagementDescription),
                QuickAction(kind: .batchExport, title: L10n.Dashboard.batchExportTitle, icon: "doc.richtext", color: Design.Colors.harvest, description: L10n.Dashboard.batchExportDescription)
            ]
        case .analytics:
            return [
                QuickAction(kind: .yieldReport, title: L10n.Dashboard.yieldReportTitle, icon: "chart.pie", color: Design.Colors.harvest, description: L10n.Dashboard.yieldReportDescription),
                QuickAction(kind: .compare, title: L10n.Dashboard.compareTitle, icon: "arrow.left.arrow.right", color: Design.Colors.harvest, description: L10n.Dashboard.compareDescription),
                QuickAction(kind: .trends, title: L10n.Dashboard.trendsTitle, icon: "chart.xyaxis.line", color: Design.Colors.Dark.info, description: L10n.Dashboard.trendsDescription),
                QuickAction(kind: .map, title: L10n.Dashboard.mapTitle, icon: "map", color: Design.Colors.Dark.info, description: L10n.Dashboard.mapDescription)
            ]
        }
    }
}
