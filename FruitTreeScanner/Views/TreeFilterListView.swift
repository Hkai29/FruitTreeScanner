// TreeFilterListView.swift
// 筛选后的果树档案行：树号、地块、标签、状态与最近一次扫描的读数。
//
// 行内只放库里真实存在的数据：地块名与颜色、标签名与颜色、状态，
// 以及该树最近一次扫描的产量与果实数（结果不完整时只标"不可用"）。

import SwiftUI

struct TreeFilterListView: View {
    let assignments: [TreeAssignment]
    @ObservedObject var tagStore: TagStore
    let latestScan: (String) -> ScanFileRecord?
    @Environment(\.locale) private var locale
    @Environment(\.orchardMapPresentation) private var presentation

    var body: some View {
        Group {
            if assignments.isEmpty {
                TreeFilterEmptyState()
            } else {
                List {
                    Section {
                        listHeader
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 6, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(assignments) { assignment in
                            TreeRowView(
                                assignment: assignment,
                                plot: assignment.plotId.flatMap { tagStore.getPlot(id: $0) },
                                tags: tagStore.tags.filter { assignment.tagIds.contains($0.id) },
                                latestScan: latestScan(assignment.treeId)
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowSeparatorTint(Design.Colors.Workspace.lineSoft)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .instrumentListStyle()
                .frame(maxWidth: 1080)
            }
        }
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(presentation.orchardTrees)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(presentation.summaryTreeCountText(assignments.count, locale: locale))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.muted)
        }
    }
}

private struct TreeFilterEmptyState: View {
    var body: some View {
        ScrollView {
            InstrumentEmptyState(
                systemImage: "leaf",
                title: TreeFilterText.emptyTitle,
                message: TreeFilterText.emptyMessage
            )
            .padding(Design.Space.lg)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 状态标记：琥珀只表示"待复核"，其余状态用中性色，不做彩色胶囊。
struct StatusBadge: View {
    let status: ScanStatus

    private var tint: Color {
        switch status {
        case .notScanned: return Design.Colors.Workspace.muted
        case .scanned: return Design.Colors.Workspace.information
        case .reviewing: return Design.Colors.Workspace.attention
        case .completed: return Design.Colors.Workspace.ink
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(L10n.History.statusName(for: status))
                .font(.caption.weight(.medium))
                .foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.History.statusName(for: status))
    }
}

/// 标签标记：方角 + 发丝线，色点保留标签库里真实的颜色。
struct TagBadge: View {
    let tag: GroupTag

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(tag.name)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Design.Colors.Workspace.surfaceQuiet,
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

/// 一棵树的档案行。
struct TreeRowView: View {
    let assignment: TreeAssignment
    let plot: Plot?
    let tags: [GroupTag]
    let latestScan: ScanFileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            plotRow
            if !tags.isEmpty {
                tagRow
            }
            evidenceRow
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            InstrumentIdentifier(text: assignment.treeId)
            Spacer(minLength: 8)
            StatusBadge(status: assignment.status)
        }
    }

    @ViewBuilder
    private var plotRow: some View {
        if let plot {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: plot.colorHex))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(plot.name)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(TreeFilterText.unassigned)
                .font(.footnote)
                .foregroundColor(Design.Colors.Workspace.muted)
        }
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(3)) { tag in
                TagBadge(tag: tag)
            }

            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
            }
        }
    }

    @ViewBuilder
    private var evidenceRow: some View {
        if let latestScan {
            let scanPresentation = ScanHistoryRecordPresentation(record: latestScan)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if scanPresentation.hasReliableResult {
                    if let yieldKg = scanPresentation.yieldKg {
                        InstrumentInlineDatum(
                            label: L10n.Dashboard.yield,
                            value: L10n.History.yieldKilograms(yieldKg)
                        )
                    }
                    if let fruitCount = scanPresentation.fruitCount {
                        Text(L10n.Dashboard.fruitCountLabel(fruitCount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(Design.Colors.Workspace.secondary)
                    }
                } else {
                    Text(TreeFilterText.metricsUnavailable)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.attention)
                }

                Spacer(minLength: 8)

                Text(latestScan.scanDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .lineLimit(1)
            }
        }
    }
}
