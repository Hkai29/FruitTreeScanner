import SwiftUI

struct ImportFileContentView: View {
    let status: ImportStatus
    let isProcessing: Bool
    let onImportTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ImportHeader()
                ImportStatusView(status: status)
                importButton
                ImportRulesList()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(Design.Space.lg)
        }
    }

    private var importButton: some View {
        let title = status.isSuccess ? L10n.Import.continueButton : L10n.Import.selectButton

        return Button(action: onImportTap) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(Design.Colors.Dark.bgDeep)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(L10n.Import.selectButtonHint)
        .accessibilityIdentifier("import.selectFile")
    }
}
