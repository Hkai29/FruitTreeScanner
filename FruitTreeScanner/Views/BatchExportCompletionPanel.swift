// BatchExportCompletionPanel.swift
// 导出完成面板：真实输出文件与真实输出位置，以及分享 / 收起动作。

import SwiftUI

struct BatchExportCompletionPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let url: URL
    let onShare: () -> Void
    let onClear: () -> Void

    var body: some View {
        InstrumentPanel(
            label: L10n.Export.completionTitle,
            systemImage: "checkmark.circle.fill",
            tone: .accent
        ) {
            VStack(alignment: .leading, spacing: 12) {
                fileName
                outputLocation
                actions
            }
        }
    }

    private var fileName: some View {
        Text(url.lastPathComponent)
            .font(.system(.subheadline, design: .monospaced).weight(.medium))
            .foregroundColor(Design.Colors.Workspace.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.Export.completionFileName(url.lastPathComponent))
    }

    private var outputLocation: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BatchExportStrings.outputLocation)
                .instrumentLabel()
            Text(directoryPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var directoryPath: String {
        url.deletingLastPathComponent().path
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                actionButtons(fillWidth: true)
            }
        } else {
            HStack(spacing: 10) {
                actionButtons(fillWidth: false)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(fillWidth: Bool) -> some View {
        Button(action: onShare) {
            Label(L10n.Export.completionShare, systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.accent)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: Design.Touch.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Export.completionShare)
        .accessibilityHint(L10n.Export.completionShareHint)
        .accessibilityIdentifier("batchExport.completion.share")

        Button(action: onClear) {
            Label(L10n.Export.completionDismiss, systemImage: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: Design.Touch.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Export.completionDismiss)
        .accessibilityHint(L10n.Export.completionDismissHint)
        .accessibilityIdentifier("batchExport.completion.dismiss")
    }
}
