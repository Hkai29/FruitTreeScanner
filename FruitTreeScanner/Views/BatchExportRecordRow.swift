import SwiftUI

struct BatchExportRecordRow: View {
    let record: ScanFileRecord
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Design.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)

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
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
