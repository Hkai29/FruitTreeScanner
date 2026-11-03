import SwiftUI

// MARK: - 搜索

/// 档案搜索：树号与存档编号**都**匹配。
///
/// 语义边界（与已认可原型一致）：
/// - 匹配的是**已经加载进内存的档案元数据**，不是磁盘搜索：
///   搜索框每敲一个字都不重新解析 PLY，也不另开一条读盘通路。
/// - 忽略首尾空白与大小写：树号是人抄进来的，空格与大小写都是常见手误。
/// - 空查询 = 不过滤（不是「什么都不匹配」）。
enum ScanHistorySearch {
    /// 归一化后的查询串：去掉首尾空白与换行。
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 这条档案是否命中查询。
    static func matches(_ record: ScanFileRecord, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return contains(record.treeID, needle) || contains(record.id, needle)
    }

    /// 过滤：保留传入顺序（顺序由调用方决定，这里不改）。
    static func filter(_ records: [ScanFileRecord], query: String) -> [ScanFileRecord] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return records }
        return records.filter { contains($0.treeID, needle) || contains($0.id, needle) }
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        fold(haystack).contains(fold(needle))
    }

    /// 大小写与变音符号都不敏感；locale 取 nil，避免土耳其语 I 之类的地区差异。
    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - 日期分组

/// 档案按扫描日期分组：一组 = 一个日期段。
///
/// 分组只影响**列表呈现**：组内仍是同一批档案，每一行仍按 `record.id` 打开同一份档案。
struct ScanHistoryDateGroup: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case today
        case yesterday
        case earlier
        /// 扫描日期落在未来：日期本身有问题，**明确降级**说出来，
        /// 不塞进「更早」里冒充正常档案，也不改写 `scanDate`。
        case invalidDate

        var order: Int {
            switch self {
            case .today: return 0
            case .yesterday: return 1
            case .earlier: return 2
            case .invalidDate: return 3
            }
        }
    }

    let kind: Kind
    var records: [ScanFileRecord]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .today: return L10n.History.groupToday
        case .yesterday: return L10n.History.groupYesterday
        case .earlier: return L10n.History.groupEarlier
        case .invalidDate: return L10n.History.groupInvalidDate
        }
    }

    /// 组标题：一段日期 + 这一段有几份（原型口径「今天 · 3 份」）。
    var titleWithCount: String {
        String.localizedStringWithFormat(L10n.History.groupCountFormat, title, records.count)
    }
}

/// 按真实扫描日期把档案分组。
///
/// 「今天 / 昨天」按 **Calendar 的那一天**判定（不是相差 24 小时）：
/// 跨午夜与时区都交给调用方给的 `calendar`，
/// 测试可以注入固定时钟与固定时区做边界回归，不靠运行当天猜。
enum ScanHistoryDateGrouping {
    /// 分组。
    ///
    /// - Parameters:
    ///   - now: 判定「今天」的基准时刻（测试注入固定时钟）。
    ///   - calendar: 判定日期边界用的日历（测试可注入别的时区）。
    static func group(
        _ records: [ScanFileRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScanHistoryDateGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var buckets: [ScanHistoryDateGroup.Kind: [ScanFileRecord]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.scanDate)
            let kind: ScanHistoryDateGroup.Kind
            if day > today {
                kind = .invalidDate
            } else if day == today {
                kind = .today
            } else if day == yesterday {
                kind = .yesterday
            } else {
                kind = .earlier
            }
            buckets[kind, default: []].append(record)
        }
        return ScanHistoryDateGroup.Kind.allCases
            .sorted { $0.order < $1.order }
            .compactMap { kind in
                guard let records = buckets[kind], !records.isEmpty else { return nil }
                return ScanHistoryDateGroup(kind: kind, records: sorted(records))
            }
    }

