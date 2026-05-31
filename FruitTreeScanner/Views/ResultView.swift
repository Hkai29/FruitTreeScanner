// ResultView.swift
// 扫描完成后的产量估算结果页 - 自然有机风格

import SwiftUI

struct ResultView: View {
    let treeID: String
    let result: YieldResult
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void

    @ObservedObject private var tagStore = TagStore.shared
    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus = .scanned

    private var selectedPlotName: String {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }?.name ?? "选择地块"
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()
                .task {
                    if let existing = tagStore.getAssignment(treeId: treeID) {
                        selectedPlotId = existing.plotId
                        selectedTagIds = Set(existing.tagIds)
                        selectedStatus = existing.status == .reviewing ? .scanned : existing.status
                    }
                }

            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("扫描结果")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Design.Colors.Dark.textSecondary)
                                Text("树 \(treeID)")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(Design.Colors.Dark.textPrimary)
                            }
                            Spacer()
                            ConfidenceBadge(label: confidenceLabel, color: confidenceColor)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.1f", result.yieldFinalKg))
                                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                                .foregroundColor(confidenceColor)
                            Text("kg")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                        }

                        HStack(spacing: 8) {
                            ResultSummaryPill(label: "果实", value: "\(result.nLidar)")
                            ResultSummaryPill(label: "点云", value: result.pointCloudSize > 0 ? "\(result.pointCloudSize)" : "--")
                            ResultSummaryPill(label: "方法", value: result.methodUsed.isEmpty ? "估算" : result.methodUsed)
                        }

                        if !result.note.isEmpty {
                            Text(result.note)
                                .font(.system(size: 12))
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .resultSurface(cornerRadius: 14)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // 路线B
                    if result.nLidar > 0 {
                        ResultSectionCard(
                            title: "果实体积法",
                            icon: "circle.grid.3x3",
                            color: Design.Colors.forest
                        ) {
                            ResultInfoRow(label: "校正后果实数", value: "\(result.nLidar) 个")
                            if let nV = result.nVisual {
                                ResultInfoRow(label: "视觉计数", value: "\(nV) 个")
                            }
                            ResultInfoRow(label: "总校正系数", value: String(format: "×%.2f", result.correctionK))
                            ResultInfoRow(label: "可见部分重量", value: String(format: "%.2f kg", result.yieldBVisibleKg))
                            ResultInfoRow(label: "校正后重量", value: String(format: "%.2f kg", result.yieldBCorrectedKg), highlight: true)
                            if result.meanDiameterCm > 0 {
                                ResultInfoRow(label: "实测平均直径", value: String(format: "%.1f cm", result.meanDiameterCm))
                            }
                        }
                    }

                    // 路线A
                    ResultSectionCard(
                        title: "冠层体积法",
                        icon: "tree.fill",
                        color: Design.Colors.harvest
                    ) {
                        if let yA = result.yieldAKg {
                            ResultInfoRow(label: "冠层回归产量", value: String(format: "%.2f kg", yA), highlight: true)
                            ResultInfoRow(label: "冠层体积", value: String(format: "%.3f m³", result.crownVolM3))
                            ResultInfoRow(label: "树高", value: String(format: "%.2f m", result.treeHeightM))
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(Design.Colors.Dark.textSecondary)
                                Text("路线A模型未训练，需采集称重数据后训练")
                                    .font(.system(size: 13))
                                    .foregroundColor(Design.Colors.Dark.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                    }

                    // 算法参数（论文可复现性）
                    if result.clusterEps > 0 || result.pointCloudSize > 0 {
                        ResultSectionCard(
                            title: "算法参数",
                            icon: "slider.horizontal.3",
                            color: Color(hex: "8E8E93")
                        ) {
                            if !result.fruitCategory.isEmpty {
                                ResultInfoRow(label: "水果类别", value: result.fruitCategory)
                            }
                            if result.pointCloudSize > 0 {
                                ResultInfoRow(label: "点云大小", value: "\(result.pointCloudSize) 点")
                            }
                            if result.clusterEps > 0 {
                                ResultInfoRow(label: "DBSCAN Eps", value: String(format: "%.3f m", result.clusterEps))
                            }
                            if result.clusterMinPoints > 0 {
                                ResultInfoRow(label: "DBSCAN MinPts", value: "\(result.clusterMinPoints)")
                            }
                            if !result.colorFilterDesc.isEmpty {
                                ResultInfoRow(label: "颜色过滤", value: result.colorFilterDesc)
                            }
                            if result.occlusionK != 1.0 {
                                ResultInfoRow(label: "遮挡校正 K", value: String(format: "%.2f", result.occlusionK))
                            }
                            ResultInfoRow(label: "估算方法", value: result.methodUsed.isEmpty ? "N/A" : result.methodUsed)
                        }
                    }

                    // 快速标记
                    VStack(alignment: .leading, spacing: 16) {
                        Text("快速标记")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.textPrimary)

                        // Plot selection
                        Menu {
                            Button("无地块") {
                                selectedPlotId = nil
                            }
                            ForEach(tagStore.plots) { plot in
                                Button(plot.name) {
                                    selectedPlotId = plot.id
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "map")
                                    .foregroundColor(Design.Colors.earth)
                                Text(selectedPlotName)
                                    .font(.system(size: 14))
                                    .foregroundColor(Design.Colors.Dark.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(Design.Colors.Dark.textSecondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Design.Colors.Dark.bgElevated)
                            )
                        }
                        .buttonStyle(.plain)

                        // Tag selection
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tagStore.tags) { tag in
                                    Button {
                                        if selectedTagIds.contains(tag.id) {
                                            selectedTagIds.remove(tag.id)
                                        } else {
                                            selectedTagIds.insert(tag.id)
                                        }
                                    } label: {
                                        Text(tag.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(selectedTagIds.contains(tag.id)
                                                      ? Color(hex: tag.colorHex)
                                                          : Design.Colors.Dark.bgElevated)
                                            )
                                            .foregroundColor(selectedTagIds.contains(tag.id) ? .white : Design.Colors.Dark.textPrimary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Status selection
                        HStack(spacing: 8) {
                            ForEach(ScanStatus.allCases, id: \.self) { status in
                                Button {
                                    selectedStatus = status
                                } label: {
                                    Text(status.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedStatus == status
                                                      ? statusColor(for: status)
                                                      : Design.Colors.Dark.bgElevated)
                                        )
                                        .foregroundColor(selectedStatus == status ? .white : Design.Colors.Dark.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Save button
                        Button {
                            tagStore.createOrUpdateAssignment(
                                treeId: treeID,
                                plotId: selectedPlotId,
                                tagIds: Array(selectedTagIds),
                                status: selectedStatus
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14))
                                Text("保存标记")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Design.Colors.forest)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Design.Colors.Dark.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button(action: onDismiss) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("继续扫描下一棵")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Design.Colors.forest
                            )
                            .cornerRadius(10)
                        }

                        Button {
                            onDismissToHome()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 16))
                                Text("返回主界面")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(Design.Colors.Dark.textSecondary)
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
        case "high":          return Design.Colors.forest
        case "medium":        return Design.Colors.harvest
        case "manual_review": return Design.Colors.apple
        default:              return Design.Colors.slate
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

    private func statusColor(for status: ScanStatus) -> Color {
        switch status {
        case .notScanned: return .gray
        case .scanned: return Design.Colors.earth
        case .reviewing: return Design.Colors.harvest
        case .completed: return Design.Colors.forest
        }
    }
}

// MARK: - 结果卡片
struct ResultSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()
                .background(Design.Colors.Dark.glassBorder)

            content()
        }
        .padding(16)
        .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Design.Colors.Dark.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
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
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: highlight ? .semibold : .medium, design: .monospaced))
                .foregroundColor(highlight ? Design.Colors.forest : Design.Colors.Dark.textPrimary)
        }
    }
}

private struct ConfidenceBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }
}

private struct ResultSummaryPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Design.Colors.Dark.bgElevated.opacity(0.7))
        .cornerRadius(8)
    }
}

private extension View {
    func resultSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Design.Colors.Dark.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }
}
