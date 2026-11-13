// AddCalibrationRecordForm.swift
// 新增校准记录表单。
//
// 四组字段各自独立：扫描记录带入、基本信息、算法估算、实际数据。
// 标识符左对齐，数值右对齐，单位固定在左侧。

import SwiftUI

struct AddCalibrationRecordForm: View {
    let recentRecords: [ScanFileRecord]
    @Binding var treeID: String
    @Binding var estimatedFruitCount: String
    @Binding var estimatedYieldKg: String
    @Binding var manualFruitCount: String
    @Binding var actualYieldKg: String
    @Binding var selectedFruitCategory: FruitCategory
    let onSelectRecentScan: (ScanFileRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !recentRecords.isEmpty {
                    AddCalibrationRecentScanImportSection(
                        records: recentRecords,
                        onSelect: onSelectRecentScan
                    )
                }

                AddCalibrationBasicInfoSection(
                    treeID: $treeID,
                    selectedFruitCategory: $selectedFruitCategory
                )
                AddCalibrationEstimateSection(
                    estimatedFruitCount: $estimatedFruitCount,
                    estimatedYieldKg: $estimatedYieldKg
                )
                AddCalibrationActualDataSection(
                    manualFruitCount: $manualFruitCount,
                    actualYieldKg: $actualYieldKg
                )
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct AddCalibrationRecentScanImportSection: View {
    let records: [ScanFileRecord]
    let onSelect: (ScanFileRecord) -> Void

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.recentScanSection,
            systemImage: "clock.arrow.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    ForEach(records.prefix(12)) { record in
                        Button {
                            onSelect(record)
                        } label: {
                            Text(
                                L10n.Calibration.recentScanSummary(
                                    treeID: record.treeID,
                                    count: record.fruitCount,
                                    yieldKg: record.yieldKg
                                )
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .accessibilityHidden(true)
                        Text(L10n.Calibration.recentScanPicker)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: Design.Touch.minimumHeight)
                    .background(
                        Design.Colors.Workspace.inset,
                        in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.Calibration.recentScanPicker)
                .accessibilityHint(L10n.Calibration.recentScanHint)

                Text(L10n.Calibration.recentScanHint)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AddCalibrationBasicInfoSection: View {
    @Binding var treeID: String
    @Binding var selectedFruitCategory: FruitCategory

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.basicInformation,
            systemImage: "tree"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.Calibration.treeIDPlaceholder, text: $treeID)
                    .calibrationIdentifierField()
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)

                InstrumentFormRow(label: L10n.Calibration.fruitType) {
                    Picker(L10n.Calibration.fruitType, selection: $selectedFruitCategory) {
                        ForEach(FruitCategory.allCases, id: \.self) { category in
                            Text(L10n.Fruit.name(for: category)).tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Design.Colors.Workspace.accent)
                    .accessibilityLabel(L10n.Calibration.fruitType)
                    .accessibilityValue(L10n.Fruit.name(for: selectedFruitCategory))
                }
            }
        }
    }
}

struct AddCalibrationEstimateSection: View {
    @Binding var estimatedFruitCount: String
    @Binding var estimatedYieldKg: String

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.estimateSection,
            systemImage: "chart.bar"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(L10n.Calibration.fruitUnit)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(minWidth: 24, alignment: .leading)

                    InstrumentTextField(
                        placeholder: L10n.Calibration.estimatedFruitCountPlaceholder,
                        text: $estimatedFruitCount,
                        keyboard: .numberPad
                    )
                }

                HStack(spacing: 10) {
                    Text(L10n.Calibration.kilogramUnit)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(minWidth: 24, alignment: .leading)

                    InstrumentTextField(
                        placeholder: L10n.Calibration.estimatedYieldPlaceholder,
                        text: $estimatedYieldKg,
                        keyboard: .decimalPad
                    )
                }
            }
        }
    }
}

struct AddCalibrationActualDataSection: View {
    @Binding var manualFruitCount: String
    @Binding var actualYieldKg: String

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.actualSection,
            systemImage: "target"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Calibration.actualDataHint)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(L10n.Calibration.fruitUnit)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(minWidth: 24, alignment: .leading)

                    InstrumentTextField(
                        placeholder: L10n.Calibration.manualFruitCountPlaceholder,
                        text: $manualFruitCount,
                        keyboard: .numberPad
                    )
                }

                HStack(spacing: 10) {
                    Text(L10n.Calibration.kilogramUnit)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(minWidth: 24, alignment: .leading)

                    InstrumentTextField(
                        placeholder: L10n.Calibration.actualYieldPlaceholder,
                        text: $actualYieldKg,
                        keyboard: .decimalPad
                    )
                }

                Text(L10n.Calibration.inputHint)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    /// 标识符输入框：左对齐、等宽字形，样式与仪器输入框一致。
    func calibrationIdentifierField() -> some View {
        self
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(Design.Colors.Workspace.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .background(
                Design.Colors.Workspace.inset,
                in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
    }
}
