import SwiftUI

struct BatchExportRecordRow: View {
    let record: ScanFileRecord
    let isExportable: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onToggle) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout
                } else {
                    compactLayout
                }
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isSelected ? Design.Colors.harvest : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.BatchExport.recordAccessibilityLabel(
                treeID: record.treeID,
                fruitCount: record.fruitCount,
                yieldKg: record.yieldKg
            )
        )
        .accessibilityValue(accessibilityState)
        .accessibilityHint(isExportable ? L10n.BatchExport.toggleSelectionHint() : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("batchExport.record.\(record.id)")
    }

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: Design.Space.md) {
            selectionIndicator
            recordSummary
            Spacer(minLength: Design.Space.sm)
            scanMetadata
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(alignment: .top, spacing: Design.Space.md) {
                selectionIndicator
                recordTitle
            }

            measurementDetails

            if !isExportable {
                unavailableNotice
            }

            scanMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionIndicator: some View {
        Image(systemName: selectionIcon)
            .font(.title2)
            .foregroundColor(selectionColor)
            .accessibilityHidden(true)
    }

    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            recordTitle

            measurementDetails

            if !isExportable {
                unavailableNotice
            }
        }
    }

    private var recordTitle: some View {
        Text(record.treeID)
            .font(dynamicTypeSize.isAccessibilitySize ? .headline : .subheadline)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unavailableNotice: some View {
        Label(unavailableMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(Design.Colors.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var measurementDetails: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: Design.Space.sm))

        return layout {
            Label(
                L10n.BatchExport.fruitCountLabel(record.fruitCount),
                systemImage: "leaf.fill"
            )
            .fixedSize(horizontal: false, vertical: true)
            Label(
                L10n.BatchExport.yieldLabel(record.yieldKg),
                systemImage: "scalemass"
            )
            .fixedSize(horizontal: false, vertical: true)
            if !record.fruitType.isEmpty {
                Text(record.fruitType)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.footnote)
        .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    private var scanMetadata: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: Design.Space.xs))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))

        return layout {
            Text(formatDate(record.scanDate))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if record.gpsLat != 0 {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundColor(Design.Colors.forest)
                    .accessibilityHidden(true)
            }
        }
    }

    private var unavailableMessage: String {
        L10n.BatchExport.unavailableMessage(for: record.persistenceState)
    }

    private var accessibilityState: String {
        L10n.BatchExport.recordAccessibilityValue(
            isExportable: isExportable,
            isSelected: isSelected,
            persistenceState: record.persistenceState
        )
    }

    private var selectionIcon: String {
        if !isExportable { return "exclamationmark.circle.fill" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var selectionColor: Color {
        if !isExportable { return Design.Colors.warning }
        return isSelected ? Design.Colors.harvest : Design.Colors.Dark.textSecondary
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
