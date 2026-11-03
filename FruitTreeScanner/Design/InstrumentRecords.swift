// InstrumentRecords.swift
// 扫描档案记录组件：跨首页 / 档案 / 对比页共用的记录语言。
//
// 一条记录必须同时说清四件事：是哪棵树、什么时候扫的、
// 结论有多可靠、点云证据在哪。等级用结构编码（线的样式），
// 不是靠一排彩色徽章。

import SwiftUI

// MARK: - 档案行版式

/// 档案行的版式变体。
///
/// - `compact`：首页 / 分析 / 对比页共用的紧凑行（树号、时间、读数同层）。
/// - `archive`：档案页专用 —— 树号独占一行，读数独立右列，状态词跟在读数下面。
///
/// 变体是**显式**的：其他调用者继续拿 `compact`，档案页显式要 `archive`。
/// 档案页改版因此不会被动改到首页、分析页与对比页的既有构图。
enum InstrumentScanRowLayout: Equatable, Sendable {
    case compact
    case archive
}

/// 档案版式的字阶（与已认可的原型档案页一致）。
///
/// 三个尺寸都通过 `@ScaledMetric` 绑定：这些数字是**基准值**，
/// 辅助字号下会随系统一起放大，不会把行锁死在固定高度。
enum InstrumentArchiveRowMetrics {
    /// 读数：24pt
    static let reading: CGFloat = 24
    /// 树号：16pt
    static let identity: CGFloat = 16
    /// 辅助信息（时间、地块、存档身份、状态词、单位）：13pt
    static let supporting: CGFloat = 13
}

// MARK: - 档案行

