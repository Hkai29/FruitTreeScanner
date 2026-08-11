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

                AddCalibrationRecordForm(
                    recentRecords: historyStore.scanFiles,
                    treeID: $treeID,
                    estimatedFruitCount: $estimatedFruitCount,
                    estimatedYieldKg: $estimatedYieldKg,
                    manualFruitCount: $manualFruitCount,
                    actualYieldKg: $actualYieldKg,
                    selectedFruitCategory: $selectedFruitCategory,
                    onSelectRecentScan: applyScanRecord
                )
            }
            .navigationTitle(L10n.Calibration.addNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        saveRecord()
                    }
                    .disabled(!canSave)
                    .accessibilityHint(L10n.Calibration.inputHint)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            historyStore.loadRecords()
        }
    }

    private var canSave: Bool {
        TreeIdentifierPolicy.isValid(treeID)
            && CalibrationRecordInputParser.requiredNonNegativeInt(estimatedFruitCount) != nil
            && CalibrationRecordInputParser.estimatedYieldKgOrZero(estimatedYieldKg) != nil
            && CalibrationRecordInputParser.isOptionalNonNegativeIntValid(manualFruitCount)
            && CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid(actualYieldKg)
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
        let normalizedTreeID = TreeIdentifierPolicy.normalized(treeID)
        guard TreeIdentifierPolicy.isValid(normalizedTreeID),
              let estimatedCount = CalibrationRecordInputParser.requiredNonNegativeInt(estimatedFruitCount),
              let estimatedYield = CalibrationRecordInputParser.estimatedYieldKgOrZero(estimatedYieldKg),
              CalibrationRecordInputParser.isOptionalNonNegativeIntValid(manualFruitCount),
              CalibrationRecordInputParser.isOptionalNonNegativeDoubleValid(actualYieldKg)
        else { return }
        let record = CalibrationRecord(
            id: UUID(),
            treeID: normalizedTreeID,
            scanDate: scanDate,
            estimatedFruitCount: estimatedCount,
            manualFruitCount: CalibrationRecordInputParser.optionalNonNegativeInt(manualFruitCount),
            estimatedYieldKg: estimatedYield,
            actualYieldKg: CalibrationRecordInputParser.optionalNonNegativeDouble(actualYieldKg),
            fruitType: selectedFruitCategory.displayName
        )
        onSave(record)
        dismiss()
    }
}
