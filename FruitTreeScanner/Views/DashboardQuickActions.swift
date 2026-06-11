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

private struct DashboardToolGroup: View {
    let title: String
    let icon: String
    let actions: [QuickAction]
    var compactLandscape: Bool = false
    var onAction: ((QuickAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compactLandscape ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvestLight)
                    .frame(width: compactLandscape ? 24 : 26, height: compactLandscape ? 24 : 26)
                    .background(Design.Colors.harvest.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(title)
                    .font(.system(size: compactLandscape ? 12 : 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
            }

            ForEach(actions) { action in
                QuickActionCard(action: action, compactLandscape: compactLandscape) {
                    onAction?(action)
                }
            }
        }
        .padding(compactLandscape ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardSurface(cornerRadius: 10)
    }
}

enum QuickActionKind: String {
    case startScan
    case quickScan
    case calibration
    case scanHistory
    case pointCloud
    case tagManagement
    case yieldReport
    case compare
    case trends
    case map
    case importFile
    case batchExport
}

struct QuickAction: Identifiable {
    let kind: QuickActionKind
    let title: String
    let icon: String
    let color: Color
    let description: String

    var id: QuickActionKind { kind }

    var imageName: String {
        switch kind {
        case .startScan: return "FeatureStartScan"
        case .quickScan: return "FeatureQuickScan"
        case .calibration: return "FeatureCalibration"
        case .scanHistory: return "FeatureScanHistory"
        case .pointCloud: return "FeaturePointCloud"
        case .tagManagement: return "FeatureTagManagement"
        case .yieldReport: return "FeatureYieldReport"
        case .compare: return "FeatureCompare"
        case .trends: return "FeatureTrends"
        case .map: return "FeatureMap"
        case .importFile: return "FeatureImportFile"
        case .batchExport: return "FeatureBatchExport"
        }
    }
}

struct QuickActionCard: View {
    let action: QuickAction
    var compactLandscape: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: compactLandscape ? 8 : 12) {
                DashboardFeatureImage(name: action.imageName, accent: action.color)
                    .frame(width: compactLandscape ? 42 : 76, height: compactLandscape ? 40 : 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: compactLandscape ? 13 : 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .lineLimit(1)
                    Text(action.description)
                        .font(.system(size: compactLandscape ? 10 : 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .lineLimit(compactLandscape ? 1 : 2)
                }

                Spacer(minLength: compactLandscape ? 4 : 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compactLandscape ? 8 : 10)
            .background(Design.Colors.Dark.bgElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.black.opacity(0.20), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title)，\(action.description)")
    }
}

private struct QuickActionTile: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 6) {
                DashboardFeatureImage(name: action.imageName, accent: action.color, cornerRadius: 7)
                    .frame(height: 34)

                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(action.color)
                        .frame(width: 18, height: 18)

                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Text(action.description)
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .background(Design.Colors.Dark.bgElevated.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title)，\(action.description)")
    }
}
