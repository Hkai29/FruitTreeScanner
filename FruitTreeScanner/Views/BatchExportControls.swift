// BatchExportControls.swift
// 批量导出的控件：格式片、字段片、主操作按钮，以及本页新增文案。
//
// 格式与字段选择使用仪器筛选片；主操作使用实心信号青。

import SwiftUI

// MARK: - 本页文案

enum BatchExportStrings {
    static let selectionLabel = NSLocalizedString(
        "export.stat.selected",
        value: "已选",
        comment: "Batch export selected-record count label"
    )
    static let exportableLabel = NSLocalizedString(
        "export.stat.exportable",
        value: "可导出",
        comment: "Batch export exportable-record count label"
    )
    static let recordsSection = NSLocalizedString(
        "export.section.records",
        value: "记录选择",
        comment: "Batch export record-selection section label"
    )
    static let optionsSection = NSLocalizedString(
        "export.section.options",
        value: "导出选项",
        comment: "Batch export options section label"
    )
    static let phaseLabel = NSLocalizedString(
        "export.phase.label",
        value: "导出阶段",
        comment: "Batch export phase section label"
    )
    static let phaseExporting = NSLocalizedString(
        "export.phase.exporting",
        value: "正在生成导出文件，可随时取消。",
        comment: "Batch export in-flight phase message"
    )
    static let outputLocation = NSLocalizedString(
        "export.completion.location",
        value: "输出位置",
        comment: "Batch export completion output-location label"
    )
    static let selectedFormat = NSLocalizedString(
        "export.completion.format",
        value: "导出格式",
        comment: "Batch export completion format label"
    )
}

// MARK: - 格式选择

/// 导出格式片。选中的格式用信号青实底，未选中用描边。
struct BatchExportFormatButton: View {
    let format: BatchExportService.ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        InstrumentChip(
            title: L10n.Export.formatName(format),
            isSelected: isSelected,
            action: action
        )
        .padding(.vertical, 6)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityIdentifier("batchExport.format.\(format.accessibilityIdentifier)")
        .accessibilityValue(isSelected ? L10n.Export.formatSelected : L10n.Export.formatNotSelected)
        .accessibilityHint(L10n.Export.formatSelectionHint)
    }
}

// MARK: - 字段选择

/// 导出字段片。包含 = 选中（信号青实底），不含 = 描边。
struct BatchExportOptionToggle: View {
    let label: String
    let accessibilityIdentifier: String
    @Binding var isOn: Bool

    var body: some View {
        InstrumentChip(title: label, isSelected: isOn) {
            isOn.toggle()
        }
        .padding(.vertical, 6)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityIdentifier("batchExport.option.\(accessibilityIdentifier)")
        .accessibilityValue(isOn ? L10n.Export.fieldIncluded : L10n.Export.fieldExcluded)
        .accessibilityHint(L10n.Export.fieldToggleHint)
    }
}

// MARK: - 主操作

/// 底部主操作：导出 / 取消导出。取消是真实的取消路径。
struct BatchExportPrimaryButton: View {
    let selectedCount: Int
    let isExporting: Bool
    let hasCompletedExport: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .accessibilityHidden(true)
                }

                Text(buttonTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorkspacePrimaryButtonStyle())
        .accessibilityLabel(buttonTitle)
        .accessibilityHint(buttonHint)
        .accessibilityIdentifier(isExporting ? "batchExport.cancel" : "batchExport.export")
    }

    private var buttonTitle: String {
        if isExporting { return L10n.Export.primaryCancel }
        if hasCompletedExport {
            return L10n.Export.primaryReexportTitle(recordCount: selectedCount)
        }
        return L10n.Export.primaryExportTitle(recordCount: selectedCount)
    }

    private var buttonHint: String {
        if isExporting { return L10n.Export.primaryCancelHint }
        if hasCompletedExport { return L10n.Export.primaryReexportHint }
        return L10n.Export.primaryExportHint
    }
}

private extension BatchExportService.ExportFormat {
    var accessibilityIdentifier: String {
        switch self {
        case .csv: return "csv"
        case .excel: return "excel"
        case .json: return "json"
        case .replay: return "replay"
        }
    }
}
