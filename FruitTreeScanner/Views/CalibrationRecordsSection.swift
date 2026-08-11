import SwiftUI

struct CalibrationRecordsSection: View {
    let records: [CalibrationRecord]
    let state: CalibrationRecordsState
    let onAdd: () -> Void
    let onRetry: () -> Void
    let onDismissSaveFailure: () -> Void
    let onDelete: (CalibrationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)
                    .accessibilityHidden(true)

                Text(L10n.Calibration.recordsTitle)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()
            }

            Divider()

            if state != .ready {
                CalibrationRecordsStatusView(
                    state: state,
                    onRetry: onRetry,
                    onDismissSaveFailure: onDismissSaveFailure
                )
            }

            if records.isEmpty, state.canModify {
                CalibrationEmptyRecordState(onAdd: onAdd)
            } else {
                ForEach(records) { record in
                    CalibrationRecordRow(
                        record: record,
                        isDeleteEnabled: state.canModify,
                        onDelete: { onDelete(record) }
                    )
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }
}

private struct CalibrationEmptyRecordState: View {
    let onAdd: () -> Void

    var body: some View {
        DashboardSheetEmptyState(
            icon: "plus",
            imageName: "FeatureCalibration",
            title: L10n.Calibration.emptyRecordsTitle,
            message: L10n.Calibration.emptyRecordsMessage,
            accent: Design.Colors.Dark.info,
            primaryAction: DashboardSheetAction(
                title: L10n.Calibration.addRecord,
                icon: "plus",
                action: onAdd
            ),
            outerPadding: false
        )
    }
}

private struct CalibrationRecordsStatusView: View {
    let state: CalibrationRecordsState
    let onRetry: () -> Void
    let onDismissSaveFailure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            statusContent

            switch state {
            case .loadFailed:
                Button(action: onRetry) {
                    Label(L10n.Calibration.retry, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Design.Colors.Dark.info)
                .accessibilityHint(L10n.Calibration.retryHint)
                .accessibilityIdentifier("calibration.retryLoad")

            case .saveFailed:
                Button(L10n.Calibration.dismiss, action: onDismissSaveFailure)
                    .buttonStyle(.bordered)
                    .tint(Design.Colors.Dark.info)
                    .frame(maxWidth: .infinity, alignment: .trailing)

            case .loading, .ready, .saving:
                EmptyView()
            }
        }
        .padding(Design.Space.md)
        .background(statusTint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium))
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
            return Design.Colors.Dark.error
        case .loading, .ready, .saving:
            return Design.Colors.Dark.info
        }
    }

    private func statusRow(
        icon: String,
        title: String,
        message: String?,
        showsProgress: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Design.Space.sm) {
            Group {
                if showsProgress {
                    ProgressView()
                        .tint(statusTint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(statusTint)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                if let message {
                    Text(message)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
