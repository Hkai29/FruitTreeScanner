import SwiftUI

/// 地图外壳的文案。
///
/// 这里只描述"关闭地图""清除筛选"这类操作，不描述任何产量结论。
struct OrchardMapChromePresentation: Equatable {
    let closeAccessibilityLabel: String
    let clearFilterAccessibilityLabel: String
    let treeCountText: String
    let highYieldLabel: String
    let mediumYieldLabel: String
    let lowYieldLabel: String

    init(treeCount: Int, bundle: Bundle = .main) {
        closeAccessibilityLabel = bundle.localizedString(
            forKey: "orchard_map.chrome.close_accessibility",
            value: "关闭果园地图",
            table: nil
        )
        clearFilterAccessibilityLabel = bundle.localizedString(
            forKey: "orchard_map.chrome.clear_filter_accessibility",
            value: "清除产量筛选",
            table: nil
        )
        let countKey = treeCount == 1
            ? "orchard_map.chrome.tree_count_one"
            : "orchard_map.chrome.tree_count_other"
        let countFormat = bundle.localizedString(
            forKey: countKey,
            value: "%d 棵果树",
            table: nil
        )
        let locale = bundle.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        treeCountText = String(format: countFormat, locale: locale, arguments: [treeCount])
        highYieldLabel = bundle.localizedString(
            forKey: "orchard_map.chrome.filter_high",
            value: "高产",
            table: nil
        )
        mediumYieldLabel = bundle.localizedString(
            forKey: "orchard_map.chrome.filter_medium",
            value: "中产",
            table: nil
        )
        lowYieldLabel = bundle.localizedString(
            forKey: "orchard_map.chrome.filter_low",
            value: "低产",
            table: nil
        )
    }

    func filterLabel(for level: YieldLevel) -> String {
        switch level {
        case .high: return highYieldLabel
        case .medium: return mediumYieldLabel
        case .low: return lowYieldLabel
        }
    }
}

enum OrchardMapLegendLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .stacked : .horizontal
    }
}

enum OrchardMapYieldFilterSelection {
    static func next(current: YieldLevel?, tapping level: YieldLevel) -> YieldLevel? {
        current == level ? nil : level
    }
}

// MARK: - 顶栏

/// 地图顶栏：关闭操作 + 标题。
///
/// 触达区域 44×44，浅色层级用发丝线而不是投影。
struct OrchardMapTopBar: View {
    @Environment(\.orchardMapPresentation) private var presentation
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .frame(width: Design.Touch.minimumHeight, height: Design.Touch.minimumHeight)
                    .contentShape(Rectangle())
                    .background(
                        Design.Colors.Workspace.surface,
                        in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(presentation.closeMap))
            .accessibilityHint(Text(presentation.closeMapHint))

            Spacer(minLength: 0)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - 读数条

/// 地图读数：已定位的树体数量，以及没有定位、因此不在地图上的记录数量。
///
/// 两个数字都必须出现：只画树不画数，用户无法判断地图是否完整。
struct OrchardMapCountReadout: View {
    @Environment(\.orchardMapPresentation) private var presentation
    let locatedTreeCount: Int
    let unlocatedRecordCount: Int

    var body: some View {
        InstrumentStatStrip {
            HStack(spacing: 0) {
                InstrumentDatum(
                    label: presentation.orchardTrees,
                    value: "\(locatedTreeCount)",
                    unit: L10n.Dashboard.treeCountUnit(locatedTreeCount)
                )
                Rectangle()
                    .fill(Design.Colors.Workspace.line)
                    .frame(width: 0.5, height: 34)
                    .accessibilityHidden(true)
                InstrumentDatum(
                    label: presentation.unlocatedRecordsTitle,
                    value: "\(unlocatedRecordCount)"
                )
            }
        }
    }
}

// MARK: - 回退路径

/// 无定位记录的说明与回退入口。
///
/// 没有坐标的记录不会出现在地图上，必须明确告诉用户它们去哪里找。
struct OrchardMapFallbackNotice: View {
    @Environment(\.locale) private var locale
    @Environment(\.orchardMapPresentation) private var presentation
    let unlocatedRecordCount: Int
    let onOpenArchive: (() -> Void)?

