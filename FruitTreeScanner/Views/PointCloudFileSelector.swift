import SwiftUI

struct PointCloudFileSelector: View {
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
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Design.Colors.Dark.bgDeep)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            TextField(L10n.PointCloud.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
                .accessibilityLabel(L10n.PointCloud.clearSearchAccessibility)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
                    .font(.system(size: 11, weight: .semibold))
                Text(record.treeID)
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: "%.1fkg", record.yieldKg))
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.72)
            }
            .foregroundColor(isSelected ? Color.black.opacity(0.82) : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
    }
}
