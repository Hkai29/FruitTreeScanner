import SwiftUI

struct BatchExportHeaderBar: View {
    let selectedCount: Int
    let totalCount: Int
    let unavailableCount: Int
    let totalYield: Float
    let totalFruitCount: Int

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            DashboardToolHeader(
                imageName: "FeatureBatchExport",
                title: "批量导出",
                subtitle: "选择多条扫描记录，导出字段、产量和地块标签。",
                icon: "doc.richtext",
                accent: Design.Colors.harvest
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选择 \(selectedCount) / \(totalCount) 条可导出记录")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    if selectedCount > 0 {
                        Text("\(String(format: "%.1f", totalYield)) kg · \(totalFruitCount) 个果实")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }

                Spacer()
            }

            if unavailableCount > 0 {
                Label(
                    "\(unavailableCount) 条记录未完整保存或数据无效，未纳入导出",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if totalCount > 0 {
                ProgressView(value: Double(selectedCount), total: Double(totalCount))
                    .tint(Design.Colors.harvest)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }
}
