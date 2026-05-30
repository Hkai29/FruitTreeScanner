// HelpView.swift
// 使用帮助界面 - 扫描指南

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                // 扫描技巧
                helpSection(
                    icon: "viewfinder",
                    title: "扫描技巧",
                    items: [
                        "保持设备与果树距离 1-3 米",
                        "缓慢移动设备，从不同角度扫描",
                        "避免快速移动或剧烈抖动",
                        "确保追踪状态显示「优秀」或「良好」",
                        "尽量覆盖果树的各个面"
                    ]
                )

                // 速度提示说明
                helpSection(
                    icon: "hare.fill",
                    title: "速度检测",
                    items: [
                        "「太快」：降低移动速度",
                        "「太快」：可能导致点云稀疏",
                        "「适中」：最佳扫描速度",
                        "「太慢」：适当加快移动",
                        "「静止」：请移动设备进行扫描"
                    ]
                )

                // 追踪状态说明
                helpSection(
                    icon: "location.fill",
                    title: "追踪状态",
                    items: [
                        "「优秀」：追踪正常，点云质量高",
                        "「良好」：追踪正常，点云质量良好",
                        "「一般」：追踪受限，可能影响精度",
                        "「丢失」：追踪失败，请重新对准"
                    ]
                )

                // 果实检测说明
                helpSection(
                    icon: "leaf.fill",
                    title: "果实检测原理",
                    items: [
                        "使用 LiDAR 点云数据检测果实",
                        "通过颜色过滤识别目标水果",
                        "聚类分析分离单个果实",
                        "计算体积估算产量"
                    ]
                )

                // 校准说明
                helpSection(
                    icon: "slider.horizontal.3",
                    title: "算法校准",
                    items: [
                        "扫描后记录实际果实数量",
                        "采摘后称重实际产量",
                        "在「算法校准」中录入数据",
                        "系统计算误差帮您调整参数"
                    ]
                )
            }
            .padding(Design.Space.lg)
        }
        .background(Design.Colors.Dark.bgDeep.ignoresSafeArea())
        .navigationTitle("使用帮助")
        .navigationBarTitleDisplayMode(.large)
    }

    private func helpSection(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text(title)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            VStack(alignment: .leading, spacing: Design.Space.sm) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: Design.Space.sm) {
                        Text("•")
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                        Text(item)
                            .font(Design.Typography.body)
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                    }
                }
            }
        }
        .padding(Design.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
    }
}

#Preview {
    NavigationView {
        HelpView()
    }
}
