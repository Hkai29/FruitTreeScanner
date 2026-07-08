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
            title: selectedPlotId == nil ? "全部地块" : selectedPlotName,
            isSelected: selectedPlotId != nil
        ) {
            Button("全部地块") { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button(plot.name) { selectedPlotId = plot.id }
            }
        }
    }

    private var statusFilter: some View {
        FilterChip(
            title: selectedStatus == nil ? "全部状态" : (selectedStatus?.rawValue ?? "状态"),
            isSelected: selectedStatus != nil
        ) {
            Button("全部状态") { selectedStatus = nil }
            Divider()
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button(status.rawValue) { selectedStatus = status }
            }
        }
    }

    private var selectedPlotName: String {
        guard let selectedPlotId else { return "全部地块" }
        return tagStore.getPlot(id: selectedPlotId)?.name ?? "地块"
    }
}
