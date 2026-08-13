// ResultView.swift
// 扫描完成后的产量估算结果页

import SwiftUI

struct ResultTaggingSelection: Equatable {
    let plotID: UUID?
    let tagIDs: Set<UUID>
    let status: ScanStatus

    init(assignment: TreeAssignment) {
        plotID = assignment.plotId
        tagIDs = Set(assignment.tagIds)
        status = assignment.status
    }
}

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let persistenceState: ScanResultPersistenceState
    let onRetryPersistence: () -> Void
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

                    if persistenceState.showsRecovery {
                        ResultPersistenceRecoveryCard(
                            state: persistenceState,
                            onRetry: onRetryPersistence
                        )
                    }

                    if result.yieldFinalKg == 0 || ResultReviewPolicy.needsReview(result.confidence) {
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
                        isDisabled: persistenceState.blocksResultDismissal,
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
        let selection = ResultTaggingSelection(assignment: existing)
        selectedPlotId = selection.plotID
        selectedTagIds = selection.tagIDs
        selectedStatus = selection.status
    }
}

struct ResultPersistenceRecoveryCard: View {
    let state: ScanResultPersistenceState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Design.Colors.warning)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.ScanResultPersistence.text(.failureTitle))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(L10n.ScanResultPersistence.text(.failureMessage))
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onRetry) {
                HStack(spacing: 8) {
                    if state.isRetrying {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(
                        L10n.ScanResultPersistence.text(
                            state.isRetrying ? .retrying : .retry
                        )
                    )
                    .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Design.Colors.apple)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(state.isRetrying)
            .accessibilityHint(L10n.ScanResultPersistence.text(.retryHint))
        }
        .padding(14)
        .background(Design.Colors.apple.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Design.Colors.apple.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 18)
    }
}
