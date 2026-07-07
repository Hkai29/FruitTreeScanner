import SwiftUI

struct OrchardMapTopBar: View {
    let treeCount: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }

            Spacer()

            if treeCount > 0 {
                Text("\(treeCount) 棵果树")
                    .font(Design.Typography.subheadlineMedium)
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

    var body: some View {
        HStack(spacing: Design.Space.lg) {
            ForEach([YieldLevel.high, .medium, .low], id: \.self) { level in
                Button {
                    toggle(level)
                } label: {
                    HStack(spacing: Design.Space.xs) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 10, height: 10)

                        Text(level.label)
                            .font(Design.Typography.caption)
                            .foregroundColor(filterYieldLevel == level ? level.color : Design.Colors.Dark.textPrimary)
                    }
                    .padding(.horizontal, Design.Space.sm)
                    .padding(.vertical, Design.Space.xs)
                    .background(filterYieldLevel == level ? level.color.opacity(0.1) : Color.clear)
                    .cornerRadius(Design.Radius.full)
                }
            }

            Spacer()

            if filterYieldLevel != nil {
                Button {
                    filterYieldLevel = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
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