    var body: some View {
        InstrumentNotice(
            message: presentation.unlocatedFallbackMessage(
                count: unlocatedRecordCount,
                locale: locale
            ),
            tone: .attention,
            systemImage: "mappin.slash"
        ) {
            if let onOpenArchive {
                Button(action: onOpenArchive) {
                    HStack(spacing: 4) {
                        Text(presentation.archiveActionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .frame(minHeight: Design.Touch.minimumHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("orchard.map.openArchive")
            }
        }
    }
}

// MARK: - 底栏

/// 地图底栏：产量等级筛选 + 当前选中的树体读数。
struct OrchardMapBottomPanel: View {
    let selectedTree: TreeAnnotation?
    let filteredTrees: [TreeAnnotation]
    let locatedTrees: [TreeAnnotation]
    @Binding var filterYieldLevel: YieldLevel?
    let onClearSelection: () -> Void

    init(
        selectedTree: TreeAnnotation?,
        filteredTrees: [TreeAnnotation],
        locatedTrees: [TreeAnnotation],
        filterYieldLevel: Binding<YieldLevel?>,
        onClearSelection: @escaping () -> Void
    ) {
        self.selectedTree = selectedTree
        self.filteredTrees = filteredTrees
        self.locatedTrees = locatedTrees
        self._filterYieldLevel = filterYieldLevel
        self.onClearSelection = onClearSelection
    }

    var body: some View {
        VStack(spacing: Design.Space.md) {
            OrchardMapLegend(
                locatedTrees: locatedTrees,
                filteredTrees: filteredTrees,
                filterYieldLevel: $filterYieldLevel
            )

            if let selectedTree {
                TreeDetailCard(tree: selectedTree, onClose: onClearSelection)
            }
        }
    }
}

/// 产量等级筛选。既是图例也是筛选器：每片筛选片自带该等级的树体数量。
struct OrchardMapLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    let locatedTrees: [TreeAnnotation]
    let filteredTrees: [TreeAnnotation]
    @Binding var filterYieldLevel: YieldLevel?

    private var summary: TreeYieldSummary { TreeYieldSummary(trees: locatedTrees) }

    var body: some View {
        InstrumentPanel(
            label: presentation.yieldLevelTitle,
            systemImage: "leaf",
            fill: Design.Colors.Workspace.surface
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Design.Space.sm) {
                            legendItems
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Design.Space.sm) {
                                legendItems
                            }
                        }
                    }
                }

                // 当前可见数量与总数量，筛选后不会让人误以为树变少了。
                InstrumentInlineDatum(
                    label: presentation.orchardTrees,
                    value: "\(filteredTrees.count) / \(locatedTrees.count)"
                )
            }
        }
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(YieldLevel.allCases, id: \.self) { level in
            let isSelected = filterYieldLevel == level
            InstrumentChip(
                title: presentation.yieldLevelLabel(level),
                isSelected: isSelected,
                count: summary.count(for: level)
            ) {
                toggle(level)
            }
            .accessibilityLabel(Text(presentation.yieldLevelLabel(level)))
            .accessibilityValue(
                Text(isSelected ? presentation.filterSelected : presentation.filterNotSelected)
            )
            .accessibilityHint(
                Text(isSelected ? presentation.filterSelectedHint : presentation.filterHint)
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        if filterYieldLevel != nil {
            Button {
                filterYieldLevel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .frame(minWidth: Design.Touch.minimumWidth, minHeight: Design.Touch.minimumHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(presentation.clearFilter))
            .accessibilityHint(Text(presentation.clearFilterHint))
        }
    }

    private func toggle(_ level: YieldLevel) {
        filterYieldLevel = OrchardMapYieldFilterSelection.next(
            current: filterYieldLevel,
            tapping: level
        )
    }
}
