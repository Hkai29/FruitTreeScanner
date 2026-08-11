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
        let treeCountKey = treeCount == 1
            ? "orchard_map.chrome.tree_count_one"
            : "orchard_map.chrome.tree_count_other"
        let treeCountFormat = bundle.localizedString(
            forKey: treeCountKey,
            value: "%d 棵果树",
            table: nil
        )
        treeCountText = String(format: treeCountFormat, treeCount)
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
    let treeCount: Int
    let onDismiss: () -> Void

    var body: some View {
        let presentation = OrchardMapChromePresentation(treeCount: treeCount)

        HStack(spacing: Design.Space.md) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(
                        width: Design.Touch.minimumWidth,
                        height: Design.Touch.minimumHeight
                    )
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }
            .accessibilityLabel(presentation.closeAccessibilityLabel)

            Spacer()

            if treeCount > 0 {
                Text(presentation.treeCountText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
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
    let selectedTree: TreeAnnotation?
    let filteredTrees: [TreeAnnotation]
    @Binding var filterYieldLevel: YieldLevel?
    let onClearSelection: () -> Void

    var body: some View {
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
    @Binding var filterYieldLevel: YieldLevel?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let presentation = OrchardMapChromePresentation(treeCount: 0)

        Group {
            switch OrchardMapLegendLayout(dynamicTypeSize: dynamicTypeSize) {
            case .horizontal:
                ViewThatFits(in: .horizontal) {
                    horizontalLegend(presentation)
                    stackedLegend(presentation)
                }
            case .stacked:
                stackedLegend(presentation)
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private func horizontalLegend(_ presentation: OrchardMapChromePresentation) -> some View {
        HStack(spacing: Design.Space.sm) {
            filterButtons(presentation)
            Spacer(minLength: 0)
            clearButton(presentation)
        }
    }

    private func stackedLegend(_ presentation: OrchardMapChromePresentation) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            filterButtons(presentation)
            clearButton(presentation)
        }
    }

    @ViewBuilder
    private func filterButtons(_ presentation: OrchardMapChromePresentation) -> some View {
        ForEach([YieldLevel.high, .medium, .low], id: \.self) { level in
            Button {
                toggle(level)
            } label: {
                HStack(spacing: Design.Space.xs) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 10, height: 10)

                    Text(presentation.filterLabel(for: level))
                        .font(.caption)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(
                            filterYieldLevel == level
                                ? level.color
                                : Design.Colors.Dark.textPrimary
                        )
                }
                .frame(minHeight: Design.Touch.minimumHeight)
                .padding(.horizontal, Design.Space.sm)
                .background(
                    filterYieldLevel == level
                        ? level.color.opacity(0.1)
                        : Color.clear
                )
                .cornerRadius(Design.Radius.full)
            }
            .accessibilityAddTraits(filterYieldLevel == level ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func clearButton(_ presentation: OrchardMapChromePresentation) -> some View {
        if filterYieldLevel != nil {
            Button {
                filterYieldLevel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(
                        width: Design.Touch.minimumWidth,
                        height: Design.Touch.minimumHeight
                    )
            }
            .accessibilityLabel(presentation.clearFilterAccessibilityLabel)
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
