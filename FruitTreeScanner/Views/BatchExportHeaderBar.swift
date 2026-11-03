// BatchExportHeaderBar.swift
// 导出计数条：已选 / 可导出 / 总产量，全部来自真实记录。
//
// 选择进度是真实比例（已选 ÷ 可导出）；不可导出的记录单独提示原因。

import SwiftUI

struct BatchExportHeaderBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedCount: Int
    let totalCount: Int
    let unavailableCount: Int
    let totalYield: Float?
    let totalFruitCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentStatStrip {
                HStack(spacing: 0) {
                    InstrumentDatum(
                        label: BatchExportStrings.selectionLabel,
                        value: "\(selectedCount)",
                        unit: "条"
                    )
                    divider
                    InstrumentDatum(
                        label: BatchExportStrings.exportableLabel,
                        value: "\(totalCount)",
                        unit: "条"
                    )
                    divider
                    InstrumentDatum(
                        label: L10n.Dashboard.totalYield,
                        value: yieldValue,
                        unit: "kg",
                        tint: Design.Colors.Workspace.ink
                    )
                }
            }

            if totalCount > 0 {
                Group {
                    InstrumentProgress(
                        progress: Double(selectedCount) / Double(totalCount),
                        tint: Design.Colors.Workspace.accent
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Export.selectionProgress)
                .accessibilityValue(
                    L10n.Export.selectionSummary(
                        selectedCount: selectedCount,
                        totalCount: totalCount
                    )
                )
            }

            if unavailableCount > 0 {
                InstrumentNotice(
                    message: unavailableSummaryText,
                    tone: .attention,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Export.unavailableSummary(count: unavailableCount))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(width: 0.5, height: 34)
            .accessibilityHidden(true)
    }

    private var yieldValue: String {
        guard let totalYield else { return "—" }
        return String(format: "%.1f", totalYield)
    }

    private var unavailableSummaryText: String {
        dynamicTypeSize.isAccessibilitySize
            ? L10n.Export.compactUnavailableSummary(count: unavailableCount)
            : L10n.Export.unavailableSummary(count: unavailableCount)
    }
}
