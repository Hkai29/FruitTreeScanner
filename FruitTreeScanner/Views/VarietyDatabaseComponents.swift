// VarietyDatabaseComponents.swift
// 品种参数库的展示组件。
//
// 所有读数都来自 FruitParametersStore 里的真实参数，不做二次估算或四舍五入。
// 颜色只用工作区令牌：当前品种用信号青，已自定义用次级墨色，不引入新的色相。

import Foundation
import SwiftUI

// MARK: - 参数格式化

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
            millimeterNumber(meters, locale: locale),
            unit: "mm"
        )
    }

    static func diameterRange(
        minimumMeters: Float,
        maximumMeters: Float,
        locale: Locale = .current
    ) -> String {
        L10n.VarietyDatabase.diameterRange(
            minimum: millimeterNumber(minimumMeters, locale: locale),
            maximum: millimeterNumber(maximumMeters, locale: locale),
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

    private static func millimeterNumber(_ meters: Float, locale: Locale) -> String {
        // Display the nearest whole millimeter without changing the stored physical value.
        integer(Int((meters * 1_000).rounded()), locale: locale)
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

/// 品种列表里的补充文案。放在视图文件内，避免与 Core/L10n.swift 的改动冲突。
enum VarietyCopy {
    static let customized = NSLocalizedString(
        "variety.customized_badge",
        value: "已自定义",
        comment: "Variety row marker for parameters the user changed"
    )
}

// MARK: - 顶部摘要

struct VarietyDatabaseSummaryBar: View {
    let activeCategoryName: String
    let customizedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.Workspace.accent)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(Design.Colors.Workspace.accentSoft)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.VarietyDatabase.activeScan(activeCategoryName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.VarietyDatabase.customizedCount(customizedCount))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
    }
}

// MARK: - 搜索结果条

struct VarietySearchResultBar: View {
    let count: Int

    var body: some View {
        HStack {
            Text(L10n.VarietyDatabase.searchResults(count))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.Workspace.surfaceQuiet)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Workspace.lineSoft).frame(height: 0.5)
        }
    }
}

// MARK: - 搜索空状态

struct VarietySearchEmptyState: View {
    let searchText: String

    var body: some View {
        InstrumentEmptyState(
            systemImage: "magnifyingglass",
            title: L10n.VarietyDatabase.searchEmptyTitle,
            message: L10n.VarietyDatabase.searchEmptyMessage(searchText)
        )
    }
}

// MARK: - 品种行

struct VarietyRow: View {
    let category: FruitCategory
    let params: FruitVarietyParams
    let isCurrent: Bool
    let onUse: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onUse) {
                HStack(alignment: .top, spacing: 10) {
                    categoryMark

                    VStack(alignment: .leading, spacing: 7) {
                        titleRow
                        parameterReadouts
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
        .padding(.vertical, 11)
    }

    // MARK: 组成

    private var categoryMark: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Design.Colors.Workspace.secondary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.inset)
            )
            .accessibilityHidden(true)
    }

    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                fruitNameText
                statusMarkers
            }
            VStack(alignment: .leading, spacing: 4) {
                fruitNameText
                statusMarkers
            }
        }
    }

    private var fruitNameText: some View {
        Text(fruitName)
            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
            .foregroundColor(Design.Colors.Workspace.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusMarkers: some View {
        if isCurrent {
            Text(L10n.VarietyDatabase.current)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.accent)
                .fixedSize(horizontal: true, vertical: true)
        }
        if params.isCustomized {
            Text(VarietyCopy.customized)
                .font(.caption2)
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var parameterReadouts: some View {
        VStack(alignment: .leading, spacing: 3) {
            ParamChip(
                label: L10n.VarietyDatabase.diameterChip,
                value: VarietyParameterFormatter.diameterRange(
                    minimumMeters: params.diamMin,
                    maximumMeters: params.diamMax
                )
            )
            ParamChip(
                label: L10n.VarietyDatabase.averageWeightChip,
                value: VarietyParameterFormatter.grams(params.averageWeightG)
            )
            ParamChip(
                label: L10n.VarietyDatabase.epsChip,
                value: VarietyParameterFormatter.decimal(params.clusterEps, fractionDigits: 3)
            )
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.accent)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.VarietyDatabase.editAccessibility(fruitName))
    }

    // MARK: 文案

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
}

// MARK: - 行内读数

/// 品种参数行内读数。保留既有类型名，绘制改用仪器式行内读数。
struct ParamChip: View {
    let label: String
    let value: String

    var body: some View {
        InstrumentInlineDatum(label: label, value: value)
    }
}

// MARK: - 分区标题

/// 品种参数编辑页的分组标题：小标签样式 + 可选图标。
struct VarietySectionHeader: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .instrumentLabel()
        }
    }
}

// MARK: - 滑杆行

struct VarietySliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let displayValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Text(displayValue)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }

            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.Workspace.accent)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
                .accessibilityHint(L10n.VarietyDatabase.sliderHint)
        }
        .padding(.vertical, 12)
    }
}
