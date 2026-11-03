// Theme+Workspace.swift
// 日光果园工作区：纸面、墨色、发丝线与信号青。
// 采集与点云画布保持深色，见 Theme+Dark.swift。

import SwiftUI

extension Design.Colors {
    /// Daylight reading surfaces. Camera and point-cloud capture retain Dark.
    enum Workspace {
        // —— 纸面 ——
        /// 页面底色。暖中性，在强光下比纯白更耐看。
        static let background = Color(hex: "F4F3EF")
        /// 承载面（卡片、面板、列表组）。
        static let surface = Color(hex: "FFFFFF")
        /// 沉入面（凹陷区、代码块、次级背景）。
        static let inset = Color(hex: "EDEBE5")
        /// 极浅承载面，用于行内次要块。
        static let surfaceQuiet = Color(hex: "FAF9F6")

        // —— 线条 ——
        /// 1px 发丝线。
        static let line = Color(hex: "DFDDD6")
        /// 更弱的分隔线。
        static let lineSoft = Color(hex: "EAE8E2")
        /// 强分隔线（分段、强调边界）。
        static let lineStrong = Color(hex: "C9C6BC")

        // —— 墨色 ——
        static let ink = Color(hex: "151A1C")
        static let secondary = Color(hex: "4C565B")
        static let muted = Color(hex: "5E6A70")
        static let faint = Color(hex: "7E888D")

        // —— 语义色 ——
        /// 信号青：操作、选中、进行中。
        static let accent = Color(hex: "0E6B78")
        static let accentDeep = Color(hex: "0A5560")
        static let accentSoft = Color(hex: "E4F0F1")
        /// 琥珀：产量、待复核。
        static let attention = Color(hex: "8F5B0E")
        static let attentionSoft = Color(hex: "F8EFDC")
        /// 锈红：失败、不可用。
        static let failure = Color(hex: "A3382A")
        static let failureSoft = Color(hex: "F8E8E5")
        /// 深绿：可靠融合证据。
        static let reliable = Color(hex: "2C6A46")
        static let reliableSoft = Color(hex: "E5F0E8")
        /// 钢蓝：中性信息。
        static let information = Color(hex: "3F5B70")
        static let informationSoft = Color(hex: "E8EDF1")
    }
}

extension View {
    /// 承载面：白底 + 发丝描边。取代“圆角卡片 + 投影”。
    func workspaceSurface(cornerRadius: CGFloat = 10, fill: Color = Design.Colors.Workspace.surface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
    }

    /// 页面底：纸面 + 墨色 + 信号青着色。
    func workspacePage(background color: Color = Design.Colors.Workspace.background) -> some View {
        background(color.ignoresSafeArea())
            .foregroundColor(Design.Colors.Workspace.ink)
            .tint(Design.Colors.Workspace.accent)
            .preferredColorScheme(.light)
    }

    /// 仪器式小标签：小字号、半粗、轻微字距、次级墨色。
    func instrumentLabel() -> some View {
        font(.system(.caption2, design: .default).weight(.semibold))
            .tracking(0.6)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Buttons

/// 主操作：实心信号青，用于页面唯一的主要动作。
struct WorkspacePrimaryButtonStyle: ButtonStyle {
    var tint: Color = Design.Colors.Workspace.accent
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 54)
            .background(tint, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

/// 次操作：描边，用于与主操作并列的备选。
struct WorkspaceSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Design.Colors.Workspace.ink
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

/// 轻量按钮：仅文字与图标，用于行内与次级跳转。
struct WorkspaceQuietButtonStyle: ButtonStyle {
    var tint: Color = Design.Colors.Workspace.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(tint)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

enum WorkspaceText {
    static var orchard: String { NSLocalizedString("workspace.orchard", value: "果园空间", comment: "") }
    static var archive: String { NSLocalizedString("workspace.archive", value: "档案", comment: "") }
    static var analysis: String { NSLocalizedString("workspace.analysis", value: "分析", comment: "") }
    static var subtitle: String { NSLocalizedString("workspace.subtitle", value: "树木位置 · 点云档案 · 估产依据", comment: "") }
    static var noLocations: String { NSLocalizedString("workspace.no_locations", value: "从第一棵树开始", comment: "") }
    static var locationExplanation: String { NSLocalizedString("workspace.location_explanation", value: "带定位的完整扫描会显示在这里。\n已有的无定位档案仍可正常浏览。", comment: "") }
    static var recentTree: String { NSLocalizedString("workspace.recent_tree", value: "最近扫描", comment: "") }
    static var evidence: String { NSLocalizedString("workspace.evidence", value: "打开点云", comment: "") }
    static var review: String { NSLocalizedString("workspace.review", value: "待复核", comment: "") }
    static var estimatedYield: String { NSLocalizedString("workspace.estimated_yield", value: "估算产量", comment: "") }
    static var frameTrees: String { NSLocalizedString("workspace.frame_trees", value: "显示全部树木", comment: "") }
    static var openMap: String { NSLocalizedString("workspace.open_map", value: "展开地图", comment: "") }
    static var archiveExplanation: String { NSLocalizedString("workspace.archive_explanation", value: "按树木追溯每一次扫描与点云证据。", comment: "") }
    static var analysisExplanation: String { NSLocalizedString("workspace.analysis_explanation", value: "从完整扫描记录查看产量与变化。", comment: "") }
    static var noScansToday: String { NSLocalizedString("workspace.no_scans_today", value: "今日暂无完整扫描", comment: "") }
    static var openArchives: String { NSLocalizedString("workspace.open_archives", value: "查看已有档案", comment: "") }
    static var chooseArchive: String { NSLocalizedString("workspace.choose_archive", value: "切换扫描档案", comment: "") }
}
