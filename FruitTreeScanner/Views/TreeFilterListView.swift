// TreeFilterListView.swift
// Filtered tree rows and badges.

import SwiftUI

struct TreeFilterListView: View {
    let assignments: [TreeAssignment]
    @ObservedObject var tagStore: TagStore
    let latestScan: (String) -> ScanFileRecord?

    var body: some View {
        Group {
            if assignments.isEmpty {
                TreeFilterEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: Design.Space.sm) {
                        ForEach(assignments) { assignment in
                            TreeRowView(
                                assignment: assignment,
                                plot: assignment.plotId.flatMap { tagStore.getPlot(id: $0) },
                                tags: tagStore.tags.filter { assignment.tagIds.contains($0.id) },
                                latestScan: latestScan(assignment.treeId)
                            )
                        }
                    }
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                }
            }
        }
    }
}

private struct TreeFilterEmptyState: View {
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Design.Colors.forest)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.forest.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    Text("没有符合筛选的果树")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                Text("调整地块、标签或状态筛选后再查看。")
                    .font(.system(size: 13))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
            .padding(.horizontal, Design.Space.md)
            .padding(.top, Design.Space.md)

            Spacer()
        }
    }
}

struct StatusBadge: View {
    let status: ScanStatus

    private var backgroundColor: Color {
        switch status {
        case .notScanned: return Color(hex: "8E8E93")
        case .scanned: return Design.Colors.earth
        case .reviewing: return Design.Colors.harvest
        case .completed: return Design.Colors.forest
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(Design.Typography.captionMedium)
            .foregroundColor(.white)
            .padding(.horizontal, Design.Space.sm + 2)
            .padding(.vertical, Design.Space.xs + 1)
            .background(Capsule().fill(backgroundColor))
    }
}

struct TagBadge: View {
    let tag: GroupTag

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)

            Text(tag.name)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .padding(.horizontal, Design.Space.sm + 2)
        .padding(.vertical, Design.Space.xs + 1)
        .background(Capsule().fill(Design.Colors.Dark.bgElevated))
    }
}

struct TreeRowView: View {
    let assignment: TreeAssignment
    let plot: Plot?
    let tags: [GroupTag]
    let latestScan: ScanFileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            treeMetaRow

            Text(assignment.treeId)
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            if !tags.isEmpty {
                tagBadges
            }

            if let latestScan {
                latestScanRow(latestScan)
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Design.Colors.Dark.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        )
    }

    private var treeMetaRow: some View {
        HStack {
            if let plot {
                HStack(spacing: Design.Space.sm) {
                    Circle()
                        .fill(Color(hex: plot.colorHex))
                        .frame(width: 8, height: 8)

                    Text(plot.name)
                        .font(Design.Typography.subheadlineMedium)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }
            } else {
                Text("未分配")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            StatusBadge(status: assignment.status)
        }
    }

    private var tagBadges: some View {
        HStack(spacing: Design.Space.xs) {
            ForEach(tags.prefix(3)) { tag in
                TagBadge(tag: tag)
            }

            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .padding(.horizontal, Design.Space.sm)
                    .padding(.vertical, Design.Space.xs + 1)
                    .background(Capsule().fill(Design.Colors.Dark.bgElevated))
            }
        }
    }

    private func latestScanRow(_ scan: ScanFileRecord) -> some View {
        HStack(spacing: Design.Space.md) {
            Label(scan.fruitType, systemImage: "leaf.fill")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.forest)

            if scan.fruitCount > 0 {
                Label("\(scan.fruitCount) 个", systemImage: "number")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            Text(scanDateString(scan.scanDate))
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private func scanDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
