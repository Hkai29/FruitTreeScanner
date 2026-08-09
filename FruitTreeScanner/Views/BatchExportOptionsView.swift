import SwiftUI

struct BatchExportOptionsView: View {
    @Binding var exportFormat: BatchExportService.ExportFormat
    @Binding var exportOptions: BatchExportService.ExportOptions
    let isExporting: Bool
    let onOptionsChanged: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Design.Space.md) {
            formatSelector
            optionsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text(L10n.Export.formatTitle)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            formatControl
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text(L10n.Export.fieldsTitle)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            fieldsControl

            Divider()
                .background(Design.Colors.Dark.glassBorder)
                .accessibilityHidden(true)

            groupSelector
        }
    }

    private var groupSelector: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(L10n.Export.groupingTitle)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            groupPicker
        }
    }

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
            FlowLayout(spacing: Design.Space.sm) {
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
            .foregroundColor(Design.Colors.harvest)
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
            .accessibilityIdentifier("batchExport.optionMenu")
            .accessibilityLabel(L10n.Export.fieldsTitle)
            .accessibilityValue(
                L10n.Export.fieldsAccessibilityValue(includedCount: includedFieldCount)
            )
            .accessibilityHint(L10n.Export.fieldsMenuHint)
        } else {
            FlowLayout(spacing: Design.Space.sm) {
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
