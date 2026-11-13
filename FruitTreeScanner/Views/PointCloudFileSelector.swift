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
        List {
            ForEach(filteredFiles) { record in
                let presentation = ScanHistoryRecordPresentation(record: record)
                Button { onSelect(record.fileURL) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(record.treeID)
                                .font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if selectedFile == record.fileURL {
                                Image(systemName: "checkmark").foregroundColor(Design.Colors.Workspace.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text(record.scanDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundColor(Design.Colors.Workspace.secondary)
                        HStack {
                            Text(presentation.statusTitle)
                            Spacer(minLength: 8)
                            if let yield = presentation.yieldKg {
                                Text(L10n.History.yieldKilograms(yield)).monospacedDigit()
                            }
                        }
                        .font(.caption).foregroundColor(Design.Colors.Workspace.secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(Design.Colors.Workspace.ink)
                .accessibilityLabel(record.treeID)
                .accessibilityValue("\(record.scanDate.formatted(date: .abbreviated, time: .shortened)), \(presentation.accessibilityValue)")
                .accessibilityAddTraits(selectedFile == record.fileURL ? .isSelected : [])
            }
            if filteredFiles.isEmpty {
                Text(searchText.isEmpty ? L10n.PointCloud.emptyTitle : L10n.PointCloud.noSearchResults(for: searchText))
                    .font(.subheadline).foregroundColor(Design.Colors.Workspace.secondary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: L10n.PointCloud.searchPlaceholder)
        .scrollContentBackground(.hidden)
        .workspacePage(background: Design.Colors.Workspace.surface)
    }
}
