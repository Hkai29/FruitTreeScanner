import SwiftUI

struct ImportFileContentView: View {
    let status: ImportStatus
    let isProcessing: Bool
    let onImportTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ImportHeader()
            ImportStatusView(status: status)
            importButton
            ImportRulesList()
            Spacer(minLength: 0)
        }
        .padding(Design.Space.lg)
    }

    private var importButton: some View {
        Button(action: onImportTap) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                Text(status.isSuccess ? "继续导入 PLY 文件" : "选择 PLY 文件")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Design.Colors.Dark.bgDeep)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1)
    }
}
