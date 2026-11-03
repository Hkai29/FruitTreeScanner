// ImportFileContentView.swift
// 导入页内容：状态 + 规则，底部一条主操作带。
//
// 布局遵循仪器工作区：纸面底、20pt 页边距、最大 1080 居中、发丝线分区。
// 状态完全来自既有的 ImportStatus：等待、选择文件、处理中、成功、失败。

import SwiftUI

struct ImportFileContentView: View {
    let status: ImportStatus
    let isProcessing: Bool
    let onImportTap: () -> Void

    private let contentWidth: CGFloat = 1080

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ImportHeader()

                statusSection

                rulesSection
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBand
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: ImportStrings.statusLabel)
            ImportStatusView(status: status)
        }
    }

    // MARK: - 规则

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: ImportStrings.rulesLabel)
            ImportRulesList()
        }
    }

    // MARK: - 底部主操作

    private var actionBand: some View {
        VStack(spacing: 0) {
            Button(action: onImportTap) {
                Label(buttonTitle, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .disabled(isProcessing)
            .opacity(isProcessing ? 0.6 : 1)
            .accessibilityLabel(buttonTitle)
            .accessibilityHint(L10n.Import.selectButtonHint)
            .accessibilityIdentifier("import.selectFile")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    private var buttonTitle: String {
        status.isSuccess ? L10n.Import.continueButton : L10n.Import.selectButton
    }
}
