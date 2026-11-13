// ImportFileComponents.swift
// 导入页的部件：页首说明、状态面板、规则列表。
//
// 颜色语义：进行中 / 已完成用信号青，真实错误用锈红。
// 深绿只留给结果页的可靠融合证据，这里不使用。
//
// 状态面板沿用既有接口：tint 决定语义色，失败沿用 Design.Colors.error（锈红）。

import SwiftUI

// MARK: - 本页文案

/// 导入页新增文案。沿用仓库惯例：默认值为中文，英文语言包在后续补齐。
enum ImportStrings {
    static let statusLabel = NSLocalizedString(
        "import.section.status",
        value: "导入状态",
        comment: "PLY import status section label"
    )
    static let rulesLabel = NSLocalizedString(
        "import.section.rules",
        value: "导入规则",
        comment: "PLY import rules section label"
    )
}

// MARK: - 页首

struct ImportHeader: View {
    var body: some View {
        Text(L10n.Import.headerSubtitle)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Import.headerTitle)
            .accessibilityValue(L10n.Import.headerSubtitle)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 状态面板

/// 导入状态面板：标题 + 说明 + 可选的进行中指示。
///
/// 进行中用不确定进度指示（真实工作没有可报告的百分比），
/// 不绘制任何编造的进度刻度。
struct ImportStatusPanel: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Design.Colors.Workspace.accent
    var showsProgress: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(0.10))
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            InstrumentNotice(message: message, tone: noticeTone)

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.Import.processingTitle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSurface(cornerRadius: Design.Radius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(message)
        .accessibilityIdentifier("import.status")
    }

    /// 语义色：失败用锈红，其余用信号青。
    private var noticeTone: InstrumentNotice<EmptyView>.Tone {
        tint == Design.Colors.error ? .failure : .accent
    }
}

// MARK: - 规则列表

/// 导入规则：真实的三条导入行为说明。
struct ImportRulesList: View {
    var body: some View {
        InstrumentRowGroup {
            ImportRuleRow(icon: "clock.arrow.circlepath", text: L10n.Import.historyRule)
            DividerLine(inset: 0)
            ImportRuleRow(icon: "doc.badge.gearshape", text: L10n.Import.metadataRule)
            DividerLine(inset: 0)
            ImportRuleRow(icon: "square.on.square", text: L10n.Import.duplicateRule)
        }
    }
}

struct ImportRuleRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.information)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Design.Colors.Workspace.information.opacity(0.10))
                )
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(minHeight: Design.Touch.minimumHeight, alignment: .leading)
    }
}
