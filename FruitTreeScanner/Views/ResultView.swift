// ResultView.swift
// 扫描完成后的产量估算结果页

import SwiftUI

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void

    @ObservedObject private var tagStore = TagStore.shared
    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus = .scanned

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    ResultSummaryHeader(treeID: treeID, result: result)

                    if result.yieldFinalKg == 0 || result.confidence == "low" {
                        ResultDiagnosticsSection(result: result)
                    }

                    if result.nLidar > 0 {
                        FruitVolumeResultSection(result: result)
                    }

                    CrownVolumeResultSection(result: result)
                    AlgorithmParametersResultSection(result: result)

                    QuickTaggingCard(
                        treeID: treeID,
                        selectedPlotId: $selectedPlotId,
                        selectedTagIds: $selectedTagIds,
                        selectedStatus: $selectedStatus
                    )

                    ResultPostScanWorkflowSection(result: result)

                    ResultActionButtons(
                        onDismiss: onDismiss,
                        onDismissToHome: onDismissToHome
                    )
                }
                .padding(.top, 14)
            }
        }
        .task {
            restoreExistingAssignment()
        }
    }

    private func restoreExistingAssignment() {
        guard let existing = tagStore.getAssignment(treeId: treeID) else { return }
        selectedPlotId = existing.plotId
        selectedTagIds = Set(existing.tagIds)
        selectedStatus = existing.status == .reviewing ? .scanned : existing.status
    }
}
