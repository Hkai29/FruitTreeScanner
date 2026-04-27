# 标签管理系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标:** 实现完整的标签管理系统（地块/分组标签/状态）+ 修复现有 UI 问题

**架构:** 遵循现有 ScanHistoryStore 的模式，使用 @MainActor 类管理数据，UserDefaults 存储，通过 @Published 响应式更新 UI

**技术栈:** SwiftUI, Combine, UserDefaults, @MainActor

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `FruitTreeScanner/Core/TagStore.swift` | 数据模型和数据管理（单一数据源） |
| `FruitTreeScanner/Views/TagManagementView.swift` | 标签管理首页（三个标签页） |
| `FruitTreeScanner/Views/PlotEditView.swift` | 地块编辑页 |
| `FruitTreeScanner/Views/TagEditView.swift` | 分组标签编辑页 |
| `FruitTreeScanner/Views/TreeFilterView.swift` | 果树筛选页 |
| `ResultView.swift` | 增加快速打标签组件 |
| `ScanHistoryView.swift` | 增加筛选器 |
| `HistoricalCompareView.swift` | 连接真实 PLY 数据 |
| `DashboardView.swift` | 修复标签管理入口 |
| `SettingsView.swift` | 修复设置页面标题 |

---

## Task 1: TagStore 数据模型

**文件:**
- 新建: `FruitTreeScanner/Core/TagStore.swift`

- [ ] **Step 1: 创建 TagStore.swift 文件**

