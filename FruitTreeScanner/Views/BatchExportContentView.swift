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

    private var exportableRecords: [ScanFileRecord] {
        BatchExportSelectionPolicy.exportableRecords(from: records)
    }

    private var normalizedSelectedRecords: Set<String> {
        BatchExportSelectionPolicy.normalizedSelection(selectedRecords, for: records)
    }

    private var selectedSummary: (totalYield: Float, totalFruitCount: Int) {
        let selectedFiles = exportableRecords.filter {
            normalizedSelectedRecords.contains($0.id)
        }
        let totalYield = selectedFiles.reduce(0) { $0 + $1.yieldKg }
        let totalFruitCount = selectedFiles.reduce(0) { $0 + $1.fruitCount }
        return (totalYield, totalFruitCount)
    }

    private var populatedContent: some View {
        VStack(spacing: 0) {
            BatchExportHeaderBar(
                selectedCount: normalizedSelectedRecords.count,
                totalCount: exportableRecords.count,
                unavailableCount: records.count - exportableRecords.count,
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
                selectedCount: normalizedSelectedRecords.count,
                isExporting: isExporting,
                hasCompletedExport: exportedURL != nil,
                action: onPrimaryAction
            )
            .disabled(normalizedSelectedRecords.isEmpty && !isExporting)
            .padding(Design.Space.md)
        }
    }
}
