import SwiftUI

struct BatchExportContentView: View {
    let records: [ScanFileRecord]
    let selectedRecords: Set<String>
    @Binding var exportFormat: BatchExportService.ExportFormat
    @Binding var exportOptions: BatchExportService.ExportOptions
    let exportedURL: URL?
    let isExporting: Bool
    let onStartScan: (() -> Void)?
    let onImportFile: (() -> Void)?
    let onToggleSelection: (String) -> Void
    let onOptionsChanged: () -> Void
    let onShareExport: () -> Void
    let onClearExport: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                BatchExportEmptyState(
                    onStartScan: onStartScan,
                    onImportFile: onImportFile
                )
            } else {
                populatedContent
            }
        }
    }

    private var selectedSummary: (totalYield: Float, totalFruitCount: Int) {
        let selectedFiles = records.filter {
            selectedRecords.contains($0.id) && $0.persistenceState == .complete
        }
        let totalYield = selectedFiles.reduce(0) { $0 + $1.yieldKg }
        let totalFruitCount = selectedFiles.reduce(0) { $0 + $1.fruitCount }
        return (totalYield, totalFruitCount)
    }

    private var populatedContent: some View {
        VStack(spacing: 0) {
            BatchExportHeaderBar(
                selectedCount: selectedRecords.count,
                totalCount: records.count,
                totalYield: selectedSummary.totalYield,
                totalFruitCount: selectedSummary.totalFruitCount
            )

            BatchExportRecordListView(
                records: records,
                selectedRecords: selectedRecords,
                isExporting: isExporting,
                onToggleSelection: onToggleSelection
            )

            BatchExportOptionsView(
                exportFormat: $exportFormat,
                exportOptions: $exportOptions,
                isExporting: isExporting,
                onOptionsChanged: onOptionsChanged
            )

            if let exportedURL {
                BatchExportCompletionPanel(
                    url: exportedURL,
                    onShare: onShareExport,
                    onClear: onClearExport
                )
                .padding(.horizontal, Design.Space.md)
                .padding(.top, Design.Space.md)
            }

            BatchExportPrimaryButton(
                selectedCount: selectedRecords.count,
                isExporting: isExporting,
                hasCompletedExport: exportedURL != nil,
                action: onPrimaryAction
            )
            .disabled(selectedRecords.isEmpty && !isExporting)
            .padding(Design.Space.md)
        }
    }
}