```swift
import Foundation
import Combine

// MARK: - 数据模型

struct Plot: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var displayOrder: Int
    var createdAt: Date

    init(name: String, colorHex: String = "#007AFF", displayOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.displayOrder = displayOrder
        self.createdAt = Date()
    }
}

struct GroupTag: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(name: String, colorHex: String = "#34C759") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

enum ScanStatus: String, Codable, CaseIterable {
    case notScanned = "未扫描"
    case scanned = "已扫描"
    case reviewing = "复查中"
    case completed = "已完成"
}

struct TreeAssignment: Identifiable, Codable, Equatable {
    var id: String { treeId }
    let treeId: String
    var plotId: UUID?
    var tagIds: [UUID]
    var status: ScanStatus

    init(treeId: String, plotId: UUID? = nil, tagIds: [UUID] = [], status: ScanStatus = .notScanned) {
        self.treeId = treeId
        self.plotId = plotId
        self.tagIds = tagIds
        self.status = status
    }
}

// MARK: - TagStore

@MainActor
final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private(set) var plots: [Plot] = []
    @Published private(set) var tags: [GroupTag] = []
    @Published private(set) var assignments: [TreeAssignment] = []

    private let userDefaults = UserDefaults.standard
    private let plotsKey = "TagStore.plots"
    private let tagsKey = "TagStore.tags"
    private let assignmentsKey = "TagStore.assignments"

    private init() {
        load()
    }

    // MARK: - 加载/保存

    private func load() {
        if let data = userDefaults.data(forKey: plotsKey),
           let decoded = try? JSONDecoder().decode([Plot].self, from: data) {
            plots = decoded.sorted { $0.displayOrder < $1.displayOrder }
        }
        if let data = userDefaults.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([GroupTag].self, from: data) {
            tags = decoded
        }
        if let data = userDefaults.data(forKey: assignmentsKey),
           let decoded = try? JSONDecoder().decode([TreeAssignment].self, from: data) {
            assignments = decoded
        }
    }

    private func savePlots() {
        if let encoded = try? JSONEncoder().encode(plots) {
            userDefaults.set(encoded, forKey: plotsKey)
        }
    }

    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tags) {
            userDefaults.set(encoded, forKey: tagsKey)
        }
    }

    private func saveAssignments() {
        if let encoded = try? JSONEncoder().encode(assignments) {
            userDefaults.set(encoded, forKey: assignmentsKey)
        }
    }

    // MARK: - Plot 操作

    func addPlot(name: String, colorHex: String) {
        let maxOrder = plots.map { $0.displayOrder }.max() ?? -1
        let plot = Plot(name: name, colorHex: colorHex, displayOrder: maxOrder + 1)
        plots.append(plot)
        savePlots()
    }

    func updatePlot(_ plot: Plot) {
        if let index = plots.firstIndex(where: { $0.id == plot.id }) {
            plots[index] = plot
            savePlots()
        }
    }

    func deletePlot(id: UUID) {
        plots.removeAll { $0.id == id }
        for i in assignments.indices {
            if assignments[i].plotId == id {
                assignments[i].plotId = nil
            }
        }
        savePlots()
        saveAssignments()
    }

    func movePlot(from source: IndexSet, to destination: Int) {
        plots.move(fromOffsets: source, toOffset: destination)
        for (index, _) in plots.enumerated() {
            plots[index].displayOrder = index
        }
        savePlots()
    }

    // MARK: - Tag 操作

    func addTag(name: String, colorHex: String) {
        let tag = GroupTag(name: name, colorHex: colorHex)
        tags.append(tag)
        saveTags()
    }

    func updateTag(_ tag: GroupTag) {
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = tag
            saveTags()
        }
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        for i in assignments.indices {
            assignments[i].tagIds.removeAll { $0 == id }
        }
        saveTags()
        saveAssignments()
    }

    // MARK: - Assignment 操作

    func getAssignment(treeId: String) -> TreeAssignment? {
        assignments.first { $0.treeId == treeId }
    }

    func createOrUpdateAssignment(treeId: String, plotId: UUID?, tagIds: [UUID], status: ScanStatus) {
        if let index = assignments.firstIndex(where: { $0.treeId == treeId }) {
            assignments[index].plotId = plotId
            assignments[index].tagIds = tagIds
            assignments[index].status = status
        } else {
            let assignment = TreeAssignment(treeId: treeId, plotId: plotId, tagIds: tagIds, status: status)
            assignments.append(assignment)
        }
        saveAssignments()
    }

    func updateAssignmentStatus(treeId: String, status: ScanStatus) {
        if let index = assignments.firstIndex(where: { $0.treeId == treeId }) {
            assignments[index].status = status
            saveAssignments()
        }
    }

    // MARK: - 查询方法

    func treeCount(forPlotId plotId: UUID) -> Int {
        assignments.filter { $0.plotId == plotId }.count
    }

    func treeCount(forTagId tagId: UUID) -> Int {
        assignments.filter { $0.tagIds.contains(tagId) }.count
    }

    func statusCount(forStatus status: ScanStatus) -> Int {
        assignments.filter { $0.status == status }.count
    }

    func getPlot(id: UUID) -> Plot? {
        plots.first { $0.id == id }
    }

    func getTag(id: UUID) -> GroupTag? {
        tags.first { $0.id == id }
    }

    func filteredAssignments(plotId: UUID?, tagIds: [UUID], status: ScanStatus?) -> [TreeAssignment] {
        assignments.filter { assignment in
            if let plotId = plotId, assignment.plotId != plotId {
                return false
            }
            if !tagIds.isEmpty && !tagIds.contains(where: { assignment.tagIds.contains($0) }) {
                return false
            }
            if let status = status, assignment.status != status {
                return false
            }
            return true
        }
    }
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Core/TagStore.swift
git commit -m "feat: add TagStore with Plot, GroupTag, TreeAssignment models"
```

---

## Task 2: PlotEditView 地块编辑页

**文件:**
- 新建: `FruitTreeScanner/Views/PlotEditView.swift`

- [ ] **Step 1: 创建 PlotEditView.swift**

