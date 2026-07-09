import SwiftUI

struct BatchExportFormatButton: View {
    let format: BatchExportService.ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: format.icon)
                Text(format.rawValue)
            }
            .font(Design.Typography.subheadline)
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgDeep)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("batchExport.format.\(format.accessibilityIdentifier)")
    }
}

struct BatchExportOptionToggle: View {
    let label: String
    let accessibilityIdentifier: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isOn ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("batchExport.option.\(accessibilityIdentifier)")
    }
}

struct BatchExportPrimaryButton: View {
    let selectedCount: Int
    let isExporting: Bool
    let hasCompletedExport: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(selectedCount == 0 && !isExporting ? Color.gray : Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isExporting ? "batchExport.cancel" : "batchExport.export")
    }

    private var buttonTitle: String {
        if isExporting { return "取消导出" }
        if hasCompletedExport { return "重新导出 \(selectedCount) 条记录" }
        return "导出 \(selectedCount) 条记录"
    }
}

private extension BatchExportService.ExportFormat {
    var accessibilityIdentifier: String {
        switch self {
        case .csv: return "csv"
        case .excel: return "excel"
        case .json: return "json"
        }
    }
}
