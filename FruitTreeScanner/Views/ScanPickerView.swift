import SwiftUI

struct ScanPickerView: View {
    let scans: [ScanItem]
    @Binding var selectedScan: ScanItem?
    let slot: String
    let presentation: HistoricalComparePresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: Design.Space.md) {
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
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle(presentation.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(presentation.cancel, action: dismiss.callAsFunction)
                }
            }
        }
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
                        icon
                        scanInfo
                    }
                    selectedIndicator
                }
            } else {
                HStack(spacing: Design.Space.md) {
                    icon
                    scanInfo
                    Spacer()
                    selectedIndicator
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
        .overlay(border)
        .shadow(
            color: Design.Shadow.subtle.color,
            radius: Design.Shadow.subtle.radius,
            y: Design.Shadow.subtle.y
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.treeTitle(scan.treeID)))
        .accessibilityValue(
            Text(presentation.pickerValue(scan: scan, isSelected: isSelected, locale: locale))
        )
        .accessibilityHint(Text(presentation.pickerSelectionHint(slot: slot)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Design.Colors.Dark.glow.opacity(0.12) : Design.Colors.Dark.bgSurface)
                .frame(width: 44, height: 44)

            Image(systemName: "doc.text.fill")
                .font(.title3.weight(.medium))
                .foregroundColor(isSelected ? Design.Colors.Dark.glow : Design.Colors.Dark.textSecondary)
        }
        .accessibilityHidden(true)
    }

    private var scanInfo: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(presentation.treeTitle(scan.treeID))
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.dateText(scan.scanDate, locale: locale))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(presentation.yieldText(scan.yieldKg, locale: locale))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.glow)
        }
    }

    @ViewBuilder
    private var selectedIndicator: some View {
        if isSelected {
            Label(presentation.pickerState(isSelected: true), systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.glow)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Design.Radius.large)
            .stroke(isSelected ? Design.Colors.Dark.glow : Color.clear, lineWidth: 2)
    }
}
