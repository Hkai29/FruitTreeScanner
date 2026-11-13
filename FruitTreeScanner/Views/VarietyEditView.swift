// VarietyEditView.swift
// 品种参数编辑页。
//
// 编辑采用“草稿—提交”模型：
//   1. 打开时把当前参数复制为基线（baseline）。
//   2. 滑杆只改本地草稿，不写存储。
//   3. 保存时把（基线, 草稿）一起交给 FruitParametersStore 合并；
//      如果基线已被别处改动，提交被拒绝并回退到最新值，本地草稿随之重置。
//   4. 取消只丢弃草稿，不产生任何写入。

import SwiftUI

struct VarietyEditView: View {
    let category: FruitCategory
    private let onCommit: (FruitVarietyParams, FruitVarietyParams) -> FruitParametersStore.EditCommitResult
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var baseline: FruitVarietyParams
    @State private var diamMin: Float
    @State private var diamMax: Float
    @State private var averageWeightG: Float
    @State private var density: Float
    @State private var clusterEps: Float
    @State private var sphericityThreshold: Float
    @State private var showResetConfirm = false
    @State private var showsParameterConflict = false

    init(category: FruitCategory, params: FruitVarietyParams, onSave: @escaping (FruitVarietyParams) -> Void, onReset: @escaping () -> Void) {
        self.init(category: category, params: params, onCommit: { _, edited in
            onSave(edited)
            return .accepted
        }, onReset: onReset)
    }

    init(category: FruitCategory, params: FruitVarietyParams,
         onCommit: @escaping (FruitVarietyParams, FruitVarietyParams) -> FruitParametersStore.EditCommitResult,
         onReset: @escaping () -> Void) {
        self.category = category
        self.onCommit = onCommit
        self.onReset = onReset
        _baseline = State(initialValue: params)
        _diamMin = State(initialValue: params.diamMin)
        _diamMax = State(initialValue: params.diamMax)
        _averageWeightG = State(initialValue: params.averageWeightG)
        _density = State(initialValue: params.density)
        _clusterEps = State(initialValue: params.clusterEps)
        _sphericityThreshold = State(initialValue: params.sphericityThreshold)
    }

    private var normalizedParams: FruitVarietyParams {
        var newParams = baseline
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
                Design.Colors.Workspace.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if showsParameterConflict {
                        Text(L10n.VarietyDatabase.parameterConflict)
                            .font(.footnote)
                            .foregroundColor(Design.Colors.Workspace.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                Design.Colors.Workspace.attentionSoft,
                                in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    impactNote
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 2)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            diameterSection
                            weightSection
                            qualitySection
                            algorithmSection
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(L10n.VarietyDatabase.editTitle(fruitName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel, action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save, action: saveAndDismiss)
                        .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label(L10n.VarietyDatabase.resetDefault, systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .alert(L10n.VarietyDatabase.resetParameterTitle, isPresented: $showResetConfirm) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.VarietyDatabase.reset, role: .destructive, action: resetAndDismiss)
            } message: {
                Text(L10n.VarietyDatabase.resetParameterMessage)
            }
        }
        .onChange(of: diamMin, perform: clampMaxDiameter)
        .onChange(of: diamMax, perform: clampMinDiameter)
    }

    // MARK: - 分组

    private var impactNote: some View {
        Text(L10n.VarietyDatabase.editImpact(fruitName))
            .font(.subheadline)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private var diameterSection: some View {
        parameterGroup(title: L10n.VarietyDatabase.sizeSection, icon: "ruler") {
            VarietySliderRow(
                title: L10n.VarietyDatabase.minimumDiameter,
                value: $diamMin,
                range: 0.005...0.05,
                step: 0.001,
                displayValue: VarietyParameterFormatter.millimeters(diamMin)
            )

            DividerLine()

            VarietySliderRow(
                title: L10n.VarietyDatabase.maximumDiameter,
                value: $diamMax,
                range: 0.05...0.30,
                step: 0.005,
                displayValue: VarietyParameterFormatter.millimeters(diamMax)
            )
        }
    }

    private var weightSection: some View {
        parameterGroup(title: L10n.VarietyDatabase.weightDensitySection, icon: "scalemass") {
            VarietySliderRow(
                title: L10n.VarietyDatabase.averageWeight,
                value: $averageWeightG,
                range: 1...2000,
                step: 1,
                displayValue: VarietyParameterFormatter.grams(averageWeightG)
            )

            DividerLine()

            VarietySliderRow(
                title: L10n.VarietyDatabase.density,
                value: $density,
                range: 0.5...1.0,
                step: 0.01,
                displayValue: VarietyParameterFormatter.decimal(density, fractionDigits: 2)
            )
        }
    }

    private var qualitySection: some View {
        parameterGroup(title: L10n.VarietyDatabase.thresholdsSection, icon: "circle.hexagongrid") {
            VarietySliderRow(
                title: L10n.VarietyDatabase.sphericityThreshold,
                value: $sphericityThreshold,
                range: 0.2...0.8,
                step: 0.01,
                displayValue: VarietyParameterFormatter.decimal(sphericityThreshold, fractionDigits: 2)
            )
        }
    }

    private var algorithmSection: some View {
        parameterGroup(title: L10n.VarietyDatabase.clusteringSection, icon: "circle.grid.3x3") {
            VarietySliderRow(
                title: L10n.VarietyDatabase.clusterRadius,
                value: $clusterEps,
                range: 0.02...0.15,
                step: 0.005,
                displayValue: VarietyParameterFormatter.meters(clusterEps)
            )
        }
    }

    /// 一组参数：小标签 + 列表组，组内以发丝线分隔。
    private func parameterGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VarietySectionHeader(title: title, icon: icon)

            InstrumentRowGroup {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - 提交

    private var fruitName: String {
        L10n.Fruit.name(for: category)
    }

    private func saveAndDismiss() {
        switch onCommit(baseline, normalizedParams) {
        case .accepted:
            dismiss()
        case .conflict(let current):
            baseline = current
            diamMin = current.diamMin
            diamMax = current.diamMax
            averageWeightG = current.averageWeightG
            density = current.density
            clusterEps = current.clusterEps
            sphericityThreshold = current.sphericityThreshold
            showsParameterConflict = true
        }
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
