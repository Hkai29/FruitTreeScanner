import SwiftUI

struct ScanPickerView: View {
    let scans: [ScanItem]
    @Binding var selectedScan: ScanItem?
    @Environment(\.dismiss) var dismiss

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
                                ScanPickerRow(scan: scan, isSelected: selectedScan?.id == scan.id)
                            }
                        }
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("选择扫描")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func select(_ scan: ScanItem) {
        selectedScan = scan
        dismiss()
    }
}

struct ScanPickerRow: View {
    let scan: ScanItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Design.Space.md) {
            icon
            scanInfo
            Spacer()
            selectedIndicator
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
        .overlay(border)
        .shadow(color: Design.Shadow.subtle.color, radius: Design.Shadow.subtle.radius, y: Design.Shadow.subtle.y)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Design.Colors.Dark.glow.opacity(0.12) : Design.Colors.Dark.bgSurface)
                .frame(width: 44, height: 44)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? Design.Colors.Dark.glow : Design.Colors.Dark.textSecondary)
        }
    }

    private var scanInfo: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text("树 #\(scan.treeID)")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            HStack(spacing: Design.Space.md) {
                Text(scan.dateFormatted)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text(scan.yieldFormatted)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.glow)
            }
        }
    }

    @ViewBuilder
    private var selectedIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Design.Colors.Dark.glow)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Design.Radius.large)
            .stroke(isSelected ? Design.Colors.Dark.glow : Color.clear, lineWidth: 2)
    }
}
