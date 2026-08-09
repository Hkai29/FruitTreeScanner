import SwiftUI

struct BatchExportEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                header
                actions
            }
            .padding(Design.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
            .padding(Design.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            headerText
        } else {
            HStack(alignment: .top, spacing: Design.Space.sm) {
                DashboardFeatureImage(name: "FeatureBatchExport", accent: Design.Colors.harvest)
                    .frame(width: 96, height: 76)
                    .accessibilityHidden(true)

                headerText
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(L10n.Export.emptyTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Label {
                    Text(L10n.Export.emptyTitle)
                        .font(.headline)
                } icon: {
                    Image(systemName: "tray")
                        .foregroundColor(Design.Colors.harvest)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Export.emptyTitle)
                .accessibilityAddTraits(.isHeader)
            }

            Text(emptyMessageText)
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(L10n.Export.emptyMessage)
        }
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
                VStack(spacing: Design.Space.sm) {
                    actionButtons
                }
            } else {
                HStack(spacing: Design.Space.sm) {
                    actionButtons
                }
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

    private func actionButton(
        title: String,
        hint: String,
        icon: String,
        accessibilityIdentifier: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.sm)
                .padding(.vertical, Design.Space.xs)
                .frame(maxWidth: .infinity, minHeight: Design.Touch.minimumHeight)
                .background(isPrimary ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
