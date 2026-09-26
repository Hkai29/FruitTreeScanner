import SwiftUI

enum CalibrationScanRecordImportPolicy {
    static func isEligible(_ record: ScanFileRecord) -> Bool {
        record.persistenceState == .complete
    }

    static func eligibleRecords(from records: [ScanFileRecord]) -> [ScanFileRecord] {
        records.filter(isEligible)
    }
}

private struct ImportedCalibrationMetadata: Sendable {
    let algorithmRevision: String
    let calibrationContext: String
    let baselineCount: Int
    let baselineYield: Float

    static func load(for record: ScanFileRecord) -> Self? {
        guard let payload = PLYParserHelper.readValidatedCompanionMetadataPayload(for: record.fileURL),
              payload["treeID"] as? String == record.treeID,
              PLYParserHelper.nonNegativeIntValue(payload["fruitCount"]) == record.fruitCount,
              PLYParserHelper.nonNegativeFloatValue(payload["yieldKg"]) == record.yieldKg,
              let revision = payload["algorithmRevision"] as? String, !revision.isEmpty,
              let context = payload["calibrationContext"] as? String, !context.isEmpty,
              let baselineCount = PLYParserHelper.nonNegativeIntValue(payload["calibrationBaseCount"]),
              let baselineYield = PLYParserHelper.nonNegativeFloatValue(payload["calibrationBaseYieldKg"])
        else { return nil }
        return Self(
            algorithmRevision: revision,
            calibrationContext: context,
            baselineCount: baselineCount,
            baselineYield: baselineYield
        )
    }
}

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
    @State private var importedAlgorithmRevision: String?
    @State private var importedCalibrationContext: String?
    @State private var importedEstimateSignature = ""
    @State private var importToken = UUID()
    @State private var isImportingMetadata = false

    private var estimateSignature: String {
        "\(treeID)|\(estimatedFruitCount)|\(estimatedYieldKg)|\(selectedFruitCategory.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                AddCalibrationRecordForm(
                    recentRecords: CalibrationScanRecordImportPolicy.eligibleRecords(
                        from: historyStore.scanFiles
                    ),
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
                    .disabled(!canSave || isImportingMetadata)
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
        guard CalibrationScanRecordImportPolicy.isEligible(record) else { return }

        treeID = record.treeID
        estimatedFruitCount = "\(record.fruitCount)"
        estimatedYieldKg = String(format: "%.2f", record.yieldKg)
        scanDate = record.scanDate
        if let category = FruitCategory(rawValue: record.fruitType) {
            selectedFruitCategory = category
        } else if let category = FruitCategory.allCases.first(where: { $0.displayName == record.fruitType }) {
            selectedFruitCategory = category
        }
        importedAlgorithmRevision = nil
        importedCalibrationContext = nil
        importedEstimateSignature = estimateSignature
        let selectedSignature = importedEstimateSignature
        let selectedToken = UUID()
        importToken = selectedToken
        isImportingMetadata = true
        Task { @MainActor in
            let metadata = await Task.detached(priority: .utility) {
                ImportedCalibrationMetadata.load(for: record)
            }.value
            guard importToken == selectedToken else { return }
            isImportingMetadata = false
            guard let metadata, estimateSignature == selectedSignature else { return }
            importedAlgorithmRevision = metadata.algorithmRevision
            importedCalibrationContext = metadata.calibrationContext
            estimatedFruitCount = String(metadata.baselineCount)
            estimatedYieldKg = String(metadata.baselineYield)
            importedEstimateSignature = estimateSignature
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
            fruitType: selectedFruitCategory.displayName,
            algorithmRevision: importedEstimateSignature == estimateSignature ? importedAlgorithmRevision : nil,
            calibrationContext: importedEstimateSignature == estimateSignature ? importedCalibrationContext : nil
        )
        onSave(record)
        dismiss()
    }
}
