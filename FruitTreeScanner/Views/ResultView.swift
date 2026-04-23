// ResultView.swift
// 扫描完成后的产量估算结果页 - 统一深色科技风格

import SwiftUI

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "0a1628")
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // 顶部产量卡片
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(confidenceColor.opacity(0.5), lineWidth: 1.5)
                            )

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(confidenceColor)

                                Text(treeID)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Text(String(format: "%.1f", result.yieldFinalKg))
                                .font(.system(size: 72, weight: .heavy, design: .rounded))
                                .foregroundColor(confidenceColor)

                            Text("kg")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(confidenceColor)
                                    .frame(width: 8, height: 8)
                                Text(confidenceLabel)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(confidenceColor)
                            }

                            if !result.note.isEmpty {
                                Text(result.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(32)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // 路线B
                    if result.nLidar > 0 {
                        ResultSectionCard(
                            title: "路线B · 果实体积法",
                            icon: "circle.grid.3x3",
                            color: "4ADE80"
                        ) {
                            ResultInfoRow(label: "LiDAR 检测果实", value: "\(result.nLidar) 个")
                            if let nV = result.nVisual {
                                ResultInfoRow(label: "视觉计数", value: "\(nV) 个")
                                ResultInfoRow(label: "遮挡校正系数", value: String(format: "×%.2f", result.correctionK))
                            }
                            ResultInfoRow(label: "可见部分重量", value: String(format: "%.2f kg", result.yieldBVisibleKg))
                            ResultInfoRow(label: "校正后重量", value: String(format: "%.2f kg", result.yieldBCorrectedKg), highlight: true)
                            ResultInfoRow(label: "平均果实直径", value: String(format: "%.1f cm", result.meanDiameterCm))
                        }
                    }

                    // 路线A
                    ResultSectionCard(
                        title: "路线A · 冠层体积法",
                        icon: "tree.fill",
                        color: "60A5FA"
                    ) {
                        if let yA = result.yieldAKg {
                            ResultInfoRow(label: "冠层回归产量", value: String(format: "%.2f kg", yA), highlight: true)
                            ResultInfoRow(label: "冠层体积", value: String(format: "%.3f m³", result.crownVolM3))
                            ResultInfoRow(label: "树高", value: String(format: "%.2f m", result.treeHeightM))
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.white.opacity(0.4))
                                Text("路线A模型未训练，需采集称重数据后训练")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                    }

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button(action: onDismiss) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("继续扫描下一棵")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "0a1628"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "4ADE80"), Color(hex: "22C55E")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                        }

                        Button {
                            // 返回主界面 - dismiss scan view to return to dashboard
                            onDismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 16))
                                Text("返回主界面")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var confidenceColor: Color {
        switch result.confidence {
        case "high":          return Color(hex: "4ADE80")
        case "medium":        return Color(hex: "FBBF24")
        case "manual_review": return Color(hex: "EF4444")
        default:              return Color(hex: "9CA3AF")
        }
    }

    private var confidenceLabel: String {
        switch result.confidence {
        case "high":          return "高置信度"
        case "medium":        return "中等置信度"
        case "manual_review": return "需人工复核"
        default:              return "低置信度"
        }
    }
}

// MARK: - 结果卡片
struct ResultSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: color))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - 结果信息行
struct ResultInfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: highlight ? .bold : .medium, design: .monospaced))
                .foregroundColor(highlight ? Color(hex: "4ADE80") : .white.opacity(0.8))
        }
    }
}