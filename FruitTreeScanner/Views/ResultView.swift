// ResultView.swift
// 扫描完成后的产量估算结果页

import SwiftUI

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // ── 顶部产量卡片 ────────────────────
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(confidenceColor.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(confidenceColor, lineWidth: 2)
                            )

                        VStack(spacing: 8) {
                            Text(treeID)
                                .font(.title3.bold())
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f kg", result.yieldFinalKg))
                                .font(.system(size: 56, weight: .black))
                                .foregroundColor(confidenceColor)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(confidenceColor)
                                    .frame(width: 8, height: 8)
                                Text(confidenceLabel)
                                    .font(.subheadline.bold())
                                    .foregroundColor(confidenceColor)
                            }
                            if !result.note.isEmpty {
                                Text(result.note)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(24)
                    }
                    .padding(.horizontal)

                    // ── 路线B：果实检测 ─────────────────
                    if result.nLidar > 0 {
                        SectionCard(title: "路线B · 果实体积法", icon: "circle.grid.3x3") {
                            InfoRow(label: "LiDAR 检测果实", value: "\(result.nLidar) 个")
                            if let nV = result.nVisual {
                                InfoRow(label: "视觉计数（校正用）", value: "\(nV) 个")
                                InfoRow(label: "遮挡校正系数 K",
                                        value: String(format: "×%.2f", result.correctionK))
                            }
                            InfoRow(label: "可见部分重量",
                                    value: String(format: "%.2f kg", result.yieldBVisibleKg))
                            InfoRow(label: "校正后重量",
                                    value: String(format: "%.2f kg", result.yieldBCorrectedKg),
                                    highlight: true)
                            InfoRow(label: "平均果实直径",
                                    value: String(format: "%.1f cm", result.meanDiameterCm))
                        }
                    }

                    // ── 路线A：冠层回归 ─────────────────
                    if let yA = result.yieldAKg {
                        SectionCard(title: "路线A · 冠层体积法", icon: "tree") {
                            InfoRow(label: "回归预测产量",
                                    value: String(format: "%.2f kg", yA),
                                    highlight: true)
                            InfoRow(label: "冠层体积",
                                    value: String(format: "%.3f m³", result.crownVolM3))
                            InfoRow(label: "树高",
                                    value: String(format: "%.2f m", result.treeHeightM))
                        }
                    } else {
                        SectionCard(title: "路线A · 冠层体积法", icon: "tree") {
                            Text("路线A模型未训练\n（需采集称重数据后训练）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // ── 操作按钮 ────────────────────────
                    VStack(spacing: 12) {
                        Button {
                            onDismiss()
                        } label: {
                            Label("继续扫描下一棵", systemImage: "plus.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .padding(.top, 20)
            }
            .navigationTitle("产量估算结果")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 置信度颜色/文字

    private var confidenceColor: Color {
        switch result.confidence {
        case "high":          return .green
        case "medium":        return .orange
        case "manual_review": return .red
        default:              return .gray
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

// MARK: - 子组件

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)
            Divider()
            content()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(highlight ? .subheadline.bold() : .subheadline)
                .foregroundColor(highlight ? .primary : .secondary)
        }
    }
}
