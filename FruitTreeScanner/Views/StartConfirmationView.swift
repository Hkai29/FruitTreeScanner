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
        HStack(spacing: Design.Space.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("目标水果")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Text("本次扫描固定使用此类别；识别结果只作校验。")
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            Spacer()
            Picker("目标水果", selection: $selectedFruitCategory) {
                ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
            .accessibilityLabel("目标水果")
            .accessibilityHint("选择后将固定用于本次扫描，不会被自动识别结果替换")
        }
    }

    private var tagSummary: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "tag.fill")
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)

            Text("标签")
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            if tags.isEmpty {
                Text("无")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            } else {
                HStack(spacing: Design.Space.xs) {
                    ForEach(tags.prefix(3)) { tag in
                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.system(size: 12))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.system(size: 12))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
        }
    }

    private var gpsSummary: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                .font(.system(size: 16))
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.slate)
                .frame(width: 24)

            Text("GPS")
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(gps.isAvailable ? "已获取" : "获取中...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.Dark.textSecondary)
        }
    }
}

struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Design.Colors.Dark.textPrimary

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}
