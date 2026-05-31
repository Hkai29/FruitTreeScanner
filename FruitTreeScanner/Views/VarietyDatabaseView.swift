import SwiftUI

struct VarietyDatabaseView: View {
    @ObservedObject private var store = FruitParametersStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showEditSheet = false
    @State private var editingCategory: FruitCategory? = nil
    @State private var showResetConfirm = false
    @State private var searchText = ""
    
    private var filteredCategories: [FruitCategory] {
        if searchText.isEmpty {
            return FruitCategory.allCases
        }
        return FruitCategory.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var customizedCount: Int {
        store.customizedCount()
    }

    private var activeCategory: FruitCategory {
        FruitCategory(rawValue: settings.fruitType) ?? .apple
    }
    
    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerBar
                
                if !searchText.isEmpty {
                    searchResultsInfo
                }
                
                ScrollView {
                    LazyVStack(spacing: Design.Space.sm) {
                        ForEach(filteredCategories, id: \.self) { category in
                            VarietyRow(
                                category: category,
                                params: store.param(for: category),
                                isCurrent: activeCategory == category,
                                onUse: { settings.fruitType = category.rawValue },
                                onEdit: { editingCategory = category; showEditSheet = true }
                            )
                        }
                    }
                    .padding(Design.Space.md)
                }
            }
        }
        .navigationTitle("品种参数库")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("重置所有参数", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(Design.Colors.Dark.glow)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let category = editingCategory {
                VarietyEditView(
                    category: category,
                    params: store.param(for: category),
                    onSave: { newParams in
                        store.updateParam(for: category) { p in
                            p.diamMin = newParams.diamMin
                            p.diamMax = newParams.diamMax
                            p.averageWeightG = newParams.averageWeightG
                            p.density = newParams.density
                            p.clusterEps = newParams.clusterEps
                            p.sphericityThreshold = newParams.sphericityThreshold
                        }
                    },
                    onReset: {
                        store.resetToDefault(for: category)
                    }
                )
            }
        }
        .alert("重置所有参数", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                store.resetAll()
            }
        } message: {
            Text("确定要重置所有品种参数为默认值吗？")
        }
        .searchable(text: $searchText, prompt: "搜索品种")
    }
    
    private var headerBar: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(Design.Colors.forest)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("品种参数库")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                
                Text("当前扫描: \(activeCategory.displayName) · \(customizedCount) 个品种已自定义")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            
            Spacer()
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }
    
    private var searchResultsInfo: some View {
        HStack {
            Text("找到 \(filteredCategories.count) 个品种")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.xs)
        .background(Design.Colors.Dark.bgDeep)
    }
}

private struct VarietyRow: View {
    let category: FruitCategory
    let params: FruitVarietyParams
    let isCurrent: Bool
    let onUse: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        Button(action: onUse) {
            HStack(spacing: Design.Space.md) {
                fruitIcon
            
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(params.displayName)
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.Dark.textPrimary)

                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Design.Colors.Dark.bgDeep)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Design.Colors.harvest))
                        } else if params.isCustomized {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Design.Colors.harvest)
                        }
                    }

                    HStack(spacing: Design.Space.sm) {
                        ParamChip(label: "直径", value: "\(Int(params.diamMin * 1000))~\(Int(params.diamMax * 1000))mm")
                        ParamChip(label: "均重", value: "\(Int(params.averageWeightG))g")
                        ParamChip(label: "Eps", value: String(format: "%.3f", params.clusterEps))
                    }
                }

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 24))
                        .foregroundColor(Design.Colors.Dark.glow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(params.displayName) 参数")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "\(params.displayName)，当前扫描品种" : "设为当前扫描品种: \(params.displayName)")
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(isCurrent ? Design.Colors.harvest.opacity(0.12) : Design.Colors.Dark.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.medium)
                        .stroke(isCurrent ? Design.Colors.harvest : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private var fruitIcon: some View {
        ZStack {
            Circle()
                .fill(fruitColor.opacity(0.2))
                .frame(width: 44, height: 44)
            
            Image(systemName: "leaf.fill")
                .font(.system(size: 20))
                .foregroundColor(fruitColor)
        }
    }
    
    private var fruitColor: Color {
        switch category {
        case .apple: return .red
        case .orange, .mandarin, .pomelo: return .orange
        case .pear: return Color(hex: "B8D4A8")
        case .peach: return Color(hex: "FFB6C1")
        case .cherry: return Color(hex: "DC143C")
        case .grape: return Color(hex: "8B008B")
        case .mango: return Color(hex: "FFD700")
        case .kiwi: return Color(hex: "9ACD32")
        default: return Design.Colors.harvest
        }
    }
}

private struct ParamChip: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Design.Colors.Dark.bgDeep)
        )
    }
}

private struct VarietyEditView: View {
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
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(normalizedParams)
                        dismiss()
                    }
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
                Button("重置", role: .destructive) {
                    onReset()
                    dismiss()
                }
            } message: {
                Text("确定要重置为默认值吗？")
            }
        }
        .onChange(of: diamMin) { value in
            if value > diamMax {
                diamMax = value
            }
        }
        .onChange(of: diamMax) { value in
            if value < diamMin {
                diamMin = value
            }
        }
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
            SectionHeader(title: "果实尺寸", icon: "ruler")
            
            VStack(spacing: Design.Space.md) {
                SliderRow(
                    title: "最小直径",
                    value: $diamMin,
                    range: 0.005...0.05,
                    step: 0.001,
                    unit: "mm",
                    displayValue: "\(Int(diamMin * 1000))"
                )
                
                SliderRow(
                    title: "最大直径",
                    value: $diamMax,
                    range: 0.05...0.30,
                    step: 0.005,
                    unit: "mm",
                    displayValue: "\(Int(diamMax * 1000))"
                )
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgSurface)
            )
        }
    }
    
    private var weightSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            SectionHeader(title: "重量与密度", icon: "scalemass")
            
            VStack(spacing: Design.Space.md) {
                SliderRow(
                    title: "平均单果重量",
                    value: $averageWeightG,
                    range: 1...2000,
                    step: 1,
                    unit: "g",
                    displayValue: "\(Int(averageWeightG))"
                )
                
                SliderRow(
                    title: "密度",
                    value: $density,
                    range: 0.5...1.0,
                    step: 0.01,
                    unit: "",
                    displayValue: String(format: "%.2f", density)
                )
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgSurface)
            )
        }
    }
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            SectionHeader(title: "检测阈值", icon: "circle.hexagongrid")
            
            VStack(spacing: Design.Space.md) {
                SliderRow(
                    title: "球形度阈值",
                    value: $sphericityThreshold,
                    range: 0.2...0.8,
                    step: 0.01,
                    unit: "",
                    displayValue: String(format: "%.2f", sphericityThreshold)
                )
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgSurface)
            )
        }
    }
    
    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            SectionHeader(title: "聚类参数", icon: "circle.grid.3x3")
            
            VStack(spacing: Design.Space.md) {
                SliderRow(
                    title: "聚类半径 (Eps)",
                    value: $clusterEps,
                    range: 0.02...0.15,
                    step: 0.005,
                    unit: "m",
                    displayValue: String(format: "%.3f", clusterEps)
                )
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgSurface)
            )
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.glow)
            Text(title)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let unit: String
    let displayValue: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack {
                Text(title)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Text("\(displayValue)\(unit)")
                    .font(Design.Typography.mono)
                    .foregroundColor(Design.Colors.Dark.glow)
            }
            
            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.Dark.glow)
        }
    }
}

#Preview {
    NavigationStack {
        VarietyDatabaseView()
    }
}
