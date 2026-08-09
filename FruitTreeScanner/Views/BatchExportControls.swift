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
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .accessibilityHidden(true)
                }

                Text(buttonTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.xs)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(selectedCount == 0 && !isExporting ? Color.gray : Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(buttonTitle)
        .accessibilityHint(buttonHint)
        .accessibilityIdentifier(isExporting ? "batchExport.cancel" : "batchExport.export")
    }

    private var buttonTitle: String {
        if isExporting { return L10n.Export.primaryCancel }
        if hasCompletedExport {
            return L10n.Export.primaryReexportTitle(recordCount: selectedCount)
        }
        return L10n.Export.primaryExportTitle(recordCount: selectedCount)
    }

    private var buttonHint: String {
        if isExporting { return L10n.Export.primaryCancelHint }
        if hasCompletedExport { return L10n.Export.primaryReexportHint }
        return L10n.Export.primaryExportHint
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
