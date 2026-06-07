import SwiftUI

struct VarietyEditView: View {
    let category: FruitCategory
    let params: FruitVarietyParams
    let onSave: (FruitVarietyParams) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var diamMin: Float
    @State private var diamMax: Float
    @State private var averageWeightG: Float
    @State private var density: Float
    @State private var clusterEps: Float
    @State private var sphericityThreshold: Float
    @State private var showResetConfirm = false

    init(category: FruitCategory, params: FruitVarietyParams, onSave: @escaping (FruitVarietyParams) -> Void, onReset: @escaping () -> Void) {
        self.category = category
        self.params = params
        self.onSave = onSave
        self.onReset = onReset
        _diamMin = State(initialValue: params.diamMin)
        _diamMax = State(initialValue: params.diamMax)
        _averageWeightG = State(initialValue: params.averageWeightG)
        _density = State(initialValue: params.density)
        _clusterEps = State(initialValue: params.clusterEps)
        _sphericityThreshold = State(initialValue: params.sphericityThreshold)
    }

    private var normalizedParams: FruitVarietyParams {
        var newParams = params
        let minDiameter = min(diamMin, diamMax)
        let maxDiameter = max(diamMin, diamMax)
        newParams.diamMin = minDiameter
        newParams.diamMax = maxDiameter
        newParams.averageWeightG = averageWeightG
        newParams.density = density
        newParams.clusterEps = clusterEps
        newParams.sphericityThreshold = sphericityThreshold
        return newParams
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        headerSection
                        diameterSection
                        weightSection
                        qualitySection
                        algorithmSection
                    }
                    .padding(Design.Space.md)
                }
            }
            .navigationTitle("编辑 \(category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveAndDismiss)
                        .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("重置为默认值", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .alert("重置参数", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive, action: resetAndDismiss)
            } message: {
                Text("确定要重置为默认值吗？")
            }
        }
        .onChange(of: diamMin, perform: clampMaxDiameter)
        .onChange(of: diamMax, perform: clampMinDiameter)
    }

    private var headerSection: some View {
        VStack(spacing: Design.Space.sm) {
            ZStack {
                Circle()
                    .fill(Design.Colors.harvest.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)
            }

            Text("调整参数会影响 \(category.displayName) 的检测和估算结果")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Design.Space.md)
    }

    private var diameterSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: "果实尺寸", icon: "ruler")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: "最小直径",
                    value: $diamMin,
                    range: 0.005...0.05,
                    step: 0.001,
                    unit: "mm",
                    displayValue: "\(Int(diamMin * 1000))"
                )

                VarietySliderRow(
                    title: "最大直径",
                    value: $diamMax,
                    range: 0.05...0.30,
                    step: 0.005,
                    unit: "mm",
                    displayValue: "\(Int(diamMax * 1000))"
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: "重量与密度", icon: "scalemass")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: "平均单果重量",
                    value: $averageWeightG,
                    range: 1...2000,
                    step: 1,
                    unit: "g",
                    displayValue: "\(Int(averageWeightG))"
                )

                VarietySliderRow(
                    title: "密度",
                    value: $density,
                    range: 0.5...1.0,
                    step: 0.01,
                    unit: "",
                    displayValue: String(format: "%.2f", density)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: "检测阈值", icon: "circle.hexagongrid")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: "球形度阈值",
                    value: $sphericityThreshold,
                    range: 0.2...0.8,
                    step: 0.01,
                    unit: "",
                    displayValue: String(format: "%.2f", sphericityThreshold)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: "聚类参数", icon: "circle.grid.3x3")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: "聚类半径 (Eps)",
                    value: $clusterEps,
                    range: 0.02...0.15,
                    step: 0.005,
                    unit: "m",
                    displayValue: String(format: "%.3f", clusterEps)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.medium)
            .fill(Design.Colors.Dark.bgSurface)
    }

    private func saveAndDismiss() {
        onSave(normalizedParams)
        dismiss()
    }

    private func resetAndDismiss() {
        onReset()
        dismiss()
    }

    private func clampMaxDiameter(_ value: Float) {
        if value > diamMax {
            diamMax = value
        }
    }

    private func clampMinDiameter(_ value: Float) {
        if value < diamMin {
            diamMin = value
        }
    }
}
