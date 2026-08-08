// StartConfirmationView.swift
// 新建扫描流程的最终确认步骤

import SwiftUI

struct Step5_Confirmation: View {
    let treeID: String
    let plot: Plot?
    let season: Season
    @Binding var selectedFruitCategory: FruitCategory
    let tags: [GroupTag]
    @ObservedObject var gps: GPSRecorder
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 5,
                totalSteps: 5,
                title: "启动前检查",
                subtitle: "确认编号、分组和定位状态。"
            )

            VStack(spacing: Design.Space.md) {
                ConfirmationRow(icon: "number", label: "编号", value: treeID)

                Divider().background(Design.Colors.Dark.glassBorder)

                fruitCategoryPicker

                Divider().background(Design.Colors.Dark.glassBorder)

                ConfirmationRow(
                    icon: "map.fill",
                    label: "地块",
                    value: plot?.name ?? "未分配",
                    valueColor: plot != nil ? Design.Colors.forest : Color(hex: "8E8E93")
                )

                Divider().background(Design.Colors.Dark.glassBorder)

                ConfirmationRow(
                    icon: season == .mature ? "apple.logo" : "leaf.fill",
                    label: "估算阶段",
                    value: season == .mature ? "成熟期（RGB + LiDAR 融合）" : "非成熟期（待标定）",
                    valueColor: Design.Colors.harvest
                )

                Divider().background(Design.Colors.Dark.glassBorder)

                tagSummary

                Divider().background(Design.Colors.Dark.glassBorder)

                gpsSummary
            }
            .padding(Design.Space.lg)
            .startSurface(cornerRadius: 10)

            StartNoteRow(
                icon: "camera.metering.center.weighted",
                text: "开始后请围绕树体缓慢移动，尽量让树冠与果实进入稳定视野。",
                tint: Design.Colors.harvest
            )
        }
    }

    private var fruitCategoryPicker: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: Design.Space.md) {
                    fruitCategoryLabel
                    Spacer(minLength: Design.Space.sm)
                    fruitCategoryMenu
                }
            case .vertical:
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    fruitCategoryLabel
                    fruitCategoryMenu
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var fruitCategoryLabel: some View {
        HStack(alignment: .top, spacing: Design.Space.md) {
            Image(systemName: "leaf.fill")
                .font(.body)
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.FruitCategoryVerification.selectionTitle)
                    .font(.body)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Text(L10n.FruitCategoryVerification.fixedForScan)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Dark.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fruitCategoryMenu: some View {
        Picker(L10n.FruitCategoryVerification.selectionTitle, selection: $selectedFruitCategory) {
            ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                Text(L10n.Fruit.name(for: category)).tag(category)
            }
        }
        .pickerStyle(.menu)
        .tint(Design.Colors.harvest)
        .accessibilityLabel(L10n.FruitCategoryVerification.selectedAccessibilityLabel)
        .accessibilityValue(L10n.FruitCategoryVerification.selectionAccessibilityValue(selectedFruitCategory))
        .accessibilityHint(L10n.FruitCategoryVerification.selectedAccessibilityHint)
    }

    private var tagSummary: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: Design.Space.md) {
                    tagSummaryLabel
                    Spacer(minLength: Design.Space.sm)
                    compactTagSummaryValue
                }
            case .vertical:
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    tagSummaryLabel
                    Text(tagSummaryText)
                        .font(.body.weight(.medium))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tagLabelText)
        .accessibilityValue(tagSummaryText)
    }

    private var tagSummaryLabel: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "tag.fill")
                .font(.body)
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(tagLabelText)
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    @ViewBuilder
    private var compactTagSummaryValue: some View {
        if tags.isEmpty {
            Text(emptyTagsText)
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        } else {
            HStack(spacing: Design.Space.xs) {
                ForEach(tags.prefix(3)) { tag in
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(tag.name)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }
                if tags.count > 3 {
                    Text("+\(tags.count - 3)")
                        .font(.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
    }

    private var tagSummaryText: String {
        guard !tags.isEmpty else { return emptyTagsText }
        let visibleNames = tags.prefix(3).map(\.name).joined(separator: "、")
        if tags.count > 3 {
            return "\(visibleNames) +\(tags.count - 3)"
        }
        return visibleNames
    }

    private var tagLabelText: String { "标签" }

    private var emptyTagsText: String { "无" }

    private var gpsSummary: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: Design.Space.md) {
                    gpsLabel
                    Spacer(minLength: Design.Space.sm)
                    gpsValue
                }
            case .vertical:
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    gpsLabel
                    gpsValue
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GPS")
        .accessibilityValue(gpsValueText)
    }

    private var gpsLabel: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                .font(.body)
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.slate)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text("GPS")
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var gpsValue: some View {
        Text(gpsValueText)
            .font(.subheadline.monospaced())
            .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.Dark.textSecondary)
    }

    private var gpsValueText: String {
        gps.isAvailable ? "已获取" : "获取中..."
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}

struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Design.Colors.Dark.textPrimary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: Design.Space.md) {
                    rowLabel
                    Spacer(minLength: Design.Space.sm)
                    rowValue
                        .multilineTextAlignment(.trailing)
                }
            case .vertical:
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    rowLabel
                    rowValue
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var rowLabel: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(label)
                .font(.body)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var rowValue: some View {
        Text(value)
            .font(.body.weight(.medium))
            .foregroundColor(valueColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}
