import SwiftUI

enum VarietySearchMatcher {
    static func matches(
        category: FruitCategory,
        query: String,
        localizedName: String
    ) -> Bool {
        localizedName.localizedCaseInsensitiveContains(query)
            || category.rawValue.localizedCaseInsensitiveContains(query)
    }
}

struct VarietyDatabaseView: View {
    @ObservedObject private var store = FruitParametersStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var editingSheet: VarietyEditSheet?
    @State private var showResetConfirm = false
    @State private var searchText = ""
    
    private var filteredCategories: [FruitCategory] {
        if searchText.isEmpty {
            return FruitCategory.allCases
        }
        return FruitCategory.allCases.filter {
            VarietySearchMatcher.matches(
                category: $0,
                query: searchText,
                localizedName: L10n.Fruit.name(for: $0)
            )
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
                    activeCategoryName: L10n.Fruit.name(for: activeCategory),
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
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 56)
                }
            }
            .overlay(alignment: .bottom) {
                Design.Colors.Dark.bgDeep
                    .frame(height: 72)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.VarietyDatabase.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label(L10n.VarietyDatabase.resetAll, systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(Design.Colors.Dark.glow)
                        .accessibilityLabel(L10n.VarietyDatabase.moreActions)
                }
            }
        }
        .sheet(item: $editingSheet) { sheet in
            let category = sheet.category
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
        .alert(L10n.VarietyDatabase.resetAll, isPresented: $showResetConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.VarietyDatabase.reset, role: .destructive) {
                store.resetAll()
            }
        } message: {
            Text(L10n.VarietyDatabase.resetAllMessage)
        }
        .searchable(text: $searchText, prompt: L10n.VarietyDatabase.searchPrompt)
    }

    private func useCategory(_ category: FruitCategory) {
        settings.fruitType = category.rawValue
    }

    private func editCategory(_ category: FruitCategory) {
        editingSheet = VarietyEditSheet(category: category)
    }
}

private struct VarietyEditSheet: Identifiable {
    let category: FruitCategory

    var id: String { category.rawValue }
}
