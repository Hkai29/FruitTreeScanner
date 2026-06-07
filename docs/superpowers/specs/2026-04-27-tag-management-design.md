# 标签管理系统 + UI 改进设计文档

**日期**: 2026-04-27
**项目**: FruitTreeScanner iOS App
**范围**: 标签管理（地块/分组/状态）+ UI 改进 + 现有功能修复

---

## 一、数据模型

### 1.1 Plot（地块）

```swift
struct Plot: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String  // 如 "#FF6B6B"
    var displayOrder: Int
    var createdAt: Date
}
```

### 1.2 GroupTag（分组标签）

```swift
struct GroupTag: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
}
```

### 1.3 TreeAssignment（果树的标签分配）

```swift
struct TreeAssignment: Codable {
    let treeId: String        // 树ID（如 T001）
    var plotId: UUID?         // 所属地块（可选）
    var tagIds: [UUID]         // 分组标签列表
    var status: ScanStatus     // 状态
}
```

### 1.4 ScanStatus（状态枚举）

```swift
enum ScanStatus: String, Codable, CaseIterable {
    case notScanned = "未扫描"
    case scanned = "已扫描"
    case reviewing = "复查中"
    case completed = "已完成"
}
```

### 1.5 数据存储

- 存储在 UserDefaults（JSON 编码）
- 新建 `TagStore.swift` 作为单一数据源
- 与 `ScanHistoryStore` 通过 treeId 关联

---

## 二、UI 界面设计

### 2.1 标签管理首页（TagManagementView）

三个标签页：地块 / 分组标签 / 状态

**地块标签页**:
- 列表显示所有地块，每行显示：颜色点、名称、关联树木数量
- 底部 "+ 添加地块" 按钮
- 左滑删除、长按拖动排序

**分组标签页**:
- 类似地块页，显示所有分组标签
- 支持创建/编辑/删除/排序

**状态页**:
- 显示四个固定状态及统计
- 状态不可删除，仅显示统计

### 2.2 地块编辑页面（PlotEditView）

- 名称输入框
- 颜色选择器（8 种预设颜色）
- 保存/取消按钮

### 2.3 分组标签编辑页面（TagEditView）

- 名称输入框
- 颜色选择器
- 保存/取消按钮

### 2.4 果树筛选页面（TreeFilterView）

- 顶部三个下拉筛选器：地块、标签、状态
- 列表显示符合条件的果树
- 每行显示：树ID、地块、标签、状态、最近扫描时间
- 点击进入该树的扫描历史

### 2.5 扫描结果页快速打标签（ResultView 修改）

在现有 ResultView 底部增加：
- 地块下拉选择器
- 标签多选（ chips 形式）
- 状态单选（四个选项）
- "保存并返回" 和 "仅保存" 按钮

---

## 三、功能流程

### 3.1 集中管理流程

1. 用户点击 Dashboard 的"标签管理"按钮
2. 进入 TagManagementView（标签页）
3. 可切换：地块 / 分组 / 状态
4. 点击 "+ 添加" 进入编辑页
5. 保存后返回列表

### 3.2 扫描时快速打标签流程

1. 完成扫描 → ResultView 显示产量
2. 底部显示地块/标签/状态选择器
3. 用户选择后点击"保存并返回"
4. 自动创建 TreeAssignment，状态默认为"已扫描"

### 3.3 果树筛选流程

1. 用户点击 Dashboard 的"果树列表"按钮
2. 进入 TreeFilterView
3. 选择筛选条件（可多选）
4. 列表实时更新
5. 点击果树查看其扫描历史

---

## 四、与现有功能的衔接

### 4.1 ScanHistoryStore 关联

- `TreeAssignment` 通过 `treeId` 与 `ScanFileRecord` 关联
- 查询时：先通过筛选条件找到匹配的 treeId，再查询对应的扫描记录

### 4.2 扫描入口（StartView / ResultView）

- StartView 增加地块选择（可选）
- ResultView 增加标签/状态选择

### 4.3 历史对比（HistoricalCompareView）

- 移除模拟数据，改用 PLY 解析获取真实数据
- 按当前筛选条件过滤果树

### 4.4 Dashboard 修复

- 修复"标签管理"按钮打开空白页的问题
- 修复"标签管理"按钮的 sheet 入口

---

## 五、文件修改清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `FruitTreeScanner/Core/TagStore.swift` | 标签数据管理（地块、标签、状态） |
| `FruitTreeScanner/Views/TagManagementView.swift` | 标签管理主页面 |
| `FruitTreeScanner/Views/PlotEditView.swift` | 地块编辑页 |
| `FruitTreeScanner/Views/TagEditView.swift` | 分组标签编辑页 |
| `FruitTreeScanner/Views/TreeFilterView.swift` | 果树筛选页 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `ResultView.swift` | 增加快速打标签组件 |
| `ScanHistoryView.swift` | 增加筛选器 |
| `HistoricalCompareView.swift` | 连接真实 PLY 数据 |
| `DashboardView.swift` | 修复标签管理入口 |
| `SettingsView.swift` | 修复设置页面标题 |

---

## 六、UI 改进（修复）

### 6.1 DashboardView 标签管理入口

- 当前：`.sheet(isPresented: $showTagManagement) { Text("标签管理") }`
- 修改为：打开 `TagManagementView`

### 6.2 HistoricalCompareView 数据来源

- 当前：使用模拟数据 "actual data would need PLY parsing"
- 修改为：解析真实 PLY 文件获取扫描结果

### 6.3 SettingsView 标题修复

- 当前：导航标题显示"矫正相机设置"
- 修改为：正确的标题

---

## 七、实现顺序

1. **Phase 1**: TagStore 数据模型 + TagManagementView（地块管理）
2. **Phase 2**: 分组标签管理 + 状态显示
3. **Phase 3**: 果树筛选页面 + ScanHistoryView 筛选器
4. **Phase 4**: ResultView 快速打标签
5. **Phase 5**: HistoricalCompareView 真实数据连接
6. **Phase 6**: Dashboard 修复 + Settings 标题修复

---

## 八、非功能性要求

- 数据存储在 UserDefaults，JSON 编码
- 标签数量预计不超过 100 条，查询性能无问题
- 支持 iOS 16+（MapKit 部分需要 iOS 17+）
- 遵循现有代码风格（SwiftUI + @StateObject/@ObservedObject）