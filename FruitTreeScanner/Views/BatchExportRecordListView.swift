// BatchExportRecordListView.swift
// 记录选择列表：白底列表组 + 发丝线分隔。

import SwiftUI

struct BatchExportRecordListView: View {
    let records: [ScanFileRecord]
    let selectedRecords: Set<String>
    let isExporting: Bool
    let onToggleSelection: (String) -> Void

    var body: some View {
        InstrumentRowGroup {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                let isExportable = BatchExportSelectionPolicy.isExportable(record)
                BatchExportRecordRow(
                    record: record,
                    isExportable: isExportable,
                    isSelected: isExportable && selectedRecords.contains(record.id),
                    onToggle: { onToggleSelection(record.id) }
                )
                .disabled(isExporting || !isExportable)
                .opacity(isExporting ? 0.65 : 1)
                if index < records.count - 1 {
                    DividerLine(inset: 0)
                }
            }
        }
    }
}
