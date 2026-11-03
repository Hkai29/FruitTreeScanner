import SwiftUI

// MARK: - 档案行可读性

/// 一条归档记录的可读性：结果是否完整，以及结果不可用时如何解释。
///
/// 语义边界：这里只回答"这条记录能不能直接用"，不判断证据是否可靠。
/// 完整性来自落盘状态，果数与产量只在结果完整时才有值。
struct ScanHistoryRecordPresentation: Equatable, Sendable {
    enum Integrity: Equatable, Sendable {
        case complete
        case incomplete
        case invalid
    }

    enum Detail: Equatable, Sendable {
        case none
        case missingResult
        case unreadableJSON
        case unreadableCSV
        case revisionMismatch
        case incompleteUnknown
        case invalidUnknown
    }

    let integrity: Integrity
    let detail: Detail
    let fruitCount: Int?
    let yieldKg: Float?

    var hasReliableResult: Bool {
        integrity == .complete
    }

    var showsRecoveryAction: Bool {
        !hasReliableResult
    }

    var statusTitle: String {
        switch integrity {
        case .complete:
            return NSLocalizedString("history.integrity.complete.title", value: "Result Complete", comment: "")
        case .incomplete:
            return NSLocalizedString("history.integrity.incomplete.title", value: "Recovery Needed", comment: "")
        case .invalid:
            return NSLocalizedString("history.integrity.invalid.title", value: "Result Damaged", comment: "")
        }
    }

    var statusIcon: String {
        switch integrity {
        case .complete:
            return "checkmark.circle.fill"
        case .incomplete:
            return "exclamationmark.triangle.fill"
        case .invalid:
            return "xmark.octagon.fill"
        }
    }

    /// 结果不可用时的本地化解释：说明是哪一步没落盘，以及果数与产量为什么不可用。
    ///
    /// 标题（`statusTitle`）由档案行的等级标记带出，这里补充具体原因，
    /// 避免把"结果损坏"折叠成一个没有解释的徽标。
    var statusMessage: String? {
        switch detail {
        case .none:
            return nil
        case .missingResult:
            return ScanHistoryRowCopy.localized(
                "history.integrity.incomplete.missing_result",
                value: "The result file is missing. Count and yield are unavailable."
            )
        case .unreadableJSON:
            return ScanHistoryRowCopy.localized(
                "history.integrity.invalid.json",
                value: "The result JSON can't be read. Count and yield are unavailable."
            )
        case .unreadableCSV:
            return ScanHistoryRowCopy.localized(
                "history.integrity.invalid.csv",
                value: "The result CSV can't be read. Count and yield are unavailable."
            )
        case .revisionMismatch:
            return ScanHistoryRowCopy.localized(
                "history.integrity.invalid.revision",
                value: "The result files don't match. Count and yield are unavailable."
            )
        case .incompleteUnknown:
            return ScanHistoryRowCopy.localized(
                "history.integrity.incomplete.unknown",
                value: "The result wasn't fully saved. Count and yield are unavailable."
            )
        case .invalidUnknown:
            return ScanHistoryRowCopy.localized(
                "history.integrity.invalid.unknown",
                value: "The result files can't be verified. Count and yield are unavailable."
            )
        }
    }

    var accessibilityValue: String {
        guard let fruitCount, let yieldKg else {
            /* 原生的 ScanFileRecord 一定有产量数值；读数缺失只发生在
               记录本身不完整时（结果没写全／无法核对），所以这里就是「不可用」。 */
            let unavailable = NSLocalizedString("history.row.metrics_unavailable", value: "Metrics Unavailable", comment: "")
            return "\(statusTitle), \(unavailable)"
        }
        let yieldText = String.localizedStringWithFormat(
            NSLocalizedString("history.row.yield_format", value: "%.1f kg", comment: ""),
            Double(yieldKg)
        )
        return "\(statusTitle), \(L10n.Dashboard.fruitCountLabel(fruitCount)), \(yieldText)"
    }

    init(record: ScanFileRecord) {
        switch record.persistenceState {
        case .complete:
            integrity = .complete
            detail = .none
            fruitCount = record.fruitCount
            yieldKg = record.yieldKg
        case .incomplete:
            integrity = .incomplete
            detail = record.persistenceFailureReason == "orphanPLYDetected"
                ? .missingResult
                : .incompleteUnknown
            fruitCount = nil
            yieldKg = nil
        case .invalid:
            integrity = .invalid
            switch record.persistenceFailureReason {
            case "scanResultJSONFailed":
                detail = .unreadableJSON
            case "scanResultCSVFailed":
                detail = .unreadableCSV
            case "scanResultRevisionMismatch":
                detail = .revisionMismatch
            default:
                detail = .invalidUnknown
            }
            fruitCount = nil
            yieldKg = nil
        }
    }
}

/// 颜色职责：状态色只落在图标上，文字保持墨色，避免用颜色重复表达同一语义。
struct ScanHistoryStatusVisualPolicy: Equatable, Sendable {
    enum ForegroundRole: Equatable, Sendable {
        case semanticAccent
        case primaryText
    }

