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
            .navigationTitle(L10n.VarietyDatabase.editTitle(fruitName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var headerSection: some View {
        VStack(spacing: Design.Space.sm) {
            ZStack {
                Circle()
                    .fill(Design.Colors.harvest.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Design.Colors.harvest)
                    .accessibilityHidden(true)
            }

            Text(L10n.VarietyDatabase.editImpact(fruitName))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Design.Space.md)
    }

    private var diameterSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: L10n.VarietyDatabase.sizeSection, icon: "ruler")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: L10n.VarietyDatabase.minimumDiameter,
                    value: $diamMin,
                    range: 0.005...0.05,
                    step: 0.001,
                    displayValue: VarietyParameterFormatter.millimeters(diamMin)
                )

                VarietySliderRow(
                    title: L10n.VarietyDatabase.maximumDiameter,
                    value: $diamMax,
                    range: 0.05...0.30,
                    step: 0.005,
                    displayValue: VarietyParameterFormatter.millimeters(diamMax)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: L10n.VarietyDatabase.weightDensitySection, icon: "scalemass")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: L10n.VarietyDatabase.averageWeight,
                    value: $averageWeightG,
                    range: 1...2000,
                    step: 1,
                    displayValue: VarietyParameterFormatter.grams(averageWeightG)
                )

                VarietySliderRow(
                    title: L10n.VarietyDatabase.density,
                    value: $density,
                    range: 0.5...1.0,
                    step: 0.01,
                    displayValue: VarietyParameterFormatter.decimal(density, fractionDigits: 2)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: L10n.VarietyDatabase.thresholdsSection, icon: "circle.hexagongrid")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: L10n.VarietyDatabase.sphericityThreshold,
                    value: $sphericityThreshold,
                    range: 0.2...0.8,
                    step: 0.01,
                    displayValue: VarietyParameterFormatter.decimal(sphericityThreshold, fractionDigits: 2)
                )
            }
            .padding(Design.Space.md)
            .background(sectionBackground)
        }
    }

    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            VarietySectionHeader(title: L10n.VarietyDatabase.clusteringSection, icon: "circle.grid.3x3")

            VStack(spacing: Design.Space.md) {
                VarietySliderRow(
                    title: L10n.VarietyDatabase.clusterRadius,
                    value: $clusterEps,
                    range: 0.02...0.15,
                    step: 0.005,
                    displayValue: VarietyParameterFormatter.meters(clusterEps)
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

    private var fruitName: String {
        L10n.Fruit.name(for: category)
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
