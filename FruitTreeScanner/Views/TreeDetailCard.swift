import SwiftUI

/// 选中树体的读数面板。
///
/// 面板承载四类真实读数：预估产量、果实数、置信度与扫描日期，
/// 外加产量等级与关闭操作。布局用仪器式面板，不再用带投影的浮起卡片。
struct TreeDetailCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    let tree: TreeAnnotation
    let onClose: () -> Void

    /// 置信度颜色：钢蓝表示中性可靠，琥珀表示需要留意，锈红表示不可用。
    private var confidenceColor: Color {
        switch tree.confidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return Design.Colors.Workspace.information
        case "medium": return Design.Colors.Workspace.attention
        case "low": return Design.Colors.Workspace.failure
        default: return Design.Colors.Workspace.secondary
        }
    }

    var body: some View {
        InstrumentPanel(
            label: presentation.treeTitle(tree.treeID),
            trailing: AnyView(closeButton),
            fill: Design.Colors.Workspace.surfaceQuiet
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statsRow
                DividerLine()
                yieldLevelRow
                Text(tree.positionDescription)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(presentation.closeDetails))
        .accessibilityHint(Text(presentation.closeDetailsHint))
    }

    @ViewBuilder
    private var statsRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                stats
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12, alignment: .leading),
                    GridItem(.flexible(), spacing: 12, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                stats
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        InstrumentDatum(
            label: presentation.estimatedYield,
            value: presentation.yieldText(tree.weight, locale: locale)
        )
        InstrumentDatum(
            label: presentation.fruitCount,
            value: presentation.fruitCountText(tree.fruitCount, locale: locale)
        )
        InstrumentDatum(
            label: presentation.confidence,
            value: presentation.confidenceLabel(tree.confidence),
            tint: confidenceColor
        )
        InstrumentDatum(
            label: presentation.scanDate,
            value: presentation.scanDateText(tree.scanDate, locale: locale)
        )
    }

    @ViewBuilder
    private var yieldLevelRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        layout {
            Text(presentation.yieldLevelTitle)
                .instrumentLabel()

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: tree.yieldLevel.icon)
                    .font(.caption)
                    .foregroundColor(tree.yieldLevel.color)
                    .accessibilityHidden(true)

                Text(presentation.yieldLevelLabel(tree.yieldLevel))
                    .font(.caption.weight(.medium))
                    .foregroundColor(tree.yieldLevel.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
