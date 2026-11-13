// TagManagementStatusOverview.swift
// 树体状态总览：四个真实状态的计数条 + 明细行。
//
// 计数直接来自 TagStore 的分配记录，不做推算。

import SwiftUI

struct StatusOverviewView: View {
    private let assignmentCount: Int
    private let statusCounts: [ScanStatus: Int]
    private let onStartScan: (() -> Void)?

    private let contentWidth: CGFloat = 1080

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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                } else {
                    statusStrip
                    InstrumentRowGroup {
                        ForEach(Array(ScanStatus.allCases.enumerated()), id: \.element) { index, status in
                            StatusRowView(
                                status: status,
                                count: statusCounts[status, default: 0]
                            )
                            if index < ScanStatus.allCases.count - 1 {
                                DividerLine(inset: 0)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var statusStrip: some View {
        InstrumentStatStrip {
            HStack(spacing: 0) {
                ForEach(Array(ScanStatus.allCases.enumerated()), id: \.element) { index, status in
                    InstrumentDatum(
                        label: L10n.TagManagement.statusName(for: status),
                        value: "\(statusCounts[status, default: 0])",
                        unit: "棵"
                    )
                    if index < ScanStatus.allCases.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.Workspace.line)
                            .frame(width: 0.5, height: 34)
                            .accessibilityHidden(true)
                    }
                }
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(iconColor.opacity(0.10))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.TagManagement.statusName(for: status))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.TagManagement.treeCount(count))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 12)
        .frame(minHeight: Design.Touch.minimumHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

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
        case .notScanned: return Design.Colors.Workspace.secondary
        case .scanned: return Design.Colors.Workspace.information
        case .reviewing: return Design.Colors.Workspace.attention
        case .completed: return Design.Colors.Workspace.accent
        }
    }
}
