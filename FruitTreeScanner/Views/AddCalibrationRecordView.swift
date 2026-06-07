import SwiftUI

struct AddCalibrationRecordView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared

    let onSave: (CalibrationRecord) -> Void

    @State private var treeID = ""
    @State private var estimatedFruitCount = ""
    @State private var estimatedYieldKg = ""
    @State private var manualFruitCount = ""
    @State private var actualYieldKg = ""
    @State private var selectedFruitCategory: FruitCategory = .apple
    @State private var scanDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        if !historyStore.scanFiles.isEmpty {
                            recentScanImportSection
                        }

                        basicInfoSection
                        estimateSection
                        actualDataSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("添加校准记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRecord()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            historyStore.loadRecords()
        }
    }

    private var canSave: Bool {
        !treeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(estimatedFruitCount) != nil
    }

    private var recentScanImportSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text("从扫描记录带入")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Menu {
                ForEach(historyStore.scanFiles.prefix(12)) { record in
                    Button {
                        applyScanRecord(record)
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

    private var basicInfoSection: some View {
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

    private var estimateSection: some View {
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

    private var actualDataSection: some View {
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


    private func applyScanRecord(_ record: ScanFileRecord) {
        treeID = record.treeID
        estimatedFruitCount = "\(record.fruitCount)"
        estimatedYieldKg = String(format: "%.2f", record.yieldKg)
        scanDate = record.scanDate
        if let category = FruitCategory(rawValue: record.fruitType) {
            selectedFruitCategory = category
        } else if let category = FruitCategory.allCases.first(where: { $0.displayName == record.fruitType }) {
            selectedFruitCategory = category
        }
    }

    private func saveRecord() {
        let normalizedTreeID = treeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CalibrationRecord(
            id: UUID(),
            treeID: normalizedTreeID,
            scanDate: scanDate,
            estimatedFruitCount: Int(estimatedFruitCount) ?? 0,
            manualFruitCount: Int(manualFruitCount),
            estimatedYieldKg: Double(estimatedYieldKg) ?? 0,
            actualYieldKg: Double(actualYieldKg),
            fruitType: selectedFruitCategory.displayName
        )
        onSave(record)
        dismiss()
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
