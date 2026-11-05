import SwiftUI

/// 内容宽度：与整页一致的最大宽度 + 左右留白 + 居中。
private extension View {
    func archivePageWidth() -> some View {
        frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// 扫描档案内容：搜索框 + 筛选条 + 按日期分组的记录列表。
///
/// 容器沿用既有的 `ScrollView` + `LazyVStack` 结构：原生 `List` 的
/// `UICollectionView` 在记录被筛掉后仍会短暂保留旧的可访问元素，
/// 会让"标记为待复核后应立即从当前筛选中消失"的行为失真。
/// 视觉完全由行、搜索框与筛选条组件提供，容器只负责排布。
///
/// 搜索与筛选随列表一起滚（与原型一致），但放在**非惰性**的容器里 ——
/// 放进 `LazyVStack` 的话，列表一滚远它们连同无障碍元素一起消失，
/// 「有没有回到档案列表」这类判断会被滚动位置绑架。
///
/// 四种"看不到记录"必须分开说：
/// - 档案里一条都没有 → 档案页整体走空状态（带「开始扫描」）；
/// - 有档案，但当前搜索没命中 → 搜索专属文案 + 「清除搜索」；
/// - 查询**命中了**，但被地块/状态筛选排空 → 「被筛选排除」文案 + 「清除筛选」
///   （不能说成「没有这样的记录」：那条记录就在档案里）；
/// - 有档案，但地块/状态筛选没命中 → 筛选专属文案。
/// 加载失败与损坏记录由档案页的横幅说明，不混进这里。
///
/// 返回档案详情后，滚动位置与无障碍焦点要放回刚才看的那一条：
/// `ScrollViewReader` 负责滚动锚点，`focusedRecordID` 负责焦点。
struct ScanHistoryContentView: View {
    let filteredScans: [ScanFileRecord]
    /// 为什么看不到记录：区分「没有这条记录」与「被筛选排掉了」。
    let emptyReason: ScanHistoryEmptyReason?
    /// 当前搜索词（树号或存档编号）。清空它**不动**地块与状态筛选。
    @Binding var searchQuery: String
    @Binding var selectedPlotId: UUID?
    @Binding var selectedStatus: ScanStatus?
    @ObservedObject var tagStore: TagStore
    /// 打开这条归档的详情（档案身份，不是树号）。
    var onOpen: ((ScanFileRecord) -> Void)? = nil
    /// 无障碍焦点落在哪一条（返回后由档案页放回原处）。
    var focusedRecordID: AccessibilityFocusState<String?>.Binding
    /// 待恢复的滚动锚点（存档身份）。
    var pendingScrollRecordID: Binding<String?>
    let onPreview: (ScanFileRecord) -> Void
    let onShare: (ScanFileRecord) -> Void
    let onRescan: (ScanFileRecord) -> Void
    let onMarkReview: (ScanFileRecord) -> Void
    let onDelete: (ScanFileRecord) -> Void
    let historyStore: ScanHistoryStore
    var loadFeedback: AnyView? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 搜索与筛选放在**非惰性**的 VStack 里（行仍在 LazyVStack 里）：
                // `LazyVStack` 只materialize视口附近的子视图 —— 搜索框与筛选片
                // 放在里面的话，列表一滚远它们连同**无障碍元素**一起消失，
                // 「有没有回到档案列表」这类判断就被滚动位置绑架了。
                // VStack 是 eager 的：控件一直在树里，而列表的可视区高度不受影响
                // （横屏 + 辅助字号下，那点常驻高度是要留给记录的）。
                VStack(alignment: .leading, spacing: 0) {
                    if let loadFeedback {
                        loadFeedback.padding(.bottom, Design.Space.lg)
                    }

                    // 搜索在筛选之上：先缩小范围，再挑地块与状态。
                    ScanHistorySearchField(query: $searchQuery)
                        .padding(.bottom, Design.Space.sm)

                    ScanHistoryFilterBar(
                        selectedPlotId: $selectedPlotId,
                        selectedStatus: $selectedStatus,
                        tagStore: tagStore
                    )
                    .padding(.bottom, Design.Space.sm)

                    if filteredScans.isEmpty {
                        emptyState
                    } else {
                        groupedRows
                    }
                }
                .archivePageWidth()
            }
            // 滚动列表就把键盘收起来：搜索结果要能被看全、点得到。
            .scrollDismissesKeyboard(.immediately)
            .refreshable { [historyStore] in await historyStore.reloadRecords() }
            .onChange(of: pendingScrollRecordID.wrappedValue) { recordID in
                guard let recordID else { return }
                // 放回原位：滚动锚点与无障碍焦点都指向刚才看过的那一条。
                proxy.scrollTo(recordID, anchor: .center)
                pendingScrollRecordID.wrappedValue = nil
            }
        }
    }

    // MARK: - 空态

    @ViewBuilder
    private var emptyState: some View {
        switch emptyReason ?? .filteredOut {
        case .emptyArchive:
            // 档案一条都没有：整页的空态由档案页自己给（带「开始扫描」），这里到不了。
            ScanHistoryEmptyState(
                title: L10n.History.emptyTitle,
                message: L10n.History.emptyMessage,
                outerPadding: false
            )
            .padding(.top, Design.Space.md)
        case .searchNoMatch:
            // 查询确实没命中：说清是**没有这样的树号或记录号**，
            // 并给一个只清搜索的动作（地块与状态筛选保持不变）。
            ScanHistoryEmptyState(
                title: L10n.History.searchNoMatchTitle,
                message: L10n.History.searchNoMatchMessage(searchQuery),
                secondaryAction: (title: L10n.History.clearSearch, action: { searchQuery = "" }),
                secondaryActionIdentifier: "historyEmpty.clearSearch",
                outerPadding: false
            )
            .padding(.top, Design.Space.md)
        case .searchExcludedByFilters:
            // 查询**命中了**，是当前地块/状态筛选把它们排空的：
            // 记录就在档案里，不能说成「没有这样的记录」。
            // 出口是清筛选，**不动搜索**：两个条件各自独立。
            ScanHistoryEmptyState(
                title: L10n.History.searchExcludedTitle,
                message: L10n.History.searchExcludedMessage(searchQuery),
                secondaryAction: (title: L10n.History.clearFilters, action: clearFilters),
                secondaryActionIdentifier: "historyEmpty.clearFilters",
                outerPadding: false
            )
            .padding(.top, Design.Space.md)
        case .filteredOut:
            ScanHistoryEmptyState(
                title: L10n.History.filteredEmptyTitle,
                message: L10n.History.filteredEmptyMessage,
                outerPadding: false
            )
            .padding(.top, Design.Space.md)
        }
    }

    /// 清除地块与状态筛选：**不动搜索**。
    ///
    /// 两个条件互相独立：用户挑的地块不该被顺手带走，搜索词也一样。
    private func clearFilters() {
        selectedPlotId = nil
        selectedStatus = nil
    }

    // MARK: - 分组列表
    /// 按扫描日期分段：今天 / 昨天 / 更早（未来日期单独说「日期异常」）。
    ///
    /// 分组只影响**呈现**：组内仍是同一批档案，每一行仍按 `record.id` 打开同一份档案。
    private var groups: [ScanHistoryDateGroup] {
        ScanHistoryDateGrouping.group(filteredScans)
    }

    private var groupedRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                ScanHistoryGroupHeader(group: group)
                ForEach(group.records) { record in
                    row(for: record)
                }
            }
        }
    }

    private func row(for record: ScanFileRecord) -> some View {
        ScanHistoryRow(
            record: record,
            onOpen: onOpen.map { handler in { handler(record) } },
            plotName: plotName(for: record),
            onPreview: { onPreview(record) },
            onShare: { onShare(record) },
            onRescan: { onRescan(record) },
            onMarkReview: { onMarkReview(record) },
            onDelete: { onDelete(record) },
            focusBinding: focusedRecordID
        )
        .id(record.id)
    }

    /// 树当前归属的地块名。
    ///
    /// 与档案页的地块筛选同源（`tagStore` 的当前分类），
    /// 不是扫描当时冻结的快照 —— 展示时也单独成行，不与这次扫描的结果混写。
    private func plotName(for record: ScanFileRecord) -> String? {
        guard let plotId = tagStore.getAssignment(treeId: record.treeID)?.plotId else { return nil }
        let name = tagStore.getPlot(id: plotId)?.name
        return (name?.isEmpty == false) ? name : nil
    }
}
