// TransitionPage.swift
// 果树生长动画 - 真实生长过程版

import SwiftUI

struct TransitionPage: View {
    @Binding var isFinished: Bool

    @State private var progress: Double = 0
    @State private var phase: GrowthPhase = .seedling

    private let totalDuration: Double = 5.0

    // 分支节点位置（在主干上的高度比例）
    private let branchNodes: [CGFloat] = [0.25, 0.42, 0.58, 0.72, 0.85]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.95, blue: 0.85),
                    Color(red: 0.90, green: 0.96, blue: 0.88),
                    Color(red: 0.95, green: 0.98, blue: 0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("FruitScanner")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.24, green: 0.42, blue: 0.36))
                    .padding(.top, 40)

                Spacer()

                GeometryReader { geometry in
                    let centerX = geometry.size.width / 2
                    let groundY = geometry.size.height * 0.88

                    ZStack {
                        groundView(groundY: groundY, centerX: centerX)
                        treeView(groundY: groundY, centerX: centerX)
                    }
                }
                .frame(height: 360)

                phaseIndicator
                    .padding(.top, 20)

                progressText
                    .padding(.top, 16)

                Spacer()

                Button("跳过") {
                    isFinished = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.54, green: 0.53, blue: 0.52))
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - 地面
    private func groundView(groundY: CGFloat, centerX: CGFloat) -> some View {
        VStack {
            Spacer()
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.50, green: 0.40, blue: 0.22),
                            Color(red: 0.38, green: 0.30, blue: 0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 120, height: 8)
                .position(x: centerX, y: groundY + 4)
            Spacer(minLength: 8)
        }
    }

    // MARK: - 树整体
    private func treeView(groundY: CGFloat, centerX: CGFloat) -> some View {
        // 主干高度：随着进度从10长到170
        let maxTrunkHeight: CGFloat = 170
        let currentTrunkHeight = maxTrunkHeight * CGFloat(progress / 100)
        let trunkWidth: CGFloat = 8 + (8 * CGFloat(progress / 100))

        // 树冠大小：跟着主干长高而变大
        // 树冠半径最大为主干高度的32%，用pow让初期更慢
        let rawProgress = max(0, (progress - 22) / 58)
        let canopyProgress = min(1.0, pow(rawProgress, 0.7))
        let canopyRadius: CGFloat = canopyProgress * (currentTrunkHeight * 0.32)

        return ZStack {
            // 主干（底部接地）
            if progress > 3 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.36, blue: 0.20),
                                Color(red: 0.38, green: 0.28, blue: 0.15),
                                Color(red: 0.48, green: 0.36, blue: 0.20)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: trunkWidth, height: currentTrunkHeight)
                    .position(x: centerX, y: groundY - currentTrunkHeight / 2)
            }

            // 分支（从主干节点上长出来）
            ForEach(0..<branchNodes.count, id: \.self) { index in
                branchAtNode(
                    nodeIndex: index,
                    nodeHeightRatio: branchNodes[index],
                    currentTrunkHeight: currentTrunkHeight,
                    groundY: groundY,
                    centerX: centerX
                )
            }

            // 树冠（在主干顶端形成，跟着长大）
            if progress > 20 {
                canopyView(
                    centerX: centerX,
                    canopyTopY: groundY - currentTrunkHeight,
                    canopyRadius: canopyRadius,
                    canopyProgress: canopyProgress
                )
            }
        }
    }

    // MARK: - 树冠
    private func canopyView(centerX: CGFloat, canopyTopY: CGFloat, canopyRadius: CGFloat, canopyProgress: CGFloat) -> some View {
        // 树冠中心贴近顶端，不让它太靠下遮住主干
        let canopyCenterY = canopyTopY + canopyRadius * 0.3

        return ZStack {
            // 树冠主体 - 多层圆形叠加形成自然树冠
            // 底层（最深色）- 最大
            Circle()
                .fill(Color(red: 0.25, green: 0.45, blue: 0.32))
                .frame(width: max(0, canopyRadius * 2), height: max(0, canopyRadius * 2))
                .position(x: centerX, y: canopyCenterY + canopyRadius * 0.2)
                .opacity(canopyProgress)

            // 中下层
            Circle()
                .fill(Color(red: 0.32, green: 0.52, blue: 0.38))
                .frame(width: max(0, canopyRadius * 1.6), height: max(0, canopyRadius * 1.6))
                .position(x: centerX, y: canopyCenterY + canopyRadius * 0.05)
                .opacity(canopyProgress)

            // 中层
            Circle()
                .fill(Color(red: 0.40, green: 0.60, blue: 0.45))
                .frame(width: max(0, canopyRadius * 1.1), height: max(0, canopyRadius * 1.1))
                .position(x: centerX - canopyRadius * 0.05, y: canopyCenterY - canopyRadius * 0.1)
                .opacity(canopyProgress)

            // 上层
            Circle()
                .fill(Color(red: 0.48, green: 0.68, blue: 0.52))
                .frame(width: max(0, canopyRadius * 0.6), height: max(0, canopyRadius * 0.6))
                .position(x: centerX - canopyRadius * 0.1, y: canopyCenterY - canopyRadius * 0.25)
                .opacity(canopyProgress)

            // 树冠上的叶子点缀
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * 45 + 20
                let leafRadius = canopyRadius * (0.35 + CGFloat(i % 3) * 0.15)
                let leafX = centerX + leafRadius * CGFloat(cos(angle * .pi / 180))
                let leafY = canopyCenterY + leafRadius * 0.45 * CGFloat(sin(angle * .pi / 180))

                Ellipse()
                    .fill(Color(red: 0.38, green: 0.65, blue: 0.42))
                    .frame(width: 10, height: 6)
                    .rotationEffect(.degrees(angle + 90))
                    .position(x: leafX, y: leafY)
                    .opacity(canopyProgress)
            }

            // 果实（等树冠长大后才出现，分布在整个树冠内）
            if progress > 55 {
                fruitsInCanopy(
                    centerX: centerX,
                    canopyCenterY: canopyCenterY,
                    canopyRadius: canopyRadius,
                    progress: canopyProgress
                )
            }
        }
    }

    // MARK: - 树冠内的果实
    private func fruitsInCanopy(centerX: CGFloat, canopyCenterY: CGFloat, canopyRadius: CGFloat, progress: CGFloat) -> some View {
        // 果实生长进度：等树冠长大到一定程度（progress>60）后才开始
        // 用sqrt让果实出现得更快更集中
        let fruitGrowthProgress = min(1.0, (progress - 0.4) / 0.6)

        return ZStack {
            ForEach(0..<14, id: \.self) { i in
                fruitView(
                    index: i,
                    centerX: centerX,
                    canopyCenterY: canopyCenterY,
                    canopyRadius: canopyRadius,
                    growthProgress: fruitGrowthProgress
                )
            }
        }
    }

    private func fruitView(index: Int, centerX: CGFloat, canopyCenterY: CGFloat, canopyRadius: CGFloat, growthProgress: CGFloat) -> some View {
        // 每个果实有不同的出现时机，逐渐成熟
        let appearDelay = Double(index) * 0.08
        let localProgress = min(1.0, max(0, (growthProgress - appearDelay) / 0.4))

        guard localProgress > 0 else { return AnyView(EmptyView()) }

        // 分布在树冠内，更分散
        let angle = Double(index) * 30 + 5
        let radiusRatio: CGFloat = 0.12 + CGFloat(index % 5) * 0.16
        let radius = canopyRadius * radiusRatio

        let fruitX = centerX + radius * CGFloat(cos(angle * .pi / 180))
        let fruitY = canopyCenterY + radius * 0.45 * CGFloat(sin(angle * .pi / 180))

        // 果实大小：逐渐变大（10->22）
        let baseSize: CGFloat = 10 + CGFloat(index % 4) * 3
        let fruitSize: CGFloat = baseSize * localProgress

        // 果实颜色：从绿到红，逐渐成熟
        let redComponent: Double = 0.30 + 0.60 * localProgress
        let greenComponent: Double = 0.75 - 0.45 * localProgress

        return AnyView(
            ZStack {
                Circle()
                    .fill(Color(red: redComponent, green: greenComponent, blue: 0.20))
                    .frame(width: fruitSize, height: fruitSize)

                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: fruitSize * 0.3, height: fruitSize * 0.3)
                    .offset(x: -fruitSize * 0.15, y: -fruitSize * 0.15)
            }
            .position(x: fruitX, y: fruitY)
        )
    }

    // MARK: - 分支
    private func branchAtNode(nodeIndex: Int, nodeHeightRatio: CGFloat, currentTrunkHeight: CGFloat, groundY: CGFloat, centerX: CGFloat) -> some View {
        // 分支出现时机：主干必须长过这个节点位置
        let nodeAppearProgress = nodeHeightRatio * 100

        guard progress > nodeAppearProgress else {
            return AnyView(EmptyView())
        }

        // 分支生长进度
        let branchGrowthDuration: Double = 12
        let branchProgress = min(1.0, (progress - nodeAppearProgress) / branchGrowthDuration)

        guard branchProgress > 0.05 else {
            return AnyView(EmptyView())
        }

        // 分支参数
        let isLeft = nodeIndex % 2 == 0
        let baseAngle: CGFloat = isLeft ? -48 : 48
        let baseLength: CGFloat = 32 + CGFloat(nodeIndex / 2) * 10

        let currentLength = baseLength * branchProgress

        // 分支起点
        let nodeY = groundY - currentTrunkHeight * nodeHeightRatio

        // 分支终点
        let angleRad = Double(baseAngle) * .pi / 180
        let endX: CGFloat
        if isLeft {
            endX = centerX - currentLength * CGFloat(cos(angleRad))
        } else {
            endX = centerX + currentLength * CGFloat(cos(angleRad))
        }
        let endY = nodeY - currentLength * CGFloat(sin(abs(angleRad)))

        // 叶子生长进度
        let leafProgress = min(1.0, (branchProgress - 0.4) / 0.4)

        return AnyView(
            ZStack {
                // 分支（树枝）
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: nodeY))
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(
                    Color(red: 0.42, green: 0.32, blue: 0.18),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                // 分支上的叶子（沿分支从基部向尖端生长）
                if leafProgress > 0 {
                    ForEach(0..<3, id: \.self) { leafIndex in
                        let leafFraction = CGFloat(leafIndex + 1) / 4.0
                        let leafX = centerX + (endX - centerX) * leafFraction
                        let leafY = nodeY + (endY - nodeY) * leafFraction

                        Ellipse()
                            .fill(Color(red: 0.38, green: 0.68, blue: 0.42))
                            .frame(width: 10, height: 6)
                            .rotationEffect(.degrees(baseAngle + (isLeft ? -50 : 50)))
                            .position(x: leafX, y: leafY)
                            .opacity(leafProgress)
                    }
                }
            }
        )
    }

    // MARK: - 阶段指示器
    private var phaseIndicator: some View {
        HStack(spacing: 20) {
            ForEach(GrowthPhase.allCases, id: \.self) { p in
                VStack(spacing: 4) {
                    Circle()
                        .fill(phase == p ? Color(red: 0.24, green: 0.42, blue: 0.36) : Color(red: 0.88, green: 0.86, blue: 0.84))
                        .frame(width: 10, height: 10)

                    if phase == p {
                        Circle()
                            .stroke(Color(red: 0.24, green: 0.42, blue: 0.36).opacity(0.4), lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
        )
    }

    private var progressText: some View {
        Text(phase.label)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(Color(red: 0.30, green: 0.29, blue: 0.28))
    }

    // MARK: - 动画启动
    private func startAnimation() {
        let updateInterval: Double = 0.03
        let incrementPerTick: Double = 100.0 / (totalDuration / updateInterval)

        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            progress += incrementPerTick
            updatePhase()

            if progress >= 100 {
                progress = 100
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFinished = true
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 1.0) {
            isFinished = true
        }
    }

    private func updatePhase() {
        if progress < 20 {
            phase = .seedling
        } else if progress < 45 {
            phase = .sprouting
        } else if progress < 70 {
            phase = .flowering
        } else {
            phase = .fruiting
        }
    }
}

// MARK: - 生长阶段
enum GrowthPhase: CaseIterable {
    case seedling, sprouting, flowering, fruiting

    var label: String {
        switch self {
        case .seedling: return "种子萌发"
        case .sprouting: return "枝叶生长"
        case .flowering: return "繁花似锦"
        case .fruiting: return "果实成熟"
        }
    }
}

#Preview {
    TransitionPage(isFinished: .constant(false))
}