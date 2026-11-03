// CalibrationRecordsSection.swift
// 校准记录区：状态提示、真实记录列表与空状态。
//
// 记录本身由 CalibrationRecordsController 负责加载与落盘，这里只呈现。

import SwiftUI

struct CalibrationRecordsSection: View {
    let records: [CalibrationRecord]
    let state: CalibrationRecordsState
    let onAdd: () -> Void
    let onRetry: () -> Void
    let onDismissSaveFailure: () -> Void
    let onDelete: (CalibrationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: L10n.Calibration.recordsTitle)

            if state != .ready {
                CalibrationRecordsStatusView(
                    state: state,
                    onRetry: onRetry,
                    onDismissSaveFailure: onDismissSaveFailure
                )
            }

            if records.isEmpty, state.canModify {
                CalibrationEmptyRecordState(onAdd: onAdd)
            } else if !records.isEmpty {
                InstrumentRowGroup {
                    ForEach(records) { record in
                        CalibrationRecordRow(
                            record: record,
                            isDeleteEnabled: state.canModify,
                            onDelete: { onDelete(record) }
                        )
                        if record.id != records.last?.id {
                            DividerLine()
                        }
                    }
                }
            }
        }
    }
}

private struct CalibrationEmptyRecordState: View {
    let onAdd: () -> Void

    var body: some View {
        InstrumentEmptyState(
            systemImage: "plus",
            title: L10n.Calibration.emptyRecordsTitle,
            message: L10n.Calibration.emptyRecordsMessage
        ) {
            Button(action: onAdd) {
                Label(L10n.Calibration.addRecord, systemImage: "plus")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .padding(.top, 4)
        }
    }
}

private struct CalibrationRecordsStatusView: View {
    let state: CalibrationRecordsState
    let onRetry: () -> Void
    let onDismissSaveFailure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusContent

            switch state {
            case .loadFailed:
                Button(action: onRetry) {
                    Label(L10n.Calibration.retry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(WorkspaceSecondaryButtonStyle(tint: Design.Colors.Workspace.information))
                .accessibilityHint(L10n.Calibration.retryHint)
                .accessibilityIdentifier("calibration.retryLoad")

            case .saveFailed:
                Button(action: onDismissSaveFailure) {
                    Text(L10n.Calibration.dismiss)
                }
                .buttonStyle(WorkspaceQuietButtonStyle(tint: Design.Colors.Workspace.information))
                .frame(maxWidth: .infinity, alignment: .trailing)

            case .loading, .ready, .saving:
                EmptyView()
            }
        }
        .padding(12)
        .background(
            statusTint.opacity(0.08),
            in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(statusTint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier("calibration.recordsStatus")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .loading:
            statusRow(
                icon: "arrow.triangle.2.circlepath",
                title: L10n.Calibration.loadingRecords,
                message: nil,
                showsProgress: true
            )
        case .saving(.add):
            statusRow(
                icon: "square.and.arrow.down",
                title: L10n.Calibration.savingAddedRecord,
                message: nil,
                showsProgress: true
            )
        case .saving(.delete):
            statusRow(
                icon: "trash",
                title: L10n.Calibration.savingDeletedRecord,
                message: nil,
                showsProgress: true
            )
        case .loadFailed:
            statusRow(
                icon: "exclamationmark.triangle.fill",
                title: L10n.Calibration.loadFailedTitle,
                message: L10n.Calibration.loadFailedMessage,
                showsProgress: false
            )
        case .saveFailed(.add):
            statusRow(
                icon: "exclamationmark.triangle.fill",
                title: L10n.Calibration.saveFailedTitle,
                message: L10n.Calibration.addSaveFailedMessage,
                showsProgress: false
            )
        case .saveFailed(.delete):
            statusRow(
                icon: "exclamationmark.triangle.fill",
                title: L10n.Calibration.saveFailedTitle,
                message: L10n.Calibration.deleteSaveFailedMessage,
                showsProgress: false
            )
        case .ready:
            EmptyView()
        }
    }

    private var statusTint: Color {
        switch state {
        case .loadFailed, .saveFailed:
            return Design.Colors.Workspace.failure
        case .loading, .ready, .saving:
            return Design.Colors.Workspace.information
        }
    }

    private func statusRow(
        icon: String,
        title: String,
        message: String?,
        showsProgress: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if showsProgress {
                    ProgressView()
                        .tint(statusTint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(statusTint)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
