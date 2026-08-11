import SwiftUI

struct OrchardTreeDetailPresentation: Equatable {
    let treeTitle: String
    let closeAccessibilityLabel: String
    let estimatedYieldTitle: String
    let estimatedYieldValue: String
    let fruitCountTitle: String
    let fruitCountValue: String
    let confidenceTitle: String
    let confidenceValue: String
    let scanDateTitle: String
    let scanDateValue: String
    let yieldLevelTitle: String
    let yieldLevelValue: String

    init(
        tree: TreeAnnotation,
        bundle: Bundle = .main,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let localizedYieldValue = Self.formattedYield(tree.weight, locale: locale)
        let localizedDate = Self.formattedDate(
            tree.scanDate,
            locale: locale,
            timeZone: timeZone
        )

        treeTitle = Self.formattedString(
            key: "orchard_map.detail.tree_title",
            fallback: "树体 %@",
            bundle: bundle,
            locale: locale,
            arguments: [tree.treeID]
        )
        closeAccessibilityLabel = Self.formattedString(
            key: "orchard_map.detail.close_accessibility",
            fallback: "关闭 %@ 的详情",
            bundle: bundle,
            locale: locale,
            arguments: [tree.treeID]
        )
        estimatedYieldTitle = Self.localizedString(
            key: "orchard_map.detail.estimated_yield",
            fallback: "预估产量",
            bundle: bundle
        )
        estimatedYieldValue = Self.formattedString(
            key: "orchard_map.detail.yield_format",
            fallback: "%@ kg",
            bundle: bundle,
            locale: locale,
            arguments: [localizedYieldValue]
        )
        fruitCountTitle = Self.localizedString(
            key: "orchard_map.detail.fruit_count",
            fallback: "果实数",
            bundle: bundle
        )
        fruitCountValue = Self.formattedString(
            key: tree.fruitCount == 1
                ? "orchard_map.detail.fruit_count_one"
                : "orchard_map.detail.fruit_count_other",
            fallback: "%d 个",
            bundle: bundle,
            locale: locale,
            arguments: [tree.fruitCount]
        )
        confidenceTitle = Self.localizedString(
            key: "orchard_map.detail.confidence",
            fallback: "置信度",
            bundle: bundle
        )
        confidenceValue = Self.localizedString(
            key: Self.confidenceKey(for: tree.confidence),
            fallback: Self.confidenceFallback(for: tree.confidence),
            bundle: bundle
        )
        scanDateTitle = Self.localizedString(
            key: "orchard_map.detail.scan_date",
            fallback: "扫描日期",
            bundle: bundle
        )
        scanDateValue = localizedDate
        yieldLevelTitle = Self.localizedString(
            key: "orchard_map.detail.yield_level",
            fallback: "产量等级",
            bundle: bundle
        )
        yieldLevelValue = Self.localizedString(
            key: Self.yieldLevelKey(for: tree.yieldLevel),
            fallback: Self.yieldLevelFallback(for: tree.yieldLevel),
            bundle: bundle
        )
    }

    private static func localizedString(key: String, fallback: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    private static func formattedString(
        key: String,
        fallback: String,
        bundle: Bundle,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String {
        let format = localizedString(key: key, fallback: fallback, bundle: bundle)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func formattedYield(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0.0"
    }

    private static func formattedDate(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    private static func confidenceKey(for confidence: String) -> String {
        switch confidence {
        case "high": return "orchard_map.detail.confidence_high"
        case "medium": return "orchard_map.detail.confidence_medium"
        default: return "orchard_map.detail.confidence_low"
        }
    }

    private static func confidenceFallback(for confidence: String) -> String {
        switch confidence {
        case "high": return "高"
        case "medium": return "中"
        default: return "低"
        }
    }

    private static func yieldLevelKey(for level: YieldLevel) -> String {
        switch level {
        case .high: return "orchard_map.detail.yield_level_high"
        case .medium: return "orchard_map.detail.yield_level_medium"
        case .low: return "orchard_map.detail.yield_level_low"
        }
    }

    private static func yieldLevelFallback(for level: YieldLevel) -> String {
        switch level {
        case .high: return "高产"
        case .medium: return "中产"
        case .low: return "低产"
        }
    }
}

enum OrchardTreeDetailLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .stacked : .horizontal
    }
}

struct TreeDetailCard: View {
    let tree: TreeAnnotation
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    private var confidenceColor: Color {
        switch tree.confidence {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.error
        }
    }

    var body: some View {
        let presentation = OrchardTreeDetailPresentation(
            tree: tree,
            locale: locale,
            timeZone: timeZone
        )

        VStack(alignment: .leading, spacing: Design.Space.md) {
            header(presentation)
            DividerLine()
            statsRow(presentation)
            yieldBadgeRow(presentation)
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private func header(_ presentation: OrchardTreeDetailPresentation) -> some View {
        HStack {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: tree.yieldLevel.icon)
                    .font(.body.weight(.medium))
                    .foregroundColor(tree.yieldLevel.color)

                Text(presentation.treeTitle)
                    .font(.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(
                        width: Design.Touch.minimumWidth,
                        height: Design.Touch.minimumHeight
                    )
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
            }
            .accessibilityLabel(presentation.closeAccessibilityLabel)
        }
    }

    @ViewBuilder
    private func statsRow(_ presentation: OrchardTreeDetailPresentation) -> some View {
        switch OrchardTreeDetailLayout(dynamicTypeSize: dynamicTypeSize) {
        case .horizontal:
            HStack(spacing: Design.Space.md) {
                statItems(presentation)
            }
        case .stacked:
            VStack(alignment: .leading, spacing: Design.Space.md) {
                statItems(presentation)
            }
        }
    }

    @ViewBuilder
    private func statItems(_ presentation: OrchardTreeDetailPresentation) -> some View {
        TreeStatItem(
            label: presentation.estimatedYieldTitle,
            value: presentation.estimatedYieldValue,
            color: Design.Colors.Dark.glow
        )
        TreeStatItem(
            label: presentation.fruitCountTitle,
            value: presentation.fruitCountValue,
            color: Design.Colors.Dark.glow
        )
        TreeStatItem(
            label: presentation.confidenceTitle,
            value: presentation.confidenceValue,
            color: confidenceColor
        )
        TreeStatItem(
            label: presentation.scanDateTitle,
            value: presentation.scanDateValue,
            color: Design.Colors.Dark.textSecondary
        )
    }

    private func yieldBadgeRow(_ presentation: OrchardTreeDetailPresentation) -> some View {
        HStack {
            Text(presentation.yieldLevelTitle)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            HStack(spacing: Design.Space.xs) {
                Circle()
                    .fill(tree.yieldLevel.color)
                    .frame(width: 8, height: 8)

                Text(presentation.yieldLevelValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(tree.yieldLevel.color)
            }
            .padding(.horizontal, Design.Space.sm)
            .padding(.vertical, Design.Space.xs)
            .background(tree.yieldLevel.color.opacity(0.1))
            .cornerRadius(Design.Radius.full)
        }
        .accessibilityElement(children: .combine)
    }
}
