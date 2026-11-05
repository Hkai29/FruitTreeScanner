// BatchExportContentView.swift
// 批量导出内容：左侧记录选择、右侧导出选项（宽屏两栏，窄屏上下排）。
//
// 计数、进度、阶段与完成位置全部来自真实记录与真实导出结果。

import SwiftUI

struct BatchExportContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private let contentWidth: CGFloat = 1080

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

    // MARK: - 计算

    private var exportableRecords: [ScanFileRecord] {
        BatchExportSelectionPolicy.exportableRecords(from: records)
    }

    private var normalizedSelectedRecords: Set<String> {
        BatchExportSelectionPolicy.normalizedSelection(selectedRecords, for: records)
    }

    private var selectedSummary: BatchExportTotals? {
        let selectedFiles = exportableRecords.filter {
            normalizedSelectedRecords.contains($0.id)
        }
        return BatchExportFormatting.totals(for: selectedFiles)
    }

    // MARK: - 主体

    private var populatedContent: some View {
        GeometryReader { geometry in
            let usesTwoColumns = geometry.size.width >= 780 && !dynamicTypeSize.isAccessibilitySize

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let exportedURL {
                            BatchExportCompletionPanel(
                                url: exportedURL,
                                onShare: onShareExport,
                                onClear: onClearExport
                            )
                            .id("batchExport.completed")
                        }

                        BatchExportHeaderBar(
                            selectedCount: normalizedSelectedRecords.count,
                            totalCount: exportableRecords.count,
                            unavailableCount: records.count - exportableRecords.count,
                            totalYield: selectedSummary?.totalYield,
                            totalFruitCount: selectedSummary?.totalFruitCount
                        )

                        if isExporting {
                            phaseSection
                        }

                        if usesTwoColumns {
                            HStack(alignment: .top, spacing: 18) {
                                recordColumn
                                optionsColumn
                                    .frame(width: 360)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                recordColumn
                                optionsColumn
                            }
                        }
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: exportedURL) { url in
                    if url != nil {
                        scrollProxy.scrollTo("batchExport.completed", anchor: .top)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBand
            }
        }
    }

    // MARK: - 分栏

    private var recordColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: BatchExportStrings.recordsSection)
            BatchExportRecordListView(
                records: records,
                selectedRecords: selectedRecords,
                isExporting: isExporting,
                onToggleSelection: onToggleSelection
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: BatchExportStrings.optionsSection)
            InstrumentPanel {
                BatchExportOptionsView(
                    exportFormat: $exportFormat,
                    exportOptions: $exportOptions,
                    isExporting: isExporting,
                    onOptionsChanged: onOptionsChanged
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 导出阶段

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: BatchExportStrings.phaseLabel)
            InstrumentPanel(tone: .accent) {
                InstrumentNotice(
                    message: BatchExportStrings.phaseExporting,
                    tone: .accent,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
    }

    // MARK: - 底部主操作

    private var actionBand: some View {
        VStack(spacing: 0) {
            BatchExportPrimaryButton(
                selectedCount: normalizedSelectedRecords.count,
                isExporting: isExporting,
                hasCompletedExport: exportedURL != nil,
                action: onPrimaryAction
            )
            .disabled((normalizedSelectedRecords.isEmpty || selectedSummary == nil) && !isExporting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }
}
