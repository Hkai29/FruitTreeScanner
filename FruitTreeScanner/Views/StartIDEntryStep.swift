// StartIDEntryStep.swift
// 第 1 步：果树编号。
//
// 编号是这次扫描唯一的"人工锚点"，因此输入框用等宽字形，
// 格式反馈直接来自 TreeIdentifierPolicy，不另立校验规则。

import SwiftUI

struct StartTreeIdentifierDraft {
    var value: String

    init(value: String = "") {
        self.value = value
    }

    var normalizedValue: String {
        TreeIdentifierPolicy.normalized(value)
    }

    var validationIssue: TreeIdentifierPolicy.ValidationIssue? {
        TreeIdentifierPolicy.validationIssue(for: normalizedValue)
    }

    var isValid: Bool {
        validationIssue == nil
    }

    var validatedValue: String? {
        guard isValid else { return nil }
        return normalizedValue
    }
}

struct Step1_IDEntry: View {
    @Binding var draft: StartTreeIdentifierDraft
    /// 果园里已经归档过的编号：点击即可沿用，避免重复录入。
    var existingTreeIDs: [String] = []

    private static let existingTitle = NSLocalizedString(
        "start.setup.identifier.existing_title",
        value: "已有编号",
        comment: "Section listing tree identifiers already filed in this orchard"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            inputPanel

            if !existingTreeIDs.isEmpty {
                existingSection
            }

            StartNoteRow(
                icon: "link",
                text: L10n.StartSetup.text(.identifierNote),
                tone: .neutral
            )
        }
    }

    // MARK: - 输入

    private var inputPanel: some View {
        InstrumentPanel(
            label: L10n.StartSetup.text(.identifierFieldLabel),
            trailing: AnyView(
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                InstrumentTextField(
                    placeholder: L10n.StartSetup.text(.identifierPlaceholder),
                    text: $draft.value,
                    keyboard: .asciiCapable,
                    isMonospaced: true
                )
                .accessibilityLabel(L10n.StartSetup.text(.identifierFieldLabel))

                if let error = validationErrorMessage {
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.failure)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(L10n.StartSetup.text(.identifierSubtitle))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 已有编号

    private var existingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionLabel(title: Self.existingTitle)

            FlowLayout(spacing: 8) {
                ForEach(existingTreeIDs, id: \.self) { treeID in
                    existingChip(treeID)
                }
            }
        }
    }

    private func existingChip(_ treeID: String) -> some View {
        Button {
            draft.value = treeID
        } label: {
            Text(treeID)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(Design.Colors.Workspace.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(treeID)
    }

    // MARK: - 状态

    private var statusText: String {
        draft.isValid
            ? L10n.StartSetup.text(.identifierAvailable)
            : (
                validationErrorMessage != nil
                    ? L10n.StartSetup.text(.identifierInvalid)
                    : L10n.StartSetup.text(.identifierRequired)
            )
    }

    private var statusColor: Color {
        draft.isValid ? Design.Colors.Workspace.accent :
            (validationErrorMessage == nil ? Design.Colors.Workspace.secondary : Design.Colors.Workspace.failure)
    }

    private var validationErrorMessage: String? {
        guard !draft.normalizedValue.isEmpty, let issue = draft.validationIssue else { return nil }
        return L10n.StartSetup.validationError(for: issue)
    }
}
