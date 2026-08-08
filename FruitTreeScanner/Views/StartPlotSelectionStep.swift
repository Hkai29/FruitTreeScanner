import SwiftUI

struct Step2_PlotSelection: View {
    let plots: [Plot]
    @Binding var selectedPlotId: UUID?
    let onAddPlot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 2,
                totalSteps: 5,
                title: "地块",
                subtitle: "可选。用于后续按地块筛选和汇总。"
            )

            if plots.isEmpty {
                emptyState
            } else {
                selectionList
            }
        }
    }

    private var emptyState: some View {
        StartEmptyAction(
            icon: "map",
            title: "还没有地块",
            message: "这次扫描可以跳过，之后也能在标签管理中维护。",
            buttonTitle: "创建地块",
            action: onAddPlot
        )
    }

    private var selectionList: some View {
        VStack(spacing: 0) {
            PlotSelectionRow(
                title: "暂不分配",
                subtitle: "扫描完成后再归档到地块",
                color: Design.Colors.Dark.textMuted,
                isSelected: selectedPlotId == nil
            ) {
                selectedPlotId = nil
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            ForEach(plots) { plot in
                PlotSelectionRow(
                    title: plot.name,
                    subtitle: "分配到该地块",
                    color: Color(hex: plot.colorHex),
                    isSelected: selectedPlotId == plot.id
                ) {
                    selectedPlotId = plot.id
                }

                if plot.id != plots.last?.id {
                    Divider().background(Design.Colors.Dark.glassBorder)
                }
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            Button(action: onAddPlot) {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "plus")
                    Text("添加地块")
                    Spacer()
                }
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, 13)
                .frame(minHeight: Design.Touch.minimumHeight)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .startSurface(cornerRadius: 10)
    }
}

struct PlotSelectionRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        StartSelectionRow(
            title: title,
            subtitle: subtitle,
            icon: "map",
            tint: color,
            isSelected: isSelected,
            action: action
        ) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
    }
}
