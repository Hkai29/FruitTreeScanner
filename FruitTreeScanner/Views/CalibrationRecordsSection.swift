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

                Text("校准记录")
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
            title: "暂无校准记录",
            message: "添加人工计数或实际重量后，这里会显示误差对比。",
            accent: Design.Colors.Dark.info,
            primaryAction: DashboardSheetAction(
                title: "添加记录",
                icon: "plus",
                action: onAdd
            ),
            outerPadding: false
        )
    }
}