```swift
import SwiftUI

struct PlotEditView: View {
    @Environment(\.dismiss) private var dismiss

    let plot: Plot?
    var onSave: ((Plot) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#007AFF"

    private let colorOptions = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#007AFF", "#5856D6", "#AF52DE", "#8E8E93"
    ]

    init(plot: Plot? = nil, onSave: ((Plot) -> Void)? = nil) {
        self.plot = plot
        self.onSave = onSave
        _name = State(initialValue: plot?.name ?? "")
        _selectedColor = State(initialValue: plot?.colorHex ?? "#007AFF")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("输入地块名称", text: $name)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(plot == nil ? "添加地块" : "编辑地块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let existingPlot = plot {
            var updated = existingPlot
            updated.name = trimmedName
            updated.colorHex = selectedColor
            onSave?(updated)
        } else {
            let newPlot = Plot(name: trimmedName, colorHex: selectedColor)
            onSave?(newPlot)
        }
        dismiss()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    PlotEditView()
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/PlotEditView.swift
git commit -m "feat: add PlotEditView for creating/editing plots"
```

---

## Task 3: TagEditView 分组标签编辑页

**文件:**
- 新建: `FruitTreeScanner/Views/TagEditView.swift`

- [ ] **Step 1: 创建 TagEditView.swift**

```swift
import SwiftUI

struct TagEditView: View {
    @Environment(\.dismiss) private var dismiss

    let tag: GroupTag?
    var onSave: ((GroupTag) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#34C759"

    private let colorOptions = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#007AFF", "#5856D6", "#AF52DE", "#8E8E93"
    ]

    init(tag: GroupTag? = nil, onSave: ((GroupTag) -> Void)? = nil) {
        self.tag = tag
        self.onSave = onSave
        _name = State(initialValue: tag?.name ?? "")
        _selectedColor = State(initialValue: tag?.colorHex ?? "#34C759")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("输入标签名称", text: $name)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(tag == nil ? "添加标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let existingTag = tag {
            var updated = existingTag
            updated.name = trimmedName
            updated.colorHex = selectedColor
            onSave?(updated)
        } else {
            let newTag = GroupTag(name: trimmedName, colorHex: selectedColor)
            onSave?(newTag)
        }
        dismiss()
    }
}

#Preview {
    TagEditView()
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/TagEditView.swift
git commit -m "feat: add TagEditView for creating/editing group tags"
```

---

## Task 4: TagManagementView 标签管理首页

**文件:**
- 新建: `FruitTreeScanner/Views/TagManagementView.swift`

- [ ] **Step 1: 创建 TagManagementView.swift**

