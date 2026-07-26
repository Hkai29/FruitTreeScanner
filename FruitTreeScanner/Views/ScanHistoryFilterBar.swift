import SwiftUI

struct ScanHistoryFilterBar: View {
    @Binding var selectedPlotId: UUID?
    @Binding var selectedStatus: ScanStatus?
    @ObservedObject var tagStore: TagStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Space.sm) {
                plotFilter
                statusFilter
            }
        }
    }

    private var plotFilter: some View {
        FilterChip(
            title: selectedPlotId == nil ? ScanHistoryText.allPlots : selectedPlotName,
            isSelected: selectedPlotId != nil
        ) {
            Button(ScanHistoryText.allPlots) { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button(plot.name) { selectedPlotId = plot.id }
            }
        }
    }

    private var statusFilter: some View {
        FilterChip(
            title: selectedStatus == nil
                ? ScanHistoryText.allStatuses
                : selectedStatus.map(ScanHistoryText.statusName) ?? ScanHistoryText.status,
            isSelected: selectedStatus != nil
        ) {
            Button(ScanHistoryText.allStatuses) { selectedStatus = nil }
            Divider()
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button(ScanHistoryText.statusName(status)) { selectedStatus = status }
            }
        }
    }

    private var selectedPlotName: String {
        guard let selectedPlotId else { return ScanHistoryText.allPlots }
        return tagStore.getPlot(id: selectedPlotId)?.name ?? ScanHistoryText.plot
    }
}
