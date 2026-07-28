import SwiftUI

struct BatchExportRecordRow: View {
    let record: ScanFileRecord
    let isExportable: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Design.Space.md) {
                Image(systemName: selectionIcon)
                    .font(.system(size: 22))
                    .foregroundColor(selectionColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.treeID)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    HStack(spacing: Design.Space.sm) {
                        Label("\(record.fruitCount)", systemImage: "leaf.fill")
                        Label(String(format: "%.1f kg", record.yieldKg), systemImage: "scalemass")
                        Text(record.fruitType)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                    if !isExportable {
                        Label(unavailableMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.warning)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(record.scanDate))
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    if record.gpsLat != 0 {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Design.Colors.forest)
                    }
                }
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isSelected ? Design.Colors.harvest : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(record.treeID)，\(record.fruitCount) 个果实，\(String(format: "%.1f", record.yieldKg)) 千克"
        )
        .accessibilityValue(accessibilityState)
        .accessibilityHint(isExportable ? "双击切换选择状态" : "")
        .accessibilityIdentifier("batchExport.record.\(record.id)")
    }

    private var unavailableMessage: String {
        switch record.persistenceState {
        case .complete:
            return ""
        case .incomplete:
            return "记录未完整保存，无法导出"
        case .invalid:
            return "记录数据无效，无法导出"
        }
    }

    private var accessibilityState: String {
        guard isExportable else { return unavailableMessage }
        return isSelected ? "已选择，可导出" : "未选择，可导出"
    }

    private var selectionIcon: String {
        if !isExportable { return "exclamationmark.circle.fill" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var selectionColor: Color {
        if !isExportable { return Design.Colors.warning }
        return isSelected ? Design.Colors.harvest : Design.Colors.Dark.textSecondary
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
