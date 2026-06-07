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
                VarietyDatabaseSummaryBar(
                    activeCategoryName: activeCategory.displayName,
                    customizedCount: customizedCount
                )
                
                if !searchText.isEmpty {
                    VarietySearchResultBar(count: filteredCategories.count)
                }
                
                ScrollView {
                    if filteredCategories.isEmpty {
                        VarietySearchEmptyState(searchText: searchText)
                            .padding(.top, Design.Space.md)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredCategories, id: \.self) { category in
                                VarietyRow(
                                    category: category,
                                    params: store.param(for: category),
                                    isCurrent: activeCategory == category,
                                    onUse: { useCategory(category) },
                                    onEdit: { editCategory(category) }
                                )
                            }
                        }
                        .padding(Design.Space.md)
                    }
                }
            }
        }
        .navigationTitle("品种参数库")
        .navigationBarTitleDisplayMode(.inline)
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

    private func useCategory(_ category: FruitCategory) {
        settings.fruitType = category.rawValue
    }

    private func editCategory(_ category: FruitCategory) {
        editingCategory = category
        showEditSheet = true
    }
}
