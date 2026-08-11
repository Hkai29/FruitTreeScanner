import SwiftUI

struct ImportFileContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.lg)
        }
    }

    private var importButton: some View {
        let title = status.isSuccess ? L10n.Import.continueButton : L10n.Import.selectButton

        return Button(action: onImportTap) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.headline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundColor(Design.Colors.Dark.bgDeep)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
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