    let symbolForeground: ForegroundRole
    let titleForeground: ForegroundRole
    let recoverySymbolForeground: ForegroundRole
    let recoveryTextForeground: ForegroundRole

    init() {
        symbolForeground = .semanticAccent
        titleForeground = .primaryText
        recoverySymbolForeground = .semanticAccent
        recoveryTextForeground = .primaryText
    }
}

// MARK: - 档案行

/// 扫描档案行：等级标记 + 树号/时间 + 读数 + 证据动作。
///
/// 结果不可用时，行内必须同时说清三件事：
/// 1. 等级（`InstrumentRecord.tier(for:)`，结构编码在左侧竖线上）；
/// 2. 原因（`statusTitle` + `statusMessage`，来自 `ScanHistoryRecordPresentation`）；
/// 3. 果数与产量不可用（明确的不可用标记）。
///
/// 恢复动作（复扫）不在行内另开按钮：它和另外四个动作一起收在行尾唯一的「更多」菜单里。
struct ScanHistoryRow: View {
    let record: ScanFileRecord
    /// 打开这条归档的详情。身份行是入口；动作按钮留在行外，避免嵌套按钮与重复 AX 动作。
    var onOpen: (() -> Void)? = nil
    /// 树**当前**归属的地块名（与档案页地块筛选同一来源）。
    var plotName: String? = nil
    let onPreview: () -> Void
    let onShare: () -> Void
    let onRescan: () -> Void
    let onMarkReview: () -> Void
    let onDelete: () -> Void
    /// 返回档案列表后要把无障碍焦点放回哪一行（按存档身份）。
    var focusBinding: AccessibilityFocusState<String?>.Binding? = nil

    private var presentation: ScanHistoryRecordPresentation {
        ScanHistoryRecordPresentation(record: record)
    }

