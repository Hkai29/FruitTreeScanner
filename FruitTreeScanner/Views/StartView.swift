// StartView.swift
// 新建扫描 - 5步引导式设计

import SwiftUI

struct StartView: View {
    @State private var currentStep = 1
    @State private var treeID = ""
    @State private var selectedPlotId: UUID?
    @State private var season: Season = .mature
    @State private var selectedTagIds: Set<UUID> = []
    @State private var showScan = false
    @State private var showPlotEdit = false
    @State private var showTagEdit = false

    @StateObject private var tagStore = TagStore.shared
    @StateObject private var gps = GPSRecorder()
    @Environment(\.dismiss) var dismiss

    private let totalSteps = 5

    private var canGoNext: Bool {
        switch currentStep {
        case 1: return !treeID.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var selectedPlot: Plot? {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }
    }

    private var selectedTags: [GroupTag] {
        tagStore.tags.filter { selectedTagIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            // 暗色渐变背景
            Design.Colors.darkGradient
                .ignoresSafeArea()

            // 手指光效
            FingerGlowOverlay()

            VStack(spacing: 0) {
                // 顶部导航
                topNavigation

                // 进度指示器
                StepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.vertical, Design.Space.lg)

                // 内容区域 - 带翻页动画
                GeometryReader { geometry in
                    ZStack {
                        stepContent
                            .frame(width: geometry.size.width)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.horizontal, Design.Space.lg)

                Spacer()

                // 底部导航
                StepNavigationBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    canGoBack: currentStep > 1,
                    canGoNext: canGoNext,
                    onBack: { withAnimation(.easeInOut(duration: 0.3)) { if currentStep > 1 { currentStep -= 1 } } },
                    onNext: {
                        if currentStep < totalSteps {
                            withAnimation(.easeInOut(duration: 0.3)) { currentStep += 1 }
                        } else {
                            showScan = true
                        }
                    }
                )
                .padding(.horizontal, Design.Space.lg)
                .padding(.bottom, Design.Space.lg)
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView(
                treeID: treeID.trimmingCharacters(in: .whitespaces),
                nVisual: nil,
                season: season,
                gps: gps
            )
        }
        .sheet(isPresented: $showPlotEdit) {
            PlotEditView(onSave: { newPlot in
                TagStore.shared.addPlot(name: newPlot.name, colorHex: newPlot.colorHex)
            })
        }
        .sheet(isPresented: $showTagEdit) {
            TagEditView(onSave: { newTag in
                TagStore.shared.addTag(name: newTag.name, colorHex: newTag.colorHex)
            })
        }
    }

    // MARK: - Top Navigation
    private var topNavigation: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Design.Colors.harvest)

            Spacer()

            Text("新建扫描")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            // 占位，保持标题居中
            Button("取消") { }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.clear)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
    }

    // MARK: - Step Content
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1:
            Step1_IDEntry(treeID: $treeID)
        case 2:
            Step2_PlotSelection(
                plots: tagStore.plots,
                selectedPlotId: $selectedPlotId,
                onAddPlot: { showPlotEdit = true }
            )
        case 3:
            Step3_SeasonSelection(season: $season)
        case 4:
            Step4_TagSelection(
                tags: tagStore.tags,
                selectedTagIds: $selectedTagIds,
                onAddTag: { showTagEdit = true }
            )
        case 5:
            Step5_Confirmation(
                treeID: treeID,
                plot: selectedPlot,
                season: season,
                tags: selectedTags,
                gps: gps
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Step Progress View
struct StepProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    private let labels = ["编号", "地块", "季节", "标签", "确认"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...totalSteps, id: \.self) { step in
                // 圆点
                Circle()
                    .fill(step <= currentStep ? Design.Colors.forest : Color(hex: "E5E5EA"))
                    .frame(width: step == currentStep ? 12 : 10, height: step == currentStep ? 12 : 10)
                    .overlay {
                        if step == currentStep {
                            Circle()
                                .stroke(Design.Colors.forest.opacity(0.3), lineWidth: 3)
                                .frame(width: 20, height: 20)
                        }
                    }

                // 连接线
                if step < totalSteps {
                    Rectangle()
                        .fill(step < currentStep ? Design.Colors.forest : Color(hex: "E5E5EA"))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, Design.Space.xl)

        // 标签
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Text(labels[index])
                    .font(.system(size: 11, weight: index + 1 == currentStep ? .semibold : .regular))
                    .foregroundColor(index + 1 <= currentStep ? Design.Colors.forest : Color(hex: "8E8E93"))
                    .frame(width: 60)

                if index < totalSteps - 1 {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.top, Design.Space.sm)
    }
}

