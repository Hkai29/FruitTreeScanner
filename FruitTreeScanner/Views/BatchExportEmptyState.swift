// BatchExportEmptyState.swift
// 没有可导出记录时的空状态：说明原因并给出真实入口。

import SwiftUI

struct BatchExportEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            InstrumentEmptyState(
                systemImage: "tray",
                title: L10n.Export.emptyTitle,
                message: emptyMessageText
            ) {
                actions
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessageText: String {
        dynamicTypeSize.isAccessibilitySize
            ? L10n.Export.emptyCompactMessage
            : L10n.Export.emptyMessage
    }

    @ViewBuilder
    private var actions: some View {
        if onStartScan != nil || onImportFile != nil {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    actionButtons
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 10) {
                    actionButtons
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let onStartScan {
            actionButton(
                title: L10n.Export.startScan,
                hint: L10n.Export.startScanHint,
                icon: "viewfinder",
                accessibilityIdentifier: "batchExport.empty.startScan",
                isPrimary: true,
                action: onStartScan
            )
        }

        if let onImportFile {
            actionButton(
                title: L10n.Export.importPLY,
                hint: L10n.Export.importPLYHint,
                icon: "square.and.arrow.down",
                accessibilityIdentifier: "batchExport.empty.importPLY",
                isPrimary: false,
                action: onImportFile
            )
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        hint: String,
        icon: String,
        accessibilityIdentifier: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isPrimary {
            primaryActionButton(
                title: title,
                hint: hint,
                icon: icon,
                accessibilityIdentifier: accessibilityIdentifier,
                action: action
            )
        } else {
            secondaryActionButton(
                title: title,
                hint: hint,
                icon: icon,
                accessibilityIdentifier: accessibilityIdentifier,
                action: action
            )
        }
    }

    private func primaryActionButton(
        title: String,
        hint: String,
        icon: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(WorkspacePrimaryButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func secondaryActionButton(
        title: String,
        hint: String,
        icon: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(WorkspaceSecondaryButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
