import SwiftUI

struct ScanPickerView: View {
    let scans: [ScanItem]
    @Binding var selectedScan: ScanItem?
    let slot: String
    let presentation: HistoricalComparePresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(scans) { scan in
                    Button {
                        select(scan)
                    } label: {
                        ScanPickerRow(
                            scan: scan,
                            isSelected: selectedScan?.id == scan.id,
                            slot: slot
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.Workspace.surface)
            .navigationTitle(presentation.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(presentation.cancel, action: dismiss.callAsFunction)
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.historicalComparePresentation, presentation)
    }

    private func select(_ scan: ScanItem) {
        selectedScan = scan
        dismiss()
    }
}

struct ScanPickerRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.historicalComparePresentation) private var presentation
    let scan: ScanItem
    let isSelected: Bool
    let slot: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    HStack(alignment: .top, spacing: Design.Space.sm) {
                        scanInfo
                    }
                    selectedIndicator
                }
            } else {
                HStack(spacing: Design.Space.md) {
                    scanInfo
                    Spacer()
                    selectedIndicator
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.treeTitle(scan.treeID)))
        .accessibilityValue(
            Text("\(presentation.pickerValue(scan: scan, isSelected: isSelected, locale: locale)), \(scan.scanDate.formatted(date: .omitted, time: .shortened))")
        )
        .accessibilityHint(Text(presentation.pickerSelectionHint(slot: slot)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var scanInfo: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(presentation.treeTitle(scan.treeID))
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(presentation.dateText(scan.scanDate, locale: locale)) \(scan.scanDate.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)

            Text(presentation.yieldText(scan.yieldKg, locale: locale))
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.accent)
        }
    }

    @ViewBuilder
    private var selectedIndicator: some View {
        if isSelected {
            Label(presentation.pickerState(isSelected: true), systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.accent)
        }
    }

}