```swift
import SwiftUI

struct TagManagementView: View {
    @StateObject private var tagStore = TagStore.shared
    @State private var selectedTab = 0
    @State private var showingAddPlot = false
    @State private var showingAddTag = false
    @State private var editingPlot: Plot?
    @State private var editingTag: GroupTag?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("地块").tag(0)
                    Text("标签").tag(1)
                    Text("状态").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    PlotListView(tagStore: tagStore, onEdit: { editingPlot = $0 })
                        .tag(0)

                    TagListView(tagStore: tagStore, onEdit: { editingTag = $0 })
                        .tag(1)

                    StatusOverviewView(tagStore: tagStore)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("标签管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if selectedTab == 0 {
                            showingAddPlot = true
                        } else if selectedTab == 1 {
                            showingAddTag = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddPlot) {
                PlotEditView { newPlot in
                    tagStore.addPlot(name: newPlot.name, colorHex: newPlot.colorHex)
                }
            }
            .sheet(item: $editingPlot) { plot in
                PlotEditView(plot: plot) { updatedPlot in
                    tagStore.updatePlot(updatedPlot)
                }
            }
            .sheet(isPresented: $showingAddTag) {
                TagEditView { newTag in
                    tagStore.addTag(name: newTag.name, colorHex: newTag.colorHex)
                }
            }
            .sheet(item: $editingTag) { tag in
                TagEditView(tag: tag) { updatedTag in
                    tagStore.updateTag(updatedTag)
                }
            }
        }
    }
}

// MARK: - Plot List View

struct PlotListView: View {
    @ObservedObject var tagStore: TagStore
    var onEdit: (Plot) -> Void

    var body: some View {
        List {
            ForEach(tagStore.plots) { plot in
                HStack {
                    Circle()
                        .fill(Color(hex: plot.colorHex))
                        .frame(width: 16, height: 16)
                    Text(plot.name)
                        .font(.body)
                    Spacer()
                    Text("\(tagStore.treeCount(forPlotId: plot.id))棵树")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onEdit(plot) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        tagStore.deletePlot(id: plot.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                tagStore.movePlot(from: source, to: destination)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if tagStore.plots.isEmpty {
                ContentUnavailableView("暂无地块", systemImage: "map", description: Text("点击右上角添加地块"))
            }
        }
    }
}

// MARK: - Tag List View

struct TagListView: View {
    @ObservedObject var tagStore: TagStore
    var onEdit: (GroupTag) -> Void

    var body: some View {
        List {
            ForEach(tagStore.tags) { tag in
                HStack {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 16, height: 16)
                    Text(tag.name)
                        .font(.body)
                    Spacer()
                    Text("\(tagStore.treeCount(forTagId: tag.id))棵树")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onEdit(tag) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        tagStore.deleteTag(id: tag.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if tagStore.tags.isEmpty {
                ContentUnavailableView("暂无标签", systemImage: "tag", description: Text("点击右上角添加标签"))
            }
        }
    }
}

// MARK: - Status Overview View

struct StatusOverviewView: View {
    @ObservedObject var tagStore: TagStore

    var body: some View {
        List {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                HStack {
                    Image(systemName: statusIcon(for: status))
                        .foregroundStyle(statusColor(for: status))
                        .frame(width: 24)
                    Text(status.rawValue)
                        .font(.body)
                    Spacer()
                    Text("\(tagStore.statusCount(forStatus: status))棵树")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statusIcon(for status: ScanStatus) -> String {
        switch status {
        case .notScanned: return "circle"
        case .scanned: return "checkmark.circle"
        case .reviewing: return "arrow.clockwise.circle"
        case .completed: return "checkmark.seal.fill"
        }
    }

    private func statusColor(for status: ScanStatus) -> Color {
        switch status {
        case .notScanned: return .gray
        case .scanned: return .blue
        case .reviewing: return .orange
        case .completed: return .green
        }
    }
}

#Preview {
    TagManagementView()
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/TagManagementView.swift
git commit -m "feat: add TagManagementView with three tabs (plots, tags, status)"
```

---

## Task 5: TreeFilterView 果树筛选页

**文件:**
- 新建: `FruitTreeScanner/Views/TreeFilterView.swift`

- [ ] **Step 1: 创建 TreeFilterView.swift**

