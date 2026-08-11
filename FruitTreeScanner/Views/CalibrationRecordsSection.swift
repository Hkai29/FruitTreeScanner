import SwiftUI

struct CalibrationRecordsSection: View {
    let records: [CalibrationRecord]
    let onAdd: () -> Void
    let onDelete: (CalibrationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text(L10n.CalibrationWorkspace.recordsTitle)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()

            if records.isEmpty {
                CalibrationEmptyRecordState(onAdd: onAdd)
            } else {
                ForEach(records) { record in
                    CalibrationRecordRow(
                        record: record,
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
            title: L10n.CalibrationWorkspace.recordsEmptyTitle,
            message: L10n.CalibrationWorkspace.recordsEmptyMessage,
            accent: Design.Colors.Dark.info,
            primaryAction: DashboardSheetAction(
                title: L10n.CalibrationWorkspace.addRecord,
                icon: "plus",
                action: onAdd
            ),
            outerPadding: false
        )
    }
}
