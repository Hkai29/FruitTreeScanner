// BatchExportOptionsView.swift
// 导出选项：格式、包含字段、分组方式。
//
// 格式与字段用筛选片，分组用分段控件；无障碍字号下退回菜单，
// 避免固定宽度被裁切。选项变化会清空已生成的导出文件（由调用方处理）。

import SwiftUI

struct BatchExportOptionsView: View {
    @Binding var exportFormat: BatchExportService.ExportFormat
    @Binding var exportOptions: BatchExportService.ExportOptions
    let isExporting: Bool
    let onOptionsChanged: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            formatSelector
            if exportFormat == .replay {
                replayNotice
            } else {
                optionsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 格式

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Export.formatTitle)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)

            formatControl

            Text(exportFormat.description)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var replayNotice: some View {
        InstrumentNotice(
            message: exportFormat.description,
            tone: .neutral,
            systemImage: "doc.badge.clock"
        )
        .accessibilityIdentifier("batchExport.replay.description")
    }

    // MARK: - 字段与分组

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Export.fieldsTitle)
                    .instrumentLabel()
                    .accessibilityAddTraits(.isHeader)

                fieldsControl
            }

            DividerLine()

            groupSelector
        }
    }

    private var groupSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Export.groupingTitle)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)

            groupPicker
        }
    }

    // MARK: - 控件

    @ViewBuilder
    private var formatControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(L10n.Export.formatTitle, selection: $exportFormat) {
                ForEach(BatchExportService.ExportFormat.allCases, id: \.self) { format in
                    Text(L10n.Export.formatName(format)).tag(format)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Design.Touch.minimumHeight)
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
            .accessibilityIdentifier("batchExport.format.picker")
            .accessibilityValue(L10n.Export.formatName(exportFormat))
            .onChange(of: exportFormat) { _ in
                onOptionsChanged()
            }
        } else {
            FlowLayout(spacing: 8) {
                ForEach(BatchExportService.ExportFormat.allCases, id: \.self) { format in
                    BatchExportFormatButton(
                        format: format,
                        isSelected: exportFormat == format,
                        action: { selectFormat(format) }
                    )
                }
            }
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityGroupingPicker
                .pickerStyle(.menu)
        } else {
            // 分组方式保留系统分段控件：它是既有的原生控件契约，
            // 且在日光工作区上使用浅色外观。
            groupingPicker
                .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var fieldsControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                fieldMenuButton(L10n.Export.treeIDField, keyPath: \.includeTreeID)
                fieldMenuButton(L10n.Export.fruitCountField, keyPath: \.includeFruitCount)
                fieldMenuButton(L10n.Export.yieldField, keyPath: \.includeYield)
                fieldMenuButton(L10n.Export.gpsField, keyPath: \.includeGPS)
                fieldMenuButton(L10n.Export.scanDateField, keyPath: \.includeDate)
            } label: {
                Label(
                    L10n.Export.compactFieldsSummary(includedCount: includedFieldCount),
                    systemImage: "checklist"
                )
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Design.Touch.minimumHeight)
            }
            .buttonStyle(.plain)
            .foregroundColor(Design.Colors.Workspace.accent)
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
            .accessibilityIdentifier("batchExport.optionMenu")
            .accessibilityLabel(L10n.Export.fieldsTitle)
            .accessibilityValue(
                L10n.Export.fieldsAccessibilityValue(includedCount: includedFieldCount)
            )
            .accessibilityHint(L10n.Export.fieldsMenuHint)
        } else {
            FlowLayout(spacing: 8) {
                BatchExportOptionToggle(
                    label: L10n.Export.treeIDField,
                    accessibilityIdentifier: "treeID",
                    isOn: optionBinding(\.includeTreeID)
                )
                BatchExportOptionToggle(
                    label: L10n.Export.fruitCountField,
                    accessibilityIdentifier: "fruitCount",
                    isOn: optionBinding(\.includeFruitCount)
                )
                BatchExportOptionToggle(
                    label: L10n.Export.yieldField,
                    accessibilityIdentifier: "yield",
                    isOn: optionBinding(\.includeYield)
                )
                BatchExportOptionToggle(
                    label: L10n.Export.gpsField,
                    accessibilityIdentifier: "gps",
                    isOn: optionBinding(\.includeGPS)
                )
                BatchExportOptionToggle(
                    label: L10n.Export.scanDateField,
                    accessibilityIdentifier: "date",
                    isOn: optionBinding(\.includeDate)
                )
            }
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
        }
    }

    // MARK: - 绑定

    private var includedFieldCount: Int {
        [
            exportOptions.includeTreeID,
            exportOptions.includeFruitCount,
            exportOptions.includeYield,
            exportOptions.includeGPS,
            exportOptions.includeDate
        ].filter { $0 }.count
    }

    private func fieldMenuButton(
        _ label: String,
        keyPath: WritableKeyPath<BatchExportService.ExportOptions, Bool>
    ) -> some View {
        let isIncluded = exportOptions[keyPath: keyPath]
        return Button {
            toggleOption(keyPath)
        } label: {
            if isIncluded {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(isIncluded ? L10n.Export.fieldIncluded : L10n.Export.fieldExcluded)
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }

    private var accessibilityGroupingPicker: some View {
        Picker(L10n.Export.groupingTitle, selection: $exportOptions.groupBy) {
            ForEach(BatchExportService.ExportOptions.GroupByOption.allCases, id: \.self) { option in
                Text(L10n.Export.compactGroupingName(option)).tag(option)
            }
        }
        .disabled(isExporting)
        .opacity(isExporting ? 0.65 : 1)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityIdentifier("batchExport.groupBy")
        .accessibilityValue(L10n.Export.groupingName(exportOptions.groupBy))
        .onChange(of: exportOptions.groupBy) { _ in
            onOptionsChanged()
        }
    }

    private var groupingPicker: some View {
        Picker(L10n.Export.groupingTitle, selection: $exportOptions.groupBy) {
            ForEach(BatchExportService.ExportOptions.GroupByOption.allCases, id: \.self) { option in
                Text(L10n.Export.groupingName(option)).tag(option)
            }
        }
        .disabled(isExporting)
        .opacity(isExporting ? 0.65 : 1)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityIdentifier("batchExport.groupBy")
        .accessibilityValue(L10n.Export.groupingName(exportOptions.groupBy))
        .onChange(of: exportOptions.groupBy) { _ in
            onOptionsChanged()
        }
    }

    private func optionBinding(_ keyPath: WritableKeyPath<BatchExportService.ExportOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { exportOptions[keyPath: keyPath] },
            set: { newValue in
                guard !isExporting else { return }
                exportOptions[keyPath: keyPath] = newValue
                onOptionsChanged()
            }
        )
    }

    private func selectFormat(_ format: BatchExportService.ExportFormat) {
        guard !isExporting else { return }
        exportFormat = format
        onOptionsChanged()
    }

    private func toggleOption(
        _ keyPath: WritableKeyPath<BatchExportService.ExportOptions, Bool>
    ) {
        guard !isExporting else { return }
        exportOptions[keyPath: keyPath].toggle()
        onOptionsChanged()
    }
}
