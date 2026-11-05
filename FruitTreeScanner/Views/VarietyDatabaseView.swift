// VarietyDatabaseView.swift
// 品种参数库：列出所有品种的真实参数，进入编辑页后可改。
//
// 编辑采用“草稿—提交”模型：编辑页持有基线副本，取消即丢弃，
// 保存时交给 FruitParametersStore 合并并落盘。
//
// 容器说明：这里用 ScrollView 而不是原生 List。原生 List 由 UICollectionView 承载，
// 现有 UI 测试驱动页面时需要能滚动并可定位的 UIScrollView；分组外观由
// InstrumentRowGroup 统一，与工作台其他页面一致。

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
    @ObservedObject private var store: FruitParametersStore
    @ObservedObject private var settings: SettingsStore
    @State private var editingSheet: VarietyEditSheet?
    @State private var showResetConfirm = false
    @State private var searchText = ""

    @MainActor
    init(settings: SettingsStore = .shared, store: FruitParametersStore? = nil) {
        self.settings = settings
        self.store = store ?? .shared
    }

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
        VStack(spacing: 0) {
            VarietyDatabaseSummaryBar(
                activeCategoryName: L10n.Fruit.name(for: activeCategory),
                customizedCount: customizedCount
            )

            if !searchText.isEmpty {
                VarietySearchResultBar(count: filteredCategories.count)
            }

            content
        }
        .workspacePage()
        .navigationTitle(L10n.VarietyDatabase.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
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
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityLabel(L10n.VarietyDatabase.moreActions)
                }
            }
        }
        .sheet(item: $editingSheet) { sheet in
            let category = sheet.category
            VarietyEditView(
                category: category,
                params: store.param(for: category),
                onCommit: { baseline, edited in
                    store.commitEdits(for: category, baseline: baseline, edited: edited)
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

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if filteredCategories.isEmpty {
            ScrollView {
                VarietySearchEmptyState(searchText: searchText)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        } else {
            ScrollView {
                InstrumentRowGroup {
                    ForEach(filteredCategories, id: \.self) { category in
                        VarietyRow(
                            category: category,
                            params: store.param(for: category),
                            isCurrent: activeCategory == category,
                            onUse: { useCategory(category) },
                            onEdit: { editCategory(category) }
                        )
                        if category != filteredCategories.last {
                            DividerLine()
                        }
                    }
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - 动作

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