    private let statusVisualPolicy = ScanHistoryStatusVisualPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                identityRow
                trailingActions
            }

            if presentation.showsRecoveryAction {
                integrityPanel
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: 身份行

    /// 档案行的身份与读数由 `InstrumentScanRow` 承担（档案版式：树号独占一行、读数独立右列）。
    ///
    /// 无障碍上，这一行是**一条**可朗读元素：标签是归档文件名，
    /// 值里带上树号、地块、时间、存档身份、果数、产量与完整性结论。
    @ViewBuilder
    private var identityRow: some View {
        let identity = InstrumentScanRow(record: record, layout: .archive, plotName: plotName)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.fileURL.lastPathComponent)
            .accessibilityValue(rowAccessibilityValue)

        if let onOpen {
            Button(action: onOpen) {
                identity
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(record.fileURL.lastPathComponent)
            .accessibilityValue(rowAccessibilityValue)
            .accessibilityHint(ScanHistoryRowCopy.openDetailHint)
            .accessibilityIdentifier("historyRow.open")
            .accessibilityAddTraits(.isButton)
            .modifier(ScanHistoryRowFocusModifier(focusBinding: focusBinding, recordID: record.id))
        } else {
            identity
        }
    }

    // MARK: 完整性说明

    /// 等级标题由档案行本身带出（损坏/待恢复），这里补充本地化原因与不可用标记。
    ///
    /// 颜色职责：状态色只落在图标上，文字保持墨色 —— 不用颜色重复表达同一语义。
    private var integrityPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(statusForegroundColor(for: statusVisualPolicy.symbolForeground))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(metricsUnavailable)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusForegroundColor(for: statusVisualPolicy.titleForeground))
                        .fixedSize(horizontal: false, vertical: true)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundColor(Design.Colors.Workspace.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.statusTitle)
            .accessibilityValue(integrityAccessibilityValue)
        }
    }

    // MARK: 动作区

    /// 行尾唯一的操作入口：预览点云 / 复扫 / 分享 / 标记待复核 / 删除都在这一个菜单里。
    ///
    /// 它是身份按钮的**兄弟**而不是子元素 —— 嵌套按钮会同时造成
    /// "点菜单误开详情" 和读屏念两遍同一个动作。
    private var trailingActions: some View {
        Menu {
            Button(action: onPreview) {
                Label(L10n.History.previewPointCloud, systemImage: "cube.transparent")
            }
            Button(action: onRescan) {
                Label(L10n.History.rescanTree, systemImage: "viewfinder")
            }
            .accessibilityHint(
                localized(
                    "history.row.rescan_accessibility_hint",
                    value: "Starts a new scan for this tree. This record's count and yield remain unavailable."
                )
            )
            Button(action: onShare) {
                Label(L10n.History.sharePointCloud, systemImage: "square.and.arrow.up")
            }
            Button(action: onMarkReview) {
                Label(L10n.History.markReview, systemImage: "flag")
            }
            Button(role: .destructive, action: onDelete) {
                Label(L10n.History.deleteRecord, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.History.moreActions)
        .frame(width: Design.Touch.minimumWidth)
    }

    // MARK: 读数与状态

    private var statusIcon: String {
        presentation.statusIcon
    }

    private var statusMessage: String? {
        presentation.statusMessage
    }

    private var statusColor: Color {
        switch presentation.integrity {
        case .complete:
            return Design.Colors.Workspace.accent
        case .incomplete:
            return Design.Colors.Workspace.attention
        case .invalid:
            return Design.Colors.Workspace.failure
        }
    }

    private func statusForegroundColor(
        for role: ScanHistoryStatusVisualPolicy.ForegroundRole
    ) -> Color {
        switch role {
        case .semanticAccent:
            return statusColor
        case .primaryText:
            return Design.Colors.Workspace.ink
        }
    }

    private var metricsUnavailable: String {
        localized("history.row.metrics_unavailable", value: "Metrics Unavailable")
    }

    private var integrityAccessibilityValue: String {
        [statusMessage, metricsUnavailable]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    /// 朗读值与行里看得见的内容一一对应：树号、地块、时间、存档身份、
    /// 果数、果实种类、产量、完整性结论、文件大小。
    private var rowAccessibilityValue: String {
        ScanHistoryRowAccessibility.value(record: record, plotName: plotName)
    }

    private func localized(_ key: String, value: String) -> String {
        ScanHistoryRowCopy.localized(key, value: value)
    }
}

/// 把无障碍焦点挂到某一条归档上（返回档案列表时用它把焦点放回原处）。
///
/// 用 `.accessibilityFocused` 而不是自己造焦点状态：系统的读屏顺序与焦点恢复
/// 都由 VoiceOver 自己管，我们只声明「焦点该落在哪一条」。
struct ScanHistoryRowFocusModifier: ViewModifier {
    var focusBinding: AccessibilityFocusState<String?>.Binding?
    let recordID: String

    func body(content: Content) -> some View {
        if let focusBinding {
            content.accessibilityFocused(focusBinding, equals: recordID)
        } else {
            content
        }
    }
}

// MARK: - 文案

/// 档案行的朗读值与日期文案。
///
/// 档案行有两个宿主（`ScanHistoryRow` 的按钮与共享行组件的档案版式），
/// 播报内容必须一致 —— 这里给同一份构造，两边不再各写一遍。
enum ScanHistoryRowAccessibility {
    /// 行里显示的扫描时间，与朗读值里的时间是同一句。
    static func dateText(for record: ScanFileRecord) -> String {
        record.scanDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// 树的**当前**地块名（与档案页筛选同源），没有就不说。
    static func plotText(_ plotName: String?) -> String? {
        guard let plotName, !plotName.isEmpty else { return nil }
        return plotName
    }

    /// 存档身份：存档编号（原生里就是这份存档的文件名）。
    static func identityText(for record: ScanFileRecord) -> String {
        L10n.History.archiveRecordPrefix + " " + record.id
    }

    /// 这次扫描当时的结果事实：果数 + 果实种类。
    static func extraText(for record: ScanFileRecord) -> String {
        let presentation = ScanHistoryRecordPresentation(record: record)
        var parts: [String] = []
        if let fruitCount = presentation.fruitCount {
            parts.append(L10n.History.fruitCount(fruitCount))
        }
        if !record.fruitType.isEmpty {
            parts.append(record.fruitType)
        }
        return parts.joined(separator: " · ")
    }

    /// 完整朗读值：树号、当前地块、时间、存档身份、果数、果实种类、读数与完整性结论、文件大小。
    ///
    /// 当前地块带一句限定词：它是**现在**的分类，不是这次扫描当时冻结的事实 ——
    /// 两类事实在朗读里也要分得开。
    static func value(record: ScanFileRecord, plotName: String?) -> String {
        let presentation = ScanHistoryRecordPresentation(record: record)
        var parts: [String] = [record.treeID]
        if let plot = plotText(plotName) {
            parts.append("\(L10n.History.currentPlotPrefix) \(plot)")
        }
        parts.append(dateText(for: record))
        parts.append("\(L10n.History.detailRecordLabel) \(record.id)")
        if let fruitCount = presentation.fruitCount {
            parts.append(L10n.History.fruitCount(fruitCount))
        }
        if !record.fruitType.isEmpty {
            parts.append(record.fruitType)
        }
        parts.append(presentation.accessibilityValue)
        parts.append(fileSizeText(for: record))
        return parts.joined(separator: ", ")
    }

    private static func fileSizeText(for record: ScanFileRecord) -> String {
        guard record.fileSizeBytes > 0 else {
            return L10n.History.unknownSize
        }
        let mb = Double(record.fileSizeBytes) / 1_048_576
        return L10n.History.fileSizeMegabytes(mb)
    }
}

private enum ScanHistoryRowCopy {
    static func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }

    static let openDetailHint = localized(
        "history.row.open_detail_hint",
        value: "打开这条归档的详情。"
    )
}
