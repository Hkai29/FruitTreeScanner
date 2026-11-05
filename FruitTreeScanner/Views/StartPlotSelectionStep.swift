// StartPlotSelectionStep.swift
// 第 2 步：地块。
//
// 地块来自 TagStore 的真实数据：名称按标识符用等宽字形，
// 尾部显示该地块已归档的树木数量。

import SwiftUI

struct Step2_PlotSelection: View {
    let plots: [Plot]
    @Binding var selectedPlotId: UUID?
    /// 每个地块已归档的树木数量（来自 TagStore 的归档记录）。
    var treeCounts: [UUID: Int] = [:]
    let onAddPlot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstrumentSectionLabel(title: L10n.StartSetup.text(.plotTitle))

            if plots.isEmpty {
                StartEmptyAction(
                    icon: "map",
                    title: L10n.StartSetup.text(.plotEmptyTitle),
                    message: L10n.StartSetup.text(.plotEmptyMessage),
                    buttonTitle: L10n.StartSetup.text(.plotCreate),
                    usesSurveyPlate: true,
                    action: onAddPlot
                )
            } else {
                selectionList
            }
        }
    }

    // MARK: - 列表

    private var selectionList: some View {
        InstrumentRowGroup {
            PlotSelectionRow(
                title: L10n.StartSetup.text(.plotNoneTitle),
                subtitle: L10n.StartSetup.text(.plotNoneSubtitle),
                color: Design.Colors.Workspace.muted,
                isSelected: selectedPlotId == nil,
                isMonospacedTitle: false
            ) {
                selectedPlotId = nil
            }

            DividerLine(inset: 0)

            ForEach(plots) { plot in
                PlotSelectionRow(
                    title: plot.name,
                    subtitle: L10n.StartSetup.text(.plotAssignedSubtitle),
                    color: Color(hex: plot.colorHex),
                    isSelected: selectedPlotId == plot.id,
                    treeCount: treeCounts[plot.id]
                ) {
                    selectedPlotId = plot.id
                }

                if plot.id != plots.last?.id {
                    DividerLine(inset: 0)
                }
            }

            DividerLine(inset: 0)

            addPlotRow
        }
    }

    private var addPlotRow: some View {
        Button(action: onAddPlot) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.StartSetup.text(.plotAdd))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(Design.Colors.Workspace.accent)
            .frame(minHeight: Design.Touch.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.StartSetup.text(.plotAdd))
    }
}

struct PlotSelectionRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    /// 地块名是标识符，默认用等宽字形。
    var isMonospacedTitle: Bool = true
    /// 已归档树木数量；缺省表示没有归档记录。
    var treeCount: Int? = nil
    let action: () -> Void

    var body: some View {
        StartSelectionRow(
            title: title,
            subtitle: subtitle,
            isMonospacedTitle: isMonospacedTitle,
            isSelected: isSelected,
            action: action
        ) {
            HStack(spacing: 8) {
                if let treeCount {
                    Text("\(treeCount) \(L10n.Dashboard.treeCountUnit(treeCount))")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }
}
