import SwiftUI

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

            VStack(alignment: .leading, spacing: 2) {
                Text("当前扫描: \(activeCategoryName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("\(customizedCount) 个品种已自定义")
                    .font(Design.Typography.caption)
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
            Text("找到 \(count) 个品种")
                .font(Design.Typography.caption)
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

                Text("没有匹配的品种")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Text("未找到 \"\(searchText)\" 相关参数。")
                .font(.system(size: 13))
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

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Button(action: onUse) {
                HStack(spacing: Design.Space.sm) {
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
            .accessibilityLabel(isCurrent ? "\(params.displayName)，当前扫描品种" : "设为当前扫描品种: \(params.displayName)")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.glow)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑 \(params.displayName) 参数")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
    }

    private var titleRow: some View {
        HStack {
            Text(params.displayName)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            if isCurrent {
                Text("当前")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.bgDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Design.Colors.harvest))
            } else if params.isCustomized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.harvest)
            }
        }
    }

    private var parameterChips: some View {
        HStack(spacing: Design.Space.sm) {
            ParamChip(label: "直径", value: "\(Int(params.diamMin * 1000))~\(Int(params.diamMax * 1000))mm")
            ParamChip(label: "均重", value: "\(Int(params.averageWeightG))g")
            ParamChip(label: "Eps", value: String(format: "%.3f", params.clusterEps))
        }
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

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Design.Colors.Dark.bgDeep)
        )
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
            Text(title)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

struct VarietySliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let unit: String
    let displayValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack {
                Text(title)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Text("\(displayValue)\(unit)")
                    .font(Design.Typography.mono)
                    .foregroundColor(Design.Colors.Dark.glow)
            }

            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.Dark.glow)
        }
    }
}
