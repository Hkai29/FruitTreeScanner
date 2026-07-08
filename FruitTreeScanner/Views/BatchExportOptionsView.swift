import SwiftUI

struct BatchExportOptionsView: View {
    @Binding var exportFormat: BatchExportService.ExportFormat
    @Binding var exportOptions: BatchExportService.ExportOptions
    let isExporting: Bool
    let onOptionsChanged: () -> Void

    var body: some View {
        VStack(spacing: Design.Space.md) {
            formatSelector
            optionsSection
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("导出格式")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack(spacing: Design.Space.md) {
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

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("包含字段")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            FlowLayout(spacing: Design.Space.sm) {
                BatchExportOptionToggle(
                    label: "果树编号",
                    accessibilityIdentifier: "treeID",
                    isOn: optionBinding(\.includeTreeID)
                )
                BatchExportOptionToggle(
                    label: "果实数量",
                    accessibilityIdentifier: "fruitCount",
                    isOn: optionBinding(\.includeFruitCount)
                )
                BatchExportOptionToggle(
                    label: "产量",
                    accessibilityIdentifier: "yield",
                    isOn: optionBinding(\.includeYield)
                )
                BatchExportOptionToggle(
                    label: "GPS位置",
                    accessibilityIdentifier: "gps",
                    isOn: optionBinding(\.includeGPS)
                )
                BatchExportOptionToggle(
                    label: "扫描日期",
                    accessibilityIdentifier: "date",
                    isOn: optionBinding(\.includeDate)
                )
            }
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)

            Divider()
                .background(Design.Colors.Dark.glassBorder)

            groupSelector
        }
    }

    private var groupSelector: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text("分组方式")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Picker("分组方式", selection: $exportOptions.groupBy) {
                ForEach(BatchExportService.ExportOptions.GroupByOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isExporting)
            .opacity(isExporting ? 0.65 : 1)
            .accessibilityIdentifier("batchExport.groupBy")
            .onChange(of: exportOptions.groupBy) { _ in
                onOptionsChanged()
            }
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
}
