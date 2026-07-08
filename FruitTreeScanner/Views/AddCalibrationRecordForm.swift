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
            Text("从扫描记录带入")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Menu {
                ForEach(records.prefix(12)) { record in
                    Button {
                        onSelect(record)
                    } label: {
                        Text("\(record.treeID) · \(record.fruitCount) 个 · \(String(format: "%.1f kg", record.yieldKg))")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("选择最近扫描")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.md)
                .frame(height: 46)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("会自动填入树编号、估算果数、估算产量和扫描日期。")
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
            Text("基本信息")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            TextField("树木编号 (如 T001)", text: $treeID)
                .calibrationTextField()
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)

            Picker("水果类型", selection: $selectedFruitCategory) {
                ForEach(FruitCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
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
            Text("算法估算结果")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack {
                TextField("果实数量", text: $estimatedFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text("个")
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField("估算产量", text: $estimatedYieldKg)
                    .calibrationTextField()
                    .keyboardType(.decimalPad)

                Text("kg")
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
            Text("实际数据（可选）")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text("录入实际数据后，系统会自动计算误差")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack {
                TextField("人工计数", text: $manualFruitCount)
                    .calibrationTextField()
                    .keyboardType(.numberPad)

                Text("个")
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack {
                TextField("实际产量", text: $actualYieldKg)
                    .calibrationTextField()
                    .keyboardType(.decimalPad)

                Text("kg")
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
