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
                    let isExportable = BatchExportSelectionPolicy.isExportable(record)
                    BatchExportRecordRow(
                        record: record,
                        isExportable: isExportable,
                        isSelected: isExportable && selectedRecords.contains(record.id),
                        onToggle: { onToggleSelection(record.id) }
                    )
                    .disabled(isExporting || !isExportable)
                    .opacity(isExporting ? 0.65 : 1)
                }
            }
            .padding(Design.Space.md)
        }
    }
}
