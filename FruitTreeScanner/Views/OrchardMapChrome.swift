import SwiftUI

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
            if dynamicTypeSize.isAccessibilitySize {
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
        filterYieldLevel = filterYieldLevel == level ? nil : level
    }
}

var orchardFloatingSurface: some View {
    RoundedRectangle(cornerRadius: Design.Radius.large)
        .fill(Design.Colors.Dark.bgSurface)
        .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
}
