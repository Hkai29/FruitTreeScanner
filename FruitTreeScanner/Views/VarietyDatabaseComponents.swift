import Foundation
import SwiftUI

enum VarietyParameterFormatter {
    static func integer(_ value: Int, locale: Locale = .current) -> String {
        numberFormatter(fractionDigits: 0, locale: locale)
            .string(from: NSNumber(value: value)) ?? String(value)
    }

    static func decimal(
        _ value: Float,
        fractionDigits: Int,
        locale: Locale = .current
    ) -> String {
        numberFormatter(fractionDigits: fractionDigits, locale: locale)
            .string(from: NSNumber(value: value)) ?? String(value)
    }

    static func millimeters(_ meters: Float, locale: Locale = .current) -> String {
        L10n.VarietyDatabase.unitValue(
            integer(Int(meters * 1_000), locale: locale),
            unit: "mm"
        )
    }

    static func diameterRange(
        minimumMeters: Float,
        maximumMeters: Float,
        locale: Locale = .current
    ) -> String {
        L10n.VarietyDatabase.diameterRange(
            minimum: integer(Int(minimumMeters * 1_000), locale: locale),
            maximum: integer(Int(maximumMeters * 1_000), locale: locale),
            unit: "mm"
        )
    }

    static func grams(_ value: Float, locale: Locale = .current) -> String {
        L10n.VarietyDatabase.unitValue(
            integer(Int(value), locale: locale),
            unit: "g"
        )
    }

    static func meters(_ value: Float, locale: Locale = .current) -> String {
        L10n.VarietyDatabase.unitValue(
            decimal(value, fractionDigits: 3, locale: locale),
            unit: "m"
        )
    }

    private static func numberFormatter(fractionDigits: Int, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }
}

struct VarietyDatabaseSummaryBar: View {
    let activeCategoryName: String
    let customizedCount: Int

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.forest)
                .frame(width: 28, height: 28)
                .background(Design.Colors.forest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.VarietyDatabase.activeScan(activeCategoryName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(L10n.VarietyDatabase.customizedCount(customizedCount))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, 10)
        .background(Design.Colors.Dark.bgSurface)
    }
}

struct VarietySearchResultBar: View {
    let count: Int

    var body: some View {
        HStack {
            Text(L10n.VarietyDatabase.searchResults(count))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.xs)
        .background(Design.Colors.Dark.bgDeep)
    }
}

struct VarietySearchEmptyState: View {
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(width: 28, height: 28)
                    .background(Design.Colors.harvest.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                Text(L10n.VarietyDatabase.searchEmptyTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Text(L10n.VarietyDatabase.searchEmptyMessage(searchText))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .padding(.horizontal, Design.Space.md)
    }
}

struct VarietyRow: View {
    let category: FruitCategory
    let params: FruitVarietyParams
    let isCurrent: Bool
    let onUse: () -> Void
    let onEdit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
    }

    private var compactLayout: some View {
        HStack(spacing: 4) {
            Button(action: onUse) {
                HStack(spacing: Design.Space.xs) {
                    fruitIcon

                    VStack(alignment: .leading, spacing: 4) {
                        titleRow
                        parameterChips
                    }

                    Spacer(minLength: Design.Space.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint(L10n.VarietyDatabase.useHint)

            editButton
        }
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: Design.Space.xs) {
            Button(action: onUse) {
                HStack(alignment: .top, spacing: Design.Space.xs) {
                    fruitIcon

                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        titleRow
                        parameterChips
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint(L10n.VarietyDatabase.useHint)

            editButton
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.glow)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.VarietyDatabase.editAccessibility(fruitName))
    }

    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                fruitNameText
                statusIndicator
            }

            VStack(alignment: .leading, spacing: 4) {
                fruitNameText
                statusIndicator
            }
        }
    }

    private var fruitNameText: some View {
        Text(fruitName)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isCurrent {
            Text(L10n.VarietyDatabase.current)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.bgDeep)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Design.Colors.harvest))
                .fixedSize(horizontal: true, vertical: true)
        } else if params.isCustomized {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(Design.Colors.harvest)
                .accessibilityHidden(true)
        }
    }

    private var parameterChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                diameterChip
                averageWeightChip
                epsChip
            }

            VStack(alignment: .leading, spacing: 4) {
                diameterChip
                averageWeightChip
                epsChip
            }
        }
    }

    private var diameterChip: some View {
        ParamChip(
            label: L10n.VarietyDatabase.diameterChip,
            value: VarietyParameterFormatter.diameterRange(
                minimumMeters: params.diamMin,
                maximumMeters: params.diamMax
            )
        )
    }

    private var averageWeightChip: some View {
        ParamChip(
            label: L10n.VarietyDatabase.averageWeightChip,
            value: VarietyParameterFormatter.grams(params.averageWeightG)
        )
    }

    private var epsChip: some View {
        ParamChip(
            label: L10n.VarietyDatabase.epsChip,
            value: VarietyParameterFormatter.decimal(params.clusterEps, fractionDigits: 3)
        )
    }

    private var fruitName: String {
        L10n.Fruit.name(for: category)
    }

    private var rowAccessibilityLabel: String {
        if isCurrent {
            return L10n.VarietyDatabase.currentAccessibility(fruitName)
        }
        if params.isCustomized {
            return L10n.VarietyDatabase.customizedAccessibility(fruitName)
        }
        return L10n.VarietyDatabase.useAccessibility(fruitName)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isCurrent ? Design.Colors.harvest.opacity(0.12) : Design.Colors.Dark.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Design.Colors.harvest : Color.clear, lineWidth: 1)
            )
    }

    private var fruitIcon: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(fruitColor)
            .frame(width: 28, height: 28)
            .background(fruitColor.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }

    private var fruitColor: Color {
        switch category {
        case .apple: return Design.Colors.apple
        case .orange, .mandarin, .pomelo: return Design.Colors.harvest
        case .pear: return Color(hex: "9BAE78")
        case .peach: return Color(hex: "B98575")
        case .cherry: return Color(hex: "9E4D49")
        case .grape: return Color(hex: "6F5D78")
        case .mango: return Color(hex: "C09A45")
        case .kiwi: return Color(hex: "7F955C")
        default: return Design.Colors.harvest
        }
    }
}

struct ParamChip: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? Design.Space.xs : 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Design.Space.xs : 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Design.Colors.Dark.bgDeep)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct VarietySectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.glow)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

struct VarietySliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let displayValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    titleText
                    Spacer()
                    valueText
                }

                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    valueText
                }
            }

            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.Dark.glow)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
                .accessibilityHint(L10n.VarietyDatabase.sliderHint)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(displayValue)
            .font(.system(.body, design: .monospaced).weight(.medium))
            .foregroundColor(Design.Colors.Dark.glow)
            .fixedSize(horizontal: true, vertical: true)
    }
}
