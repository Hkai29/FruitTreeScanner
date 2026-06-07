import SwiftUI

struct PlotListView: View {
    let plots: [Plot]
    let treeCount: (UUID) -> Int
    let onEdit: (Plot) -> Void
    let onDelete: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        List {
            ForEach(plots) { plot in
                PlotRowView(
                    plot: plot,
                    treeCount: treeCount(plot.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onEdit(plot)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    onDelete(plots[index].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if plots.isEmpty {
                TagManagementEmptyState(
                    icon: "map",
                    imageName: "FeatureTagManagement",
                    title: "暂无地块",
                    message: "添加地块后，可把果树扫描记录归到具体区域。",
                    primaryAction: DashboardSheetAction(title: "添加地块", icon: "plus", action: onAdd)
                )
            }
        }
    }
}

struct PlotRowView: View {
    let plot: Plot
    let treeCount: Int

    var body: some View {
        TagManagementRow(
            colorHex: plot.colorHex,
            title: plot.name,
            detail: "\(treeCount) 棵树"
        )
    }
}

struct TagListView: View {
    let tags: [GroupTag]
    let treeCount: (UUID) -> Int
    let onEdit: (GroupTag) -> Void
    let onDelete: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        List {
            ForEach(tags) { tag in
                TagRowView(
                    tag: tag,
                    treeCount: treeCount(tag.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onEdit(tag)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    onDelete(tags[index].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if tags.isEmpty {
                TagManagementEmptyState(
                    icon: "tag",
                    imageName: "FeatureTagManagement",
                    title: "暂无标签",
                    message: "标签用于标记试验组、品种批次或管理状态。",
                    primaryAction: DashboardSheetAction(title: "添加标签", icon: "plus", action: onAdd)
                )
            }
        }
    }
}

struct TagRowView: View {
    let tag: GroupTag
    let treeCount: Int

    var body: some View {
        TagManagementRow(
            colorHex: tag.colorHex,
            title: tag.name,
            detail: "\(treeCount) 棵树"
        )
    }
}

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
                    title: "暂无树体状态",
                    message: "开始扫描并选择地块或标签后，这里会汇总待扫描、复核中和已完成的树体数量。",
                    primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan)
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
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("\(count) 棵树")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 7)
        .listRowBackground(Design.Colors.Dark.bgDeep)
    }
}

private struct TagManagementRow: View {
    let colorHex: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: colorHex))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.vertical, 7)
        .listRowBackground(Design.Colors.Dark.bgDeep)
    }
}

struct TagManagementEmptyState: View {
    let icon: String
    var imageName: String? = nil
    let title: String
    let message: String
    var primaryAction: DashboardSheetAction? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: icon,
                imageName: imageName,
                title: title,
                message: message,
                accent: Design.Colors.harvest,
                primaryAction: primaryAction,
                outerPadding: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
    }
}