/// 扫描档案行。左侧证据等级竖线 + 树号 + 时间 + 读数。
struct InstrumentScanRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: ScanFileRecord
    /// 版式变体。默认紧凑行；档案页显式使用 `archive`。
    var layout: InstrumentScanRowLayout = .compact
    /// 档案版式需要的上下文：树**当前**归属的地块名。
    ///
    /// 这是当前分类（与档案页地块筛选同一来源），不是扫描当时冻结的快照 ——
    /// 两类事实不能混在一句话里，因此它单独成行，不与这次扫描的结果并列。
    var plotName: String? = nil
    var showsYield: Bool = true
    var showsDate: Bool = true
    var trailingAccessory: AnyView? = nil

    @ScaledMetric(relativeTo: .body) private var readingSize = InstrumentArchiveRowMetrics.reading
    @ScaledMetric(relativeTo: .body) private var identitySize = InstrumentArchiveRowMetrics.identity
    @ScaledMetric(relativeTo: .caption) private var supportingSize = InstrumentArchiveRowMetrics.supporting

    private var presentation: ScanHistoryRecordPresentation { ScanHistoryRecordPresentation(record: record) }
    private var tier: InstrumentRecordTier { InstrumentRecord.tier(for: record) }

    var body: some View {
        switch layout {
        case .compact:
            compactBody
        case .archive:
            archiveBody
        }
    }

    // MARK: 紧凑版（首页 / 分析 / 对比页）

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 12) {
            InstrumentTierMark(style: tier.markStyle, tint: tier.tint, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.treeID)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !record.fruitType.isEmpty {
                        Text(record.fruitType)
                            .font(.caption)
                            .foregroundColor(Design.Colors.Workspace.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if showsDate {
                        Text(record.scanDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(Design.Colors.Workspace.muted)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if showsYield {
                        if let yieldKg = presentation.yieldKg {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", yieldKg))
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundColor(Design.Colors.Workspace.ink)
                                Text("kg")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(Design.Colors.Workspace.secondary)
                            }
                        } else {
                            /* 原生模型里这条记录本身不完整（结果没写全或无法核对），
                               所以读数位不能留一横装作「有个 0」，
                               也不能说「暂无估产」（那是「还没估」，不是「没存全」）。
                               直接说清：果数与产量不可用 —— 与整行朗读值、完整性面板同一句话。 */
                            Text(NSLocalizedString("history.row.metrics_unavailable",
                                                 value: "Metrics Unavailable", comment: ""))
                                .font(.footnote)
                                .foregroundColor(Design.Colors.Workspace.muted)
                        }
                    }
                    if let fruitCount = presentation.fruitCount {
                        // 计数标签本身已包含数字，直接使用完整本地化字符串。
                        Text(L10n.Dashboard.fruitCountLabel(fruitCount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(Design.Colors.Workspace.muted)
                    }
                    Spacer(minLength: 4)
                    trailingAccessory
                }

                if tier != .complete {
                    Text(InstrumentRecord.title(for: record))
                        .font(.caption.weight(.medium))
                        .foregroundColor(tier.tint)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.treeID)
        .accessibilityValue(presentation.accessibilityValue)
    }

    // MARK: 档案版（档案页）

    /// 档案页的行：树号独占一行，读数独立右列，状态词跟读数走。
    ///
    /// 辅助字号下读数列改到身份下面一行 —— 挤在一行会把长树号压成两行缩写，
    /// 那比多一行更难读。
    private var archiveBody: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    archiveIdentity
                    HStack(alignment: .top, spacing: 8) {
                        Spacer(minLength: 0)
                        archiveReading
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    archiveIdentity
                    Spacer(minLength: 8)
                    archiveReading
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.treeID)
        .accessibilityValue(ScanHistoryRowAccessibility.value(record: record, plotName: plotName))
    }

    /// 身份列：等级竖线 + 树号 + 上下文行 + 这次扫描的事实行。
    private var archiveIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            InstrumentTierMark(style: tier.markStyle, tint: tier.tint, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.treeID)
                    .font(.system(size: identitySize, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !archiveContextLine.isEmpty {
                    Text(archiveContextLine)
                        .font(.system(size: supportingSize))
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !archiveExtraText.isEmpty {
                    archiveFacts
                }
            }
        }
    }

    /// 存档身份 + 这次扫描的结果事实。
    ///
    /// 存档编号是文件名，可能很长：默认字号下它单独占一个可截断的位置，
    /// 果数与种类先拿到宽度 —— 密排行里，扫得动的是数字，不是文件名。
    /// 辅助字号下改成上下两行并允许换行：这时「省略号」会把存档身份整个吃掉，
    /// 读屏用户与放大字号的用户都读不到是哪一份存档。
    @ViewBuilder
    private var archiveFacts: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(ScanHistoryRowAccessibility.identityText(for: record))
                    .fixedSize(horizontal: false, vertical: true)
                Text(archiveExtraText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: supportingSize))
            .foregroundColor(Design.Colors.Workspace.muted)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ScanHistoryRowAccessibility.identityText(for: record))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(archiveExtraText)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.system(size: supportingSize))
            .foregroundColor(Design.Colors.Workspace.muted)
        }
    }

    /// 读数列：数字右对齐，单位小一号；下面跟一个状态词。
    ///
    /// 状态词来自**这条记录自己的事实**：落盘完整性 + 既有复核策略。
    /// 档案记录没有 .fused 诊断，所以这里不说「高置信度」——
    /// 那是详情页在真的读到结果文件后才配说的话。
    private var archiveReading: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let yieldKg = presentation.yieldKg {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", yieldKg))
                        .font(.system(size: readingSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Design.Colors.Workspace.ink)
                    Text("kg")
                        .font(.system(size: supportingSize))
                        .foregroundColor(Design.Colors.Workspace.secondary)
                }
            } else {
                /* 没有读数不是零（null ≠ 0）：这里写「不可用」，
                   完整句子「果数与产量不可用」由同行的完整性面板与朗读值给出。 */
                Text(L10n.History.readingUnavailable)
                    .font(.system(size: supportingSize))
                    .foregroundColor(Design.Colors.Workspace.muted)
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(tier.tint)
                    .frame(width: 6, height: 6)
                Text(InstrumentRecord.title(for: record))
                    .font(.system(size: supportingSize))
                    .foregroundColor(tier.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 上下文行：扫描时间 + 树当前归属的地块。
    private var archiveContextLine: String {
        var parts: [String] = []
        if showsDate {
            parts.append(ScanHistoryRowAccessibility.dateText(for: record))
        }
        if let plot = ScanHistoryRowAccessibility.plotText(plotName) {
            parts.append(plot)
        }
        return parts.joined(separator: " · ")
    }

    /// 事实行：存档身份 + 果数 + 果实种类 —— 全是这次扫描当时的事实。
    ///
    /// 存档编号是文件名，可能很长：它单独占一个可截断的位置，
    /// 果数与种类先拿到宽度 —— 密排行里，扫得动的是数字，不是文件名。
    private var archiveExtraText: String {
        ScanHistoryRowAccessibility.extraText(for: record)
    }
}

// MARK: - 测区空板

/// 测区空板：像一张待勘测的图纸 —— 上半是淡测绘网格，下半是干净的说明区。
/// 这是产品的空状态语言，替代通用灰色占位图。
struct InstrumentSurveyPlate<Content: View>: View {
    var gridSpacing: CGFloat = 22
    /// 测绘网格的高度：空板越大，待勘测的"图纸"感越强。
    var gridHeight: CGFloat = 74
    var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            grid
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(height: 0.5)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.Colors.Workspace.surfaceQuiet, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
    }

    private var grid: some View {
        Canvas { context, size in
            let color = Design.Colors.Workspace.line
            var path = Path()
            var x = gridSpacing
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += gridSpacing
            }
            var y = gridSpacing
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += gridSpacing
            }
            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 0.5)
        }
        .frame(height: gridHeight)
        .allowsHitTesting(false)
    }
}

// MARK: - 工具条目

/// 工具条目：图标 + 标题 + 说明，作为两列发丝网格中的一格。
struct InstrumentToolCell: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    var tint: Color = Design.Colors.Workspace.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(0.10))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(Design.Colors.Workspace.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