```swift
import SwiftUI

struct TreeFilterView: View {
    @StateObject private var tagStore = TagStore.shared
    @ObservedObject var historyStore: ScanHistoryStore

    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus?

    var filteredAssignments: [TreeAssignment] {
        tagStore.filteredAssignments(plotId: selectedPlotId, tagIds: Array(selectedTagIds), status: selectedStatus)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Menu {
                            Button("全部地块") { selectedPlotId = nil }
                            Divider()
                            ForEach(tagStore.plots) { plot in
                                Button {
                                    selectedPlotId = plot.id
                                } label: {
                                    HStack {
                                        Circle().fill(Color(hex: plot.colorHex)).frame(width: 12, height: 12)
                                        Text(plot.name)
                                    }
                                }
                            }
                        } label: {
                            FilterChip(title: selectedPlotId.flatMap { tagStore.getPlot(id: $0)?.name } ?? "全部地块", isSelected: selectedPlotId != nil)
                        }

                        Menu {
                            Button("全部标签") { selectedTagIds.removeAll() }
                            Divider()
                            ForEach(tagStore.tags) { tag in
                                Button {
                                    if selectedTagIds.contains(tag.id) {
                                        selectedTagIds.remove(tag.id)
                                    } else {
                                        selectedTagIds.insert(tag.id)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedTagIds.contains(tag.id) ? "checkmark" : "")
                                        Circle().fill(Color(hex: tag.colorHex)).frame(width: 12, height: 12)
                                        Text(tag.name)
                                    }
                                }
                            }
                        } label: {
                            FilterChip(title: selectedTagIds.isEmpty ? "全部标签" : "\(selectedTagIds.count)个标签", isSelected: !selectedTagIds.isEmpty)
                        }

                        Menu {
                            Button("全部状态") { selectedStatus = nil }
                            Divider()
                            ForEach(ScanStatus.allCases, id: \.self) { status in
                                Button(status.rawValue) { selectedStatus = status }
                            }
                        } label: {
                            FilterChip(title: selectedStatus?.rawValue ?? "全部状态", isSelected: selectedStatus != nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                List {
                    ForEach(filteredAssignments, id: \.treeId) { assignment in
                        TreeRowView(assignment: assignment, tagStore: tagStore, latestScan: latestScan(for: assignment.treeId))
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if filteredAssignments.isEmpty {
                        ContentUnavailableView("暂无果树", systemImage: "tree", description: Text("调整筛选条件试试"))
                    }
                }
            }
            .navigationTitle("果树列表")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func latestScan(for treeId: String) -> ScanFileRecord? {
        historyStore.scanFiles.first { $0.treeID == treeId }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.subheadline)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray5))
        .foregroundStyle(isSelected ? .accentColor : .primary)
        .clipShape(Capsule())
    }
}

// MARK: - Tree Row View

struct TreeRowView: View {
    let assignment: TreeAssignment
    @ObservedObject var tagStore: TagStore
    let latestScan: ScanFileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let plotId = assignment.plotId, let plot = tagStore.getPlot(id: plotId) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: plot.colorHex)).frame(width: 12, height: 12)
                        Text(plot.name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(status: assignment.status)
            }

            Text(assignment.treeId).font(.headline)

            if !assignment.tagIds.isEmpty {
                HStack(spacing: 6) {
                    ForEach(assignment.tagIds.prefix(3), id: \.self) { tagId in
                        if let tag = tagStore.getTag(id: tagId) {
                            TagBadge(tag: tag)
                        }
                    }
                    if assignment.tagIds.count > 3 {
                        Text("+\(assignment.tagIds.count - 3)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let scan = latestScan {
                HStack {
                    Text(scan.fruitType)
                    Text("|")
                    Text("\(scan.fruitCount)果")
                    Text("|")
                    Text(scan.scanDate, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ScanStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .notScanned: return .gray.opacity(0.2)
        case .scanned: return .blue.opacity(0.2)
        case .reviewing: return .orange.opacity(0.2)
        case .completed: return .green.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .notScanned: return .gray
        case .scanned: return .blue
        case .reviewing: return .orange
        case .completed: return .green
        }
    }
}

// MARK: - Tag Badge

struct TagBadge: View {
    let tag: GroupTag

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: tag.colorHex)).frame(width: 8, height: 8)
            Text(tag.name).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: tag.colorHex).opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    TreeFilterView(historyStore: ScanHistoryStore.shared)
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/TreeFilterView.swift
git commit -m "feat: add TreeFilterView for filtering trees by plot/tag/status"
```

---

## Task 6: DashboardView 修复标签管理入口

**文件:**
- 修改: `FruitTreeScanner/Views/DashboardView.swift`

- [ ] **Step 1: 修改标签管理入口**

找到第 62 行左右的代码:
```swift
.sheet(isPresented: $showTagManagement) { Text("标签管理") }
```

