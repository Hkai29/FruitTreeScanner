import SwiftUI

struct QuickActionsGrid: View {
    var onAction: ((QuickAction) -> Void)? = nil

    var body: some View {
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
    var onAction: ((QuickAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvestLight)
                    .frame(width: 26, height: 26)
                    .background(Design.Colors.harvest.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                QuickActionCard(action: action) {
                    onAction?(action)
                }
            }
        }
        .padding(12)
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
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 12) {
                DashboardFeatureImage(name: action.imageName, accent: action.color)
                    .frame(width: 76, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(action.description)
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
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
