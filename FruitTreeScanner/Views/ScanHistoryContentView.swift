import SwiftUI

struct ScanHistoryContentView: View {
    let filteredScans: [ScanFileRecord]
    @Binding var selectedPlotId: UUID?
    @Binding var selectedStatus: ScanStatus?
    @ObservedObject var tagStore: TagStore
    let onPreview: (ScanFileRecord) -> Void
    let onShare: (ScanFileRecord) -> Void
    let onRescan: (ScanFileRecord) -> Void
    let onMarkReview: (ScanFileRecord) -> Void
    let onDelete: (ScanFileRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashboardToolHeader(
                imageName: "FeatureScanHistory",
                title: L10n.History.headerTitle,
                subtitle: L10n.History.headerSubtitle,
                icon: "folder",
                accent: Design.Colors.harvest
            )
            .padding(.horizontal, Design.Space.md)
            .padding(.top, Design.Space.md)

            ScanHistoryFilterBar(
                selectedPlotId: $selectedPlotId,
                selectedStatus: $selectedStatus,
                tagStore: tagStore
            )
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)

            ScrollView {
                if filteredScans.isEmpty {
                    ScanHistoryEmptyState(
                        title: L10n.History.filteredEmptyTitle,
                        message: L10n.History.filteredEmptyMessage,
                        onStartScan: nil,
                        onImportFile: nil
                    )
                    .padding(.top, Design.Space.md)
                } else {
                    scanRows
                }
            }
        }
    }

    private var scanRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredScans) { record in
                ScanHistoryRow(
                    record: record,
                    onPreview: { onPreview(record) },
                    onShare: { onShare(record) },
                    onRescan: { onRescan(record) },
                    onMarkReview: { onMarkReview(record) },
                    onDelete: { onDelete(record) }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
