import SwiftUI

struct BatchExportCompletionPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let url: URL
    let onShare: () -> Void
    let onClear: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    completionText
                    VStack(spacing: Design.Space.xs) {
                        actionButtons(fillWidth: true)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: Design.Space.sm) {
                    completionIcon

                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        completionText

                        HStack(spacing: Design.Space.sm) {
                            actionButtons(fillWidth: false)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var completionIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.headline)
            .foregroundColor(Design.Colors.forest)
            .frame(width: 30, height: 30)
            .background(Design.Colors.forest.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var completionText: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(L10n.Export.completionTitle)
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(url.lastPathComponent)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(L10n.Export.completionFileName(url.lastPathComponent))
        }
    }

    @ViewBuilder
    private func actionButtons(fillWidth: Bool) -> some View {
        completionButton(
            title: L10n.Export.completionShare,
            hint: L10n.Export.completionShareHint,
            icon: "square.and.arrow.up",
            accessibilityIdentifier: "batchExport.completion.share",
            fillWidth: fillWidth,
            action: onShare
        )

        completionButton(
            title: L10n.Export.completionDismiss,
            hint: L10n.Export.completionDismissHint,
            icon: "xmark",
            accessibilityIdentifier: "batchExport.completion.dismiss",
            fillWidth: fillWidth,
            action: onClear
        )
    }

    private func completionButton(
        title: String,
        hint: String,
        icon: String,
        accessibilityIdentifier: String,
        fillWidth: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: Design.Touch.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(Design.Colors.harvest)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
