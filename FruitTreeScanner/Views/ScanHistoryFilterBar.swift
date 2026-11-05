import SwiftUI

/// 扫描档案筛选条：地块 + 状态。
///
/// 筛选语义不变（仍是"全部 + 具体值"两个维度），
/// 只是外观换成仪器式筛选片，触控目标不小于 44pt。
struct ScanHistoryFilterLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let arrangement: Arrangement
    let minimumControlHeight: CGFloat

    init(isAccessibilitySize: Bool) {
        arrangement = isAccessibilitySize ? .vertical : .horizontal
        minimumControlHeight = Design.Touch.minimumHeight
    }
}

struct ScanHistoryFilterBar: View {
    @Binding var selectedPlotId: UUID?
    @Binding var selectedStatus: ScanStatus?
    @ObservedObject var tagStore: TagStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        switch layoutPolicy.arrangement {
        case .horizontal:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Space.sm) {
                    filters
                }
                .padding(.vertical, 2)
            }
        case .vertical:
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                filters
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var plotFilter: some View {
        FilterChip(
            title: selectedPlotId == nil ? L10n.History.allPlots : selectedPlotName,
            isSelected: selectedPlotId != nil,
            minimumHeight: layoutPolicy.minimumControlHeight
        ) {
            Button(L10n.History.allPlots) { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button(plot.name) { selectedPlotId = plot.id }
            }
        }
    }

    private var statusFilter: some View {
        FilterChip(
            title: selectedStatus.map(L10n.History.statusName(for:)) ?? L10n.History.allStatuses,
            isSelected: selectedStatus != nil,
            minimumHeight: layoutPolicy.minimumControlHeight
        ) {
            Button(L10n.History.allStatuses) { selectedStatus = nil }
            Divider()
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button(L10n.History.statusName(for: status)) { selectedStatus = status }
            }
        }
    }

    private var selectedPlotName: String {
        guard let selectedPlotId else { return L10n.History.allPlots }
        return tagStore.getPlot(id: selectedPlotId)?.name ?? L10n.History.plotFallback
    }

    private var layoutPolicy: ScanHistoryFilterLayoutPolicy {
        ScanHistoryFilterLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    @ViewBuilder
    private var filters: some View {
        plotFilter
        statusFilter
    }
}
