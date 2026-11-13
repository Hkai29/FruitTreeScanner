// ResultView.swift
// 扫描完成后的结果页：证据等级 → 估产读数 → 诊断 → 归档动作。
//
// 可靠性判定完全沿用 ResultReliabilityPresentation（含 .fused 诊断），
// 页面只负责把等级、建议与诊断完整呈现出来。

import SwiftUI

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let persistenceState: ScanResultPersistenceState
    let onRetryPersistence: () -> Void
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void

    @ObservedObject var tagStore = TagStore.shared
    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus = .scanned

    var body: some View {
        ZStack {
            Design.Colors.Workspace.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    ResultSummaryHeader(treeID: treeID, result: result)
                        .padding(16)
                        .background(
                            Design.Colors.Workspace.surface,
                            in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                        )

                    if persistenceState.showsRecovery {
                        ResultPersistenceRecoveryCard(
                            state: persistenceState,
                            onRetry: onRetryPersistence
                        )
                    }

                    if result.yieldFinalKg == 0 || ResultReviewPolicy.needsReview(result.confidence) {
                        ResultDiagnosticsSection(result: result)
                            .accessibilityIdentifier("screen.result.diagnostics")
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
                        selectedStatus: $selectedStatus,
                        tagStore: tagStore
                    )

                    ResultPostScanWorkflowSection(result: result)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ResultActionButtons(
                    isDisabled: persistenceState.blocksResultDismissal,
                    onDismiss: onDismiss,
                    onDismissToHome: onDismissToHome
                )
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .background(Design.Colors.Workspace.surface)
                .overlay(alignment: .top) {
                    Design.Colors.Workspace.line.frame(height: 0.5)
                }
            }
        }
        .environment(\.colorScheme, .light)
        .tint(Design.Colors.Workspace.accent)
        .task {
            restoreExistingAssignment()
        }
    }

    private func restoreExistingAssignment() {
        guard let existing = tagStore.getAssignment(treeId: treeID) else { return }
        selectedPlotId = existing.plotId
        selectedTagIds = Set(existing.tagIds)
        /* 结果页的草稿属于「这一次扫描」：旧的复核请求针对上一次结果，
           新结果从「已扫描」起算；这次结果自己的成色由记录级可靠性表达。 */
        selectedStatus = existing.status == .reviewing ? .scanned : existing.status
    }
}

/// 保存失败时的恢复面板。必须保留重试入口与真实失败说明。
struct ResultPersistenceRecoveryCard: View {
    let state: ScanResultPersistenceState
    let onRetry: () -> Void

    var body: some View {
        InstrumentPanel(
            label: L10n.ScanResultPersistence.text(.failureTitle),
            systemImage: "exclamationmark.triangle.fill",
            tone: .attention
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.ScanResultPersistence.text(.failureMessage))
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        if state.isRetrying {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(.footnote, design: .default).weight(.semibold))
                        }
                        Text(
                            L10n.ScanResultPersistence.text(
                                state.isRetrying ? .retrying : .retry
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Design.Touch.minimumHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .fill(Design.Colors.Workspace.attention)
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.isRetrying)
                .accessibilityHint(L10n.ScanResultPersistence.text(.retryHint))
            }
        }
    }
}
