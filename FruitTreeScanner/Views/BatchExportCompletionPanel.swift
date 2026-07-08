import SwiftUI

struct BatchExportCompletionPanel: View {
    let url: URL
    let onShare: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Design.Colors.forest)
                .frame(width: 30, height: 30)
                .background(Design.Colors.forest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("导出完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Button(action: onShare) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }

                    Button(action: onClear) {
                        Label("收起", systemImage: "xmark")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}
