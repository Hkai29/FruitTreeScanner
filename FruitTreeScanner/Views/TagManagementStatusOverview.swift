import SwiftUI

struct StatusOverviewView: View {
    private let assignmentCount: Int
    private let statusCounts: [ScanStatus: Int]
    private let onStartScan: (() -> Void)?

    init(assignments: [TreeAssignment], onStartScan: (() -> Void)? = nil) {
        assignmentCount = assignments.count
        self.onStartScan = onStartScan
        var counts = Dictionary(uniqueKeysWithValues: ScanStatus.allCases.map { ($0, 0) })
        for assignment in assignments {
            counts[assignment.status, default: 0] += 1
        }
        statusCounts = counts
    }

    var body: some View {
        List {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                StatusRowView(
                    status: status,
                    count: statusCounts[status, default: 0]
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if assignmentCount == 0 {
                TagManagementEmptyState(
                    icon: "checklist",
                    imageName: "FeatureTagManagement",
                    title: L10n.TagManagement.statusEmptyTitle,
                    message: L10n.TagManagement.statusEmptyMessage,
                    primaryAction: action(
                        title: L10n.TagManagement.startScan,
                        icon: "viewfinder",
                        handler: onStartScan
                    )
                )
            }
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct StatusRowView: View {
    let status: ScanStatus
    let count: Int

    private var icon: String {
        switch status {
        case .notScanned: return "circle"
        case .scanned: return "checkmark.circle"
        case .reviewing: return "arrow.clockwise.circle"
        case .completed: return "checkmark.seal.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .notScanned: return Design.Colors.Dark.textSecondary
        case .scanned: return Design.Colors.Dark.info
        case .reviewing: return Design.Colors.harvest
        case .completed: return Design.Colors.Dark.success
        }
    }

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.headline.weight(.medium))
                .foregroundColor(iconColor)
                .frame(minWidth: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.TagManagement.statusName(for: status))
                    .font(.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(L10n.TagManagement.treeCount(count))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 7)
        .listRowBackground(Design.Colors.Dark.bgDeep)
        .accessibilityElement(children: .combine)
    }
}
