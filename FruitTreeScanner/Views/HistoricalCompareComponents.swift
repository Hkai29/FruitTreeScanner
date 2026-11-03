import SwiftUI

/// 对比页空状态。
struct HistoricalCompareEmptyState: View {
    @Environment(\.locale) private var locale
    @Environment(\.historicalComparePresentation) private var presentation
    let scanCount: Int
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        DashboardSheetEmptyState(
            icon: "arrow.left.arrow.right",
            title: presentation.emptyTitle,
            message: presentation.emptyMessage(scanCount: scanCount, locale: locale),
            accent: Design.Colors.Workspace.accent,
            primaryAction: action(
                title: presentation.startScan,
                icon: "viewfinder",
                handler: onStartScan
            ),
            outerPadding: false
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

/// 还没有选中两条记录时的提示。
///
/// 用测区空板承载：等待选择的状态也是设计的一部分，
/// 不应该只是页面中间飘着一条小提示、下面留一片空白。
struct HistoricalComparePrompt: View {
    @Environment(\.historicalComparePresentation) private var presentation

    var body: some View {
        InstrumentSurveyPlate(gridHeight: 190) {
            InstrumentNotice(
                message: presentation.prompt,
                tone: .neutral,
                systemImage: "hand.tap"
            )
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.md)
        }
    }
}

/// 槽位选择卡：扫描 A / 扫描 B。
///
/// 选中时给出结构标记（证据等级竖线）与实心描边，不只靠颜色。
struct ScanSelectionCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.historicalComparePresentation) private var presentation
    let scan: ScanItem?
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .instrumentLabel()

                if let scan {
                    selectedContent(scan)
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: Design.Touch.minimumHeight)
            .background(
                Design.Colors.Workspace.surface,
                in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(
                        scan != nil ? Design.Colors.Workspace.accent : Design.Colors.Workspace.line,
                        lineWidth: scan != nil ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(presentation.selectionValue(scan: scan, locale: locale)))
        .accessibilityHint(Text(presentation.selectionHint(slot: label)))
    }

    private func selectedContent(_ scan: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                InstrumentTierMark(
                    style: scan.evidenceTier.markStyle,
                    tint: scan.evidenceTier.tint,
                    height: 22
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.treeTitle(scan.treeID))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.dateText(scan.scanDate, locale: locale))
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // 与档案行一致：数值 + 单位，不加会换行的标签。
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(presentation.yieldText(scan.yieldKg, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)
                // 计数标签本身已包含数字，直接使用完整本地化字符串。
                Text(L10n.Dashboard.fruitCountLabel(scan.archivedFruitCount))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.muted)
            }
        }
    }

    private var emptyContent: some View {
        Label(presentation.selectScan, systemImage: "plus")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Design.Colors.Workspace.secondary)
            .frame(minHeight: Design.Touch.minimumHeight)
    }
}

/// 产量变化：两个真实读数 + 真实差值 + 证据等级。
///
/// 差异不只用颜色表达：等级用线的样式编码，数值是真实差值。
struct HistoricalYieldComparisonCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.historicalComparePresentation) private var presentation
    let scan1: ScanItem
    let scan2: ScanItem
    let proportionalChange: Double?

    private var trend: TrendDirection {
        HistoricalCompareMetrics.trend(for: proportionalChange)
    }

    var body: some View {
        InstrumentPanel(label: presentation.yieldChange, systemImage: "scalemass") {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        scanValue(scan1, slot: presentation.scanA, alignment: .leading)
                        changeIndicator
                        scanValue(scan2, slot: presentation.scanB, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        scanValue(scan1, slot: presentation.scanA, alignment: .leading)
                        Spacer(minLength: 0)
                        changeIndicator
                        Spacer(minLength: 0)
                        scanValue(scan2, slot: presentation.scanB, alignment: .trailing)
                    }
                }

                DividerLine()

                ComparisonEvidenceRow(scan1: scan1, scan2: scan2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.yieldChange))
        .accessibilityValue(
            Text(
                presentation.yieldComparisonValue(
                    scan1: scan1,
                    scan2: scan2,
                    proportionalChange: proportionalChange,
                    locale: locale
                )
            )
        )
    }

    private func scanValue(
        _ scan: ScanItem,
        slot: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(slot)
                .instrumentLabel()
            Text(presentation.yieldText(scan.yieldKg, locale: locale))
                .font(.system(.title3, design: .default).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.treeTitle(scan.treeID))
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private var changeIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: trend.icon)
                    .font(.subheadline.weight(.bold))
                    .accessibilityHidden(true)
                Text(
                    presentation.yieldDeltaText(
                        from: scan1.yieldKg,
                        to: scan2.yieldKg,
                        locale: locale
                    )
                )
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            }
            .foregroundColor(trend.color)

            Text(presentation.percentageText(proportionalChange, locale: locale))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 两条对比记录的证据等级。
///
/// 等级用 `InstrumentTierMark` 的线型编码，需要复核时同时给出文字，
/// 因此不依赖颜色也能读出"这条差异能不能直接用"。
struct ComparisonEvidenceRow: View {
    @Environment(\.historicalComparePresentation) private var presentation
    let scan1: ScanItem
    let scan2: ScanItem

    private var needsReview: Bool {
        scan1.evidenceTier != .complete || scan2.evidenceTier != .complete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.evidenceTierTitle)
                .instrumentLabel()

            HStack(spacing: 10) {
                tierItem(scan1, slot: presentation.scanA)
                Spacer(minLength: 8)
                tierItem(scan2, slot: presentation.scanB)
            }

            if needsReview {
                Text(WorkspaceText.review)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tierItem(_ scan: ScanItem, slot: String) -> some View {
        HStack(spacing: 6) {
            InstrumentTierMark(
                style: scan.evidenceTier.markStyle,
                tint: scan.evidenceTier.tint,
                height: 14
            )
            Text(slot)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)
            Text(presentation.treeTitle(scan.treeID))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// 单项指标对比：A / B 两个真实读数 + 方向。
struct StatCompareCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.historicalComparePresentation) private var presentation
    let title: String
    let value1: String
    let value2: String
    let icon: String
    let trend: TrendDirection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .instrumentLabel()
                Spacer(minLength: 8)
                if let trend {
                    trendIndicator(trend)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    CompareValueColumn(slot: presentation.scanA, value: value1, alignment: .leading)
                    CompareValueColumn(slot: presentation.scanB, value: value2, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    valueRow(slot: presentation.scanA, value: value1)
                    valueRow(slot: presentation.scanB, value: value2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(presentation.comparisonValue(value1: value1, value2: value2, trend: trend)))
    }

    private func valueRow(slot: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(slot)
                    .font(.caption2)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
            }
            CompareValueColumn(slot: slot, value: value, alignment: .leading)
        }
    }

    private func trendIndicator(_ trend: TrendDirection) -> some View {
        Label(presentation.trendText(trend), systemImage: trend.icon)
            .labelStyle(.iconOnly)
            .font(.caption.weight(.bold))
            .foregroundColor(trend.color)
            .accessibilityHidden(true)
    }
}

private struct CompareValueColumn: View {
    let slot: String
    let value: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(slot)
                .font(.caption2)
                .foregroundColor(Design.Colors.Workspace.muted)
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
