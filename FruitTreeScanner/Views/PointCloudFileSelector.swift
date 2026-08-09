import SwiftUI

struct PointCloudFileSelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let records: [ScanFileRecord]
    let selectedFile: URL?
    @Binding var searchText: String
    let onSelect: (URL) -> Void

    private var filteredFiles: [ScanFileRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.treeID.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if !filteredFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(filteredFiles) { record in
                            PointCloudFileSelectorChip(
                                record: record,
                                isSelected: selectedFile == record.fileURL,
                                onSelect: { onSelect(record.fileURL) }
                            )
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text(L10n.PointCloud.noSearchResults(for: searchText))
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Design.Colors.Dark.bgDeep)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .accessibilityHidden(true)
            }

            TextField(L10n.PointCloud.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L10n.PointCloud.clearSearchAccessibility)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(Design.Colors.Dark.bgElevated)
        .cornerRadius(9)
    }
}

private struct PointCloudFileSelectorChip: View {
    let record: ScanFileRecord
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "cube")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(record.treeID)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(L10n.History.yieldKilograms(record.yieldKg))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .opacity(0.72)
            }
            .foregroundColor(isSelected ? Color.black.opacity(0.82) : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
        .accessibilityLabel(record.treeID)
        .accessibilityValue(L10n.History.yieldKilograms(record.yieldKg))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
