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
            Text(L10n.Calibration.importSection)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Menu {
                ForEach(records.prefix(12)) { record in
                    Button {
                        onSelect(record)
                    } label: {
                        Text(L10n.Calibration.recentScanSummary(
                            treeID: record.treeID,
                            fruitCount: record.fruitCount,
                            yieldKg: record.yieldKg
                        ))
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(L10n.Calibration.selectRecentScan)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, Design.Space.sm)
                .frame(minHeight: 46)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(L10n.Calibration.importHint)
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
            Text(L10n.Calibration.estimatedSection)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack {
                TextField(L10n.Calibration.estimatedFruitCount, text: $estimatedFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text(L10n.Calibration.countUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField(L10n.Calibration.estimatedYield, text: $estimatedYieldKg)
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

            Text(L10n.Calibration.actualHint)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack {
                TextField(L10n.Calibration.manualFruitCount, text: $manualFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text(L10n.Calibration.countUnit)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField(L10n.Calibration.actualYield, text: $actualYieldKg)
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

private extension View {
    func calibrationTextField() -> some View {
        self
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Design.Colors.Dark.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
    }
}
