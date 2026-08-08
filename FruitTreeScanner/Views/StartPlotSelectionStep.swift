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
                title: L10n.StartSetup.text(.plotTitle),
                subtitle: L10n.StartSetup.text(.plotSubtitle)
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
            title: L10n.StartSetup.text(.plotEmptyTitle),
            message: L10n.StartSetup.text(.plotEmptyMessage),
            buttonTitle: L10n.StartSetup.text(.plotCreate),
            action: onAddPlot
        )
    }

    private var selectionList: some View {
        VStack(spacing: 0) {
            PlotSelectionRow(
                title: L10n.StartSetup.text(.plotNoneTitle),
                subtitle: L10n.StartSetup.text(.plotNoneSubtitle),
                color: Design.Colors.Dark.textMuted,
                isSelected: selectedPlotId == nil
            ) {
                selectedPlotId = nil
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            ForEach(plots) { plot in
                PlotSelectionRow(
                    title: plot.name,
                    subtitle: L10n.StartSetup.text(.plotAssignedSubtitle),
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
                    Text(L10n.StartSetup.text(.plotAdd))
                    Spacer()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, 13)
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
