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
            VStack(spacing: Design.Space.lg) {
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
            .padding(Design.Space.lg)
        }
    }
}

struct AddCalibrationRecentScanImportSection: View {
    let records: [ScanFileRecord]
    let onSelect: (ScanFileRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text(L10n.Calibration.recentScanSection)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityAddTraits(.isHeader)

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
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityHidden(true)
                    Text(L10n.Calibration.recentScanPicker)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, Design.Space.sm)
                .frame(minHeight: 46)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(L10n.Calibration.recentScanPicker)
            .accessibilityHint(L10n.Calibration.recentScanHint)

            Text(L10n.Calibration.recentScanHint)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct AddCalibrationBasicInfoSection: View {
    @Binding var treeID: String
    @Binding var selectedFruitCategory: FruitCategory

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text(L10n.Calibration.basicInformation)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityAddTraits(.isHeader)

            TextField(L10n.Calibration.treeIDPlaceholder, text: $treeID)
                .calibrationTextField()
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)

            Picker(L10n.Calibration.fruitType, selection: $selectedFruitCategory) {
                ForEach(FruitCategory.allCases, id: \.self) { category in
                    Text(L10n.Fruit.name(for: category)).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct AddCalibrationEstimateSection: View {
    @Binding var estimatedFruitCount: String
    @Binding var estimatedYieldKg: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text(L10n.Calibration.estimateSection)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityAddTraits(.isHeader)

            HStack {
                TextField(L10n.Calibration.estimatedFruitCountPlaceholder, text: $estimatedFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text(L10n.Calibration.fruitUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField(L10n.Calibration.estimatedYieldPlaceholder, text: $estimatedYieldKg)
                    .calibrationTextField()
                    .keyboardType(.decimalPad)

                Text(L10n.Calibration.kilogramUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct AddCalibrationActualDataSection: View {
    @Binding var manualFruitCount: String
    @Binding var actualYieldKg: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text(L10n.Calibration.actualSection)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityAddTraits(.isHeader)

            Text(L10n.Calibration.actualDataHint)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack {
                TextField(L10n.Calibration.manualFruitCountPlaceholder, text: $manualFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text(L10n.Calibration.fruitUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField(L10n.Calibration.actualYieldPlaceholder, text: $actualYieldKg)
                    .calibrationTextField()
                    .keyboardType(.decimalPad)

                Text(L10n.Calibration.kilogramUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Text(L10n.Calibration.inputHint)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private extension View {
    func calibrationTextField() -> some View {
        self
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, Design.Space.sm)
            .frame(minHeight: 46)
            .background(Design.Colors.Dark.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
    }
}
