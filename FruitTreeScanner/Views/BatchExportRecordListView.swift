import SwiftUI

struct BatchExportRecordListView: View {
    let records: [ScanFileRecord]
    let selectedRecords: Set<String>
    let isExporting: Bool
    let onToggleSelection: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Design.Space.sm) {
                ForEach(records) { record in
                    BatchExportRecordRow(
                        record: record,
                        isSelected: selectedRecords.contains(record.id),
                        onToggle: { onToggleSelection(record.id) }
                    )
                    .disabled(isExporting)
                    .opacity(isExporting ? 0.65 : 1)
                }
            }
            .padding(Design.Space.md)
        }
    }
}
