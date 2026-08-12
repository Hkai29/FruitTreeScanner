import SwiftUI

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

struct OrchardMapTopBar: View {
    @Environment(\.locale) private var locale
    @Environment(\.orchardMapPresentation) private var presentation
    let treeCount: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }
            .accessibilityLabel(Text(presentation.closeMap))
            .accessibilityHint(Text(presentation.closeMapHint))

            Spacer()

            if treeCount > 0 {
                Text(presentation.treeCountText(treeCount, locale: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Capsule())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }
        }
    }
}

struct OrchardMapBottomPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedTree: TreeAnnotation?
    let filteredTrees: [TreeAnnotation]
    @Binding var filterYieldLevel: YieldLevel?
    let maximumHeight: CGFloat?
    let onClearSelection: () -> Void

    init(
        selectedTree: TreeAnnotation?,
        filteredTrees: [TreeAnnotation],
        filterYieldLevel: Binding<YieldLevel?>,
        maximumHeight: CGFloat? = nil,
        onClearSelection: @escaping () -> Void
    ) {
        self.selectedTree = selectedTree
        self.filteredTrees = filteredTrees
        self._filterYieldLevel = filterYieldLevel
        self.maximumHeight = maximumHeight
        self.onClearSelection = onClearSelection
    }

    var body: some View {
        Group {
            if OrchardMapLegendLayout(dynamicTypeSize: dynamicTypeSize) == .stacked {
                ScrollView(.vertical) {
                    panelContent
                }
                .frame(maxHeight: maximumHeight)
            } else {
                panelContent
            }
        }
    }

    private var panelContent: some View {
        VStack(spacing: Design.Space.md) {
            OrchardMapLegend(filterYieldLevel: $filterYieldLevel)

            if let selectedTree {
                TreeDetailCard(tree: selectedTree, onClose: onClearSelection)
            } else {
                TreeCountCard(filteredTrees: filteredTrees)
            }
        }
    }
}

struct OrchardMapLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    @Binding var filterYieldLevel: YieldLevel?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    legendItems
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Design.Space.md) {
                        legendItems
                    }
                }
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach([YieldLevel.high, .medium, .low], id: \.self) { level in
            Button {
                toggle(level)
            } label: {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: level.icon)
                        .font(.caption)
                        .foregroundColor(level.color)

                    Text(presentation.yieldLevelLabel(level))
                        .font(.caption)
                        .foregroundColor(
                            filterYieldLevel == level
                                ? level.color
                                : Design.Colors.Dark.textPrimary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Design.Space.sm)
                .padding(.vertical, Design.Space.xs)
                .background(filterYieldLevel == level ? level.color.opacity(0.1) : Color.clear)
                .cornerRadius(Design.Radius.full)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(presentation.yieldLevelLabel(level)))
            .accessibilityValue(
                Text(filterYieldLevel == level ? presentation.filterSelected : presentation.filterNotSelected)
            )
            .accessibilityHint(
                Text(filterYieldLevel == level ? presentation.filterSelectedHint : presentation.filterHint)
            )
            .accessibilityAddTraits(filterYieldLevel == level ? .isSelected : [])
        }

        if filterYieldLevel != nil {
            Button {
                filterYieldLevel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
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

var orchardFloatingSurface: some View {
    RoundedRectangle(cornerRadius: Design.Radius.large)
        .fill(Design.Colors.Dark.bgSurface)
        .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
}