// MARK: - Step Navigation Bar
struct StepNavigationBar: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let canGoNext: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var isLastStep: Bool { currentStep == totalSteps }

    var body: some View {
        HStack {
            // 上一步按钮
            if canGoBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("上一步")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(Design.Colors.harvest)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            // 步骤指示
            Text("\(currentStep) / \(totalSteps)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            // 下一步/开始按钮
            Button(action: onNext) {
                HStack(spacing: 4) {
                    Text(isLastStep ? "开始扫描" : "下一步")
                        .font(.system(size: 15, weight: .semibold))
                    if !isLastStep {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canGoNext ? Design.Colors.forest : Design.Colors.slate.opacity(0.5))
                )
            }
            .disabled(!canGoNext)
        }
        .padding(.vertical, Design.Space.sm)
    }
}

// MARK: - Step 1: ID Entry
struct Step1_IDEntry: View {
    @Binding var treeID: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            // 标题
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Image(systemName: "number")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)

                Text("输入果树编号")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("为扫描的果树设置唯一编号")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            // 输入卡片
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Text("果树编号")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                TextField("例：T001", text: $treeID)
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(Design.Space.md)
                    .background(Design.Colors.Dark.bgElevated)
                    .cornerRadius(12)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
            }
            .padding(Design.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )

            // 提示
            HStack(spacing: Design.Space.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.harvest)
                Text("提示：编号将用于后续数据关联，建议使用易于识别的格式")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, Design.Space.md)
    }
}

// MARK: - Step 2: Plot Selection
struct Step2_PlotSelection: View {
    let plots: [Plot]
    @Binding var selectedPlotId: UUID?
    let onAddPlot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            // 标题
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Image(systemName: "map.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)

                Text("选择地块")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("将果树分配到对应的种植区域")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            // 地块网格
            if plots.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Design.Space.md),
                    GridItem(.flexible(), spacing: Design.Space.md)
                ], spacing: Design.Space.md) {
                    ForEach(plots) { plot in
                        PlotSelectionCard(
                            plot: plot,
                            isSelected: selectedPlotId == plot.id
                        ) {
                            selectedPlotId = plot.id
                        }
                    }

                    // 添加新地块按钮
                    Button(action: onAddPlot) {
                        VStack(spacing: Design.Space.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Design.Colors.forest.opacity(0.6))

                            Text("添加新地块")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Design.Space.lg)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Design.Colors.forest.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, Design.Space.md)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(Design.Colors.slate.opacity(0.3))

            Text("暂无地块")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Button(action: onAddPlot) {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: "plus")
                    Text("创建第一个地块")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.harvest)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Design.Colors.forest, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.xl)
    }
}

struct PlotSelectionCard: View {
    let plot: Plot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Design.Space.sm) {
                Circle()
                    .fill(Color(hex: plot.colorHex))
                    .frame(width: 48, height: 48)
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 3)
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                Text(plot.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? Design.Colors.forest : Color(hex: "1C1C1E"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Design.Colors.forest.opacity(0.1) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Design.Colors.forest : Color(hex: "E5E5EA"), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }
}

// MARK: - Step 3: Season Selection
struct Step3_SeasonSelection: View {
    @Binding var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            // 标题
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Image(systemName: season == .mature ? "apple.logo" : "leaf.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)

                Text("选择扫描季节")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("季节影响产量估算的计算方法")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            // 季节选项
            HStack(spacing: Design.Space.md) {
                SeasonCard(
                    icon: "apple.logo",
                    title: "成熟期",
                    subtitle: "双路线估算",
                    description: "同时使用果实体积法和冠层体积法",
                    isSelected: season == .mature,
                    color: Design.Colors.forest
                ) {
                    season = .mature
                }

                SeasonCard(
                    icon: "leaf.fill",
                    title: "非成熟期",
                    subtitle: "冠层体积法",
                    description: "仅使用冠层体积法估算",
                    isSelected: season == .off,
                    color: Design.Colors.harvest
                ) {
                    season = .off
                }
            }

            // 提示
            HStack(spacing: Design.Space.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.info)
                Text("成熟期估算结果更精确，但需要更多采集时间")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, Design.Space.md)
    }
}

