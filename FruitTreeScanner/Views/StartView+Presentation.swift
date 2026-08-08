import SwiftUI

extension StartView {
    var canGoNext: Bool {
        switch currentStep {
        case 1: return treeIdentifierDraft.validatedValue != nil
        default: return true
        }
    }

    var selectedPlot: Plot? {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }
    }

    var selectedTags: [GroupTag] {
        tagStore.tags.filter { selectedTagIds.contains($0.id) }
    }

    var stepHeader: StartFlowToolHeaderContent {
        switch currentStep {
        case 1:
            return StartFlowToolHeaderContent(
                imageName: "FeatureStartScan",
                title: "果树编号",
                subtitle: "先建立可追踪的树体档案，后续记录会自动归到这个编号。",
                icon: "number",
                accent: Design.Colors.harvest
            )
        case 2:
            return StartFlowToolHeaderContent(
                imageName: "FeatureMap",
                title: "地块归档",
                subtitle: "把扫描挂到对应地块，便于之后按区域筛选和汇总。",
                icon: "map.fill",
                accent: Design.Colors.forest
            )
        case 3:
            return StartFlowToolHeaderContent(
                imageName: "FeatureYieldReport",
                title: "估算阶段",
                subtitle: "当前开放成熟期融合估算；冠层回归完成实测标定后开放。",
                icon: "chart.bar.fill",
                accent: Design.Colors.harvest
            )
        case 4:
            return StartFlowToolHeaderContent(
                imageName: "FeatureTagManagement",
                title: "标签分组",
                subtitle: "用标签标记品种、试验组或管理状态，方便后续复盘。",
                icon: "tag.fill",
                accent: Design.Colors.forest
            )
        default:
            return StartFlowToolHeaderContent(
                imageName: "FeatureQuickScan",
                title: "启动扫描",
                subtitle: "确认信息后进入 LiDAR 采集，请围绕树体缓慢移动。",
                icon: "viewfinder",
                accent: Design.Colors.harvest
            )
        }
    }
}