    /// 组内顺序：扫描时间新的在前；时间相同用存档编号排，保证**稳定**。
    static func sorted(_ records: [ScanFileRecord]) -> [ScanFileRecord] {
        records.sorted { lhs, rhs in
            if lhs.scanDate != rhs.scanDate { return lhs.scanDate > rhs.scanDate }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 空结果的原因

/// 档案页「看不到记录」的原因。
///
/// 四种原因必须分开说 —— 尤其「查询命中了，但被筛选排空」不能被说成
/// 「没有这样的树号或记录号」：那条记录明明就在档案里，是筛选把它挡住了。
enum ScanHistoryEmptyReason: Equatable, Sendable {
    /// 档案里一条都没有。
    case emptyArchive
    /// 档案里有记录，但当前地块/状态筛选把它们都排除了（与搜索无关）。
    case filteredOut
    /// 查询本身没有命中任何档案：没有树号或记录号包含它。
    case searchNoMatch
    /// 查询命中了档案，但当前地块/状态筛选把它们都排除了。
    case searchExcludedByFilters

    /// 判断当前该说哪一种空结果；可见记录不为空时没有空结果（返回 nil）。
    ///
    /// - Parameters:
    ///   - archiveCount: 档案里的记录总数。
    ///   - searchMatchCount: **只按查询**命中的记录数（不套地块/状态）。
    ///   - visibleCount: 地块/状态 ∩ 查询之后还剩几条。
    ///   - hasSearchQuery: 查询是否非空（归一化后）。
    static func resolve(
        archiveCount: Int,
        searchMatchCount: Int,
        visibleCount: Int,
        hasSearchQuery: Bool
    ) -> ScanHistoryEmptyReason? {
        guard visibleCount == 0 else { return nil }
        if archiveCount == 0 { return .emptyArchive }
        guard hasSearchQuery else { return .filteredOut }
        // 查询命中了几条却一条都没留下 → 是筛选把它们排掉的，不是「没有这条记录」。
        return searchMatchCount > 0 ? .searchExcludedByFilters : .searchNoMatch
    }
}

// MARK: - 搜索框

/// 档案搜索框：树号与存档编号都搜，右侧一个清除入口。
///
/// 只有一个入口做清除（原生那个蓝色叉不算），与原型一致；
/// 输入框本身不参与朗读细节：标签说清「搜什么」，值由系统读。
struct ScanHistorySearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .accessibilityHidden(true)

            TextField(L10n.History.searchPlaceholder, text: $query)
                .font(.system(.subheadline, design: .default))
                .foregroundColor(Design.Colors.Workspace.ink)
                .multilineTextAlignment(.leading)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                // 键盘上的搜索键 = 搜索 + 收键盘。
                // 键盘浮在列表上方时，下面几行会被挡住；
                // 没有这个出口，用户就得先滚一下列表才能看到它们。
                .onSubmit { isFocused = false }
                .focused($isFocused)
                .accessibilityLabel(L10n.History.searchFieldLabel)
                .accessibilityIdentifier("historySearch.field")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.History.clearSearch)
                .accessibilityIdentifier("historySearch.clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: Design.Touch.minimumHeight)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(Design.Colors.Workspace.inset)
                // 输入框本体只有一行文字高（平台控件如此），
                // 上下留白在**这一行**里。点空白处也要能聚焦，
                // 不然那 11pt 就是点不动的死区。
                .onTapGesture { isFocused = true }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

// MARK: - 分组标题

/// 一段日期的标题：日期 + 这一段有几份。
///
/// 它是**静态文本**，不是按钮：分组不可点，也不改变任何数据。
struct ScanHistoryGroupHeader: View {
    let group: ScanHistoryDateGroup

    /// 标识带上组别：同一次列表里可能有多个组标题，共用一个标识就分不出是哪一段。
    var accessibilityIdentifier: String {
        "historyGroup.header." + group.kind.rawValue
    }

    var body: some View {
        Text(group.titleWithCount)
            .font(.footnote.weight(.semibold))
            .foregroundColor(Design.Colors.Workspace.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Design.Space.md)
            .padding(.bottom, Design.Space.sm)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