替换为:
```swift
.sheet(isPresented: $showTagManagement) {
    TagManagementView()
}
```

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/DashboardView.swift
git commit -m "fix: connect tag management button to TagManagementView"
```

---

## Task 7: SettingsView 标题修复

**文件:**
- 修改: `FruitTreeScanner/Views/SettingsView.swift`

- [ ] **Step 1: 修复设置页面标题**

查找并修改 `navigationTitle("矫正相机设置")` 为 `navigationTitle("设置")`

- [ ] **Step 2: 提交代码**

```bash
git add FruitTreeScanner/Views/SettingsView.swift
git commit -m "fix: correct settings page title"
```

---

## Task 8: ResultView 快速打标签

**文件:**
- 修改: `FruitTreeScanner/Views/ResultView.swift`

- [ ] **Step 1: 添加状态变量**

```swift
@StateObject private var tagStore = TagStore.shared
@State private var selectedPlotId: UUID?
@State private var selectedTagIds: Set<UUID> = []
@State private var selectedStatus: ScanStatus = .scanned
```

- [ ] **Step 2: 添加辅助函数**

```swift
private func statusColor(for status: ScanStatus) -> Color {
    switch status {
    case .notScanned: return .gray
    case .scanned: return .blue
    case .reviewing: return .orange
    case .completed: return .green
    }
}
```

- [ ] **Step 3: 在 body 中添加快速打标签 Section**

在底部按钮之前添加（具体位置需要根据现有代码结构调整）:

```swift
Section {
    // 地块选择
    Menu {
        Button("无地块") { selectedPlotId = nil }
        ForEach(tagStore.plots) { plot in
            Button {
                selectedPlotId = plot.id
            } label: {
                HStack {
                    Circle().fill(Color(hex: plot.colorHex)).frame(width: 12, height: 12)
                    Text(plot.name)
                }
            }
        }
    } label: {
        HStack {
            Text("地块").foregroundStyle(.secondary)
            Spacer()
            if let plotId = selectedPlotId, let plot = tagStore.getPlot(id: plotId) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: plot.colorHex)).frame(width: 12, height: 12)
                    Text(plot.name)
                }
            } else {
                Text("选择地块").foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }
    }

    // 标签多选
    if !tagStore.tags.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签").foregroundStyle(.secondary)
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
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: tag.colorHex)).frame(width: 8, height: 8)
                                Text(tag.name).font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTagIds.contains(tag.id) ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // 状态选择
    VStack(alignment: .leading, spacing: 8) {
        Text("状态").foregroundStyle(.secondary)
        HStack(spacing: 8) {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button {
                    selectedStatus = status
                } label: {
                    Text(status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedStatus == status ? statusColor(for: status).opacity(0.2) : Color(.systemGray5))
                        .foregroundStyle(selectedStatus == status ? statusColor(for: status) : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
} header: {
    Text("快速标记")
}
```

- [ ] **Step 4: 在保存时更新 TagStore**

在 ResultView 的保存逻辑中，添加:

```swift
tagStore.createOrUpdateAssignment(
    treeId: treeID,
    plotId: selectedPlotId,
    tagIds: Array(selectedTagIds),
    status: selectedStatus
)
```

- [ ] **Step 5: 提交代码**

```bash
git add FruitTreeScanner/Views/ResultView.swift
git commit -m "feat: add quick tagging section to ResultView"
```

---

## Task 9: ScanHistoryView 增加筛选器

**文件:**
- 修改: `FruitTreeScanner/Views/ScanHistoryView.swift`

- [ ] **Step 1: 添加状态变量**

```swift
@StateObject private var tagStore = TagStore.shared
@State private var selectedPlotId: UUID?
@State private var selectedStatus: ScanStatus?
```

- [ ] **Step 2: 添加筛选栏**

在 List 上方添加（具体位置需要根据现有代码结构调整）:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        Menu {
            Button("全部地块") { selectedPlotId = nil }
            Divider()
            ForEach(tagStore.plots) { plot in
                Button {
                    selectedPlotId = plot.id
                } label: {
                    HStack {
                        Circle().fill(Color(hex: plot.colorHex)).frame(width: 12, height: 12)
                        Text(plot.name)
                    }
                }
            }
        } label: {
            FilterChip(title: selectedPlotId.flatMap { tagStore.getPlot(id: $0)?.name } ?? "全部地块", isSelected: selectedPlotId != nil)
        }

        Menu {
            Button("全部状态") { selectedStatus = nil }
            Divider()
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button(status.rawValue) { selectedStatus = status }
            }
        } label: {
            FilterChip(title: selectedStatus?.rawValue ?? "全部状态", isSelected: selectedStatus != nil)
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
}
```

- [ ] **Step 3: 添加过滤逻辑**

添加 computed property:

```swift
var filteredScans: [ScanFileRecord] {
    scanHistoryStore.scanFiles.filter { record in
        if let plotId = selectedPlotId {
            let assignment = tagStore.getAssignment(treeId: record.treeID)
            if assignment?.plotId != plotId { return false }
        }
        if let status = selectedStatus {
            let assignment = tagStore.getAssignment(treeId: record.treeID)
            if assignment?.status != status { return false }
        }
        return true
    }
}
```

然后在 ForEach 中使用 `filteredScans` 代替 `scanHistoryStore.scanFiles`

- [ ] **Step 4: 提交代码**

```bash
git add FruitTreeScanner/Views/ScanHistoryView.swift
git commit -m "feat: add filters to ScanHistoryView"
```

---

## Task 10: HistoricalCompareView 连接真实 PLY 数据

**文件:**
- 修改: `FruitTreeScanner/Views/HistoricalCompareView.swift`

- [ ] **Step 1: 读取现有代码**

找到模拟数据部分（约第 69 行），替换为使用 `ScanHistoryStore` 的真实数据

- [ ] **Step 2: 使用真实数据**

```swift
// 获取真实扫描数据
var comparisonData: [TreeComparisonItem] = []

for treeId in selectedTreeIds {
    let records = scanHistoryStore.scanFiles.filter { $0.treeID == treeId }
    let sortedRecords = records.sorted { $0.scanDate > $1.scanDate }
    if let latest = sortedRecords.first {
        let item = TreeComparisonItem(
            treeId: treeId,
            fruitCount: latest.fruitCount,
            yieldKg: latest.yieldKg,
            scanDate: latest.scanDate
        )
        comparisonData.append(item)
    }
}
```

- [ ] **Step 3: 提交代码**

```bash
git add FruitTreeScanner/Views/HistoricalCompareView.swift
git commit -m "fix: use real PLY data in HistoricalCompareView"
```

---

## 实现顺序总结

| Task | 文件 | 优先级 |
|------|------|--------|
| 1 | TagStore.swift | P0 - 基础数据层 |
| 2 | PlotEditView.swift | P1 - UI 组件 |
| 3 | TagEditView.swift | P1 - UI 组件 |
| 4 | TagManagementView.swift | P1 - 主页面 |
| 5 | TreeFilterView.swift | P2 - 果树筛选 |
| 6 | DashboardView.swift | P3 - 修复入口 |
| 7 | SettingsView.swift | P3 - 修复标题 |
| 8 | ResultView.swift | P2 - 快速打标签 |
| 9 | ScanHistoryView.swift | P2 - 增加筛选器 |
| 10 | HistoricalCompareView.swift | P3 - 连接真实数据 |

---

## 验证清单

- [ ] TagStore 可以增删改查 Plot
- [ ] TagStore 可以增删改查 GroupTag
- [ ] TagStore 可以管理 TreeAssignment
- [ ] TagManagementView 三个标签页切换正常
- [ ] PlotEditView 可以添加/编辑地块
- [ ] TagEditView 可以添加/编辑标签
- [ ] TreeFilterView 可以按条件筛选果树
- [ ] Dashboard 的"标签管理"按钮打开 TagManagementView
- [ ] ResultView 底部显示快速打标签组件
- [ ] ScanHistoryView 有筛选功能
- [ ] HistoricalCompareView 使用真实数据