struct SeasonCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Design.Space.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color.opacity(0.15) : Color(hex: "F2F2F7"))
                        .frame(width: 64, height: 64)

                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(isSelected ? color : Color(hex: "8E8E93"))
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "636366"))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8E8E93"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Space.sm)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? color : Color(hex: "E5E5EA"), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }
}

// MARK: - Step 4: Tag Selection
struct Step4_TagSelection: View {
    let tags: [GroupTag]
    @Binding var selectedTagIds: Set<UUID>
    let onAddTag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            // 标题
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)

                Text("添加标签")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("为果树添加分类标签（可选）")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            // 标签网格
            if tags.isEmpty {
                emptyState
            } else {
                FlowLayout(spacing: Design.Space.sm) {
                    ForEach(tags) { tag in
                        TagChip(
                            tag: tag,
                            isSelected: selectedTagIds.contains(tag.id)
                        ) {
                            if selectedTagIds.contains(tag.id) {
                                selectedTagIds.remove(tag.id)
                            } else {
                                selectedTagIds.insert(tag.id)
                            }
                        }
                    }

                    // 添加标签按钮
                    Button(action: onAddTag) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("添加标签")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, Design.Space.sm)
                        .background(
                            Capsule()
                                .strokeBorder(Design.Colors.forest, lineWidth: 1)
                        )
                    }
                }
            }

            // 已选标签
            if !selectedTagIds.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    Text("已选标签")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    HStack(spacing: Design.Space.xs) {
                        ForEach(selectedTags, id: \.id) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, Design.Space.sm)
                            .padding(.vertical, Design.Space.xs)
                            .background(
                                Capsule()
                                    .fill(Design.Colors.forest.opacity(0.1))
                            )
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, Design.Space.md)
    }

    private var selectedTags: [GroupTag] {
        tags.filter { selectedTagIds.contains($0.id) }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundColor(Design.Colors.slate.opacity(0.3))

            Text("暂无标签")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Button(action: onAddTag) {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: "plus")
                    Text("创建第一个标签")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.harvest)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.xl)
    }
}

struct TagChip: View {
    let tag: GroupTag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .font(.system(size: 13, weight: .medium))

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundColor(isSelected ? .white : Color(hex: "1C1C1E"))
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.forest : Color(hex: "F2F2F7"))
            )
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

// MARK: - Step 5: Confirmation
struct Step5_Confirmation: View {
    let treeID: String
    let plot: Plot?
    let season: Season
    let tags: [GroupTag]
    let gps: GPSRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            // 标题
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)

                Text("确认配置")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("请确认以下配置信息")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            // 配置卡片
            VStack(spacing: Design.Space.md) {
                // 编号
                ConfirmationRow(icon: "number", label: "编号", value: treeID)

                Divider()

                // 地块
                ConfirmationRow(
                    icon: "map.fill",
                    label: "地块",
                    value: plot?.name ?? "未分配",
                    valueColor: plot != nil ? Design.Colors.forest : Color(hex: "8E8E93")
                )

                Divider()

                // 季节
                ConfirmationRow(
                    icon: season == .mature ? "apple.logo" : "leaf.fill",
                    label: "季节",
                    value: season == .mature ? "成熟期（双路线）" : "非成熟期（冠层体积）",
                    valueColor: Design.Colors.harvest
                )

                Divider()

                // 标签
                HStack(spacing: Design.Space.md) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Design.Colors.harvest)
                        .frame(width: 24)

                    Text("标签")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "636366"))

                    Spacer()

                    if tags.isEmpty {
                        Text("无")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "8E8E93"))
                    } else {
                        HStack(spacing: Design.Space.xs) {
                            ForEach(tags.prefix(3)) { tag in
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "1C1C1E"))
                            }
                            if tags.count > 3 {
                                Text("+\(tags.count - 3)")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "8E8E93"))
                            }
                        }
                    }
                }

                Divider()

                // GPS
                HStack(spacing: Design.Space.md) {
                    Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                        .font(.system(size: 16))
                        .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.slate)
                        .frame(width: 24)

                    Text("GPS")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "636366"))

                    Spacer()

                    Text(gps.isAvailable ? "已获取" : "获取中...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(gps.isAvailable ? Design.Colors.forest : Color(hex: "8E8E93"))
                }
            }
            .padding(Design.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )

            Spacer()
        }
        .padding(.vertical, Design.Space.md)
    }
}

struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Color(hex: "1C1C1E")

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "636366"))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

#Preview {
    StartView()
}