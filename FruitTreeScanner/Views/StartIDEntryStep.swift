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

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 1,
                totalSteps: 5,
                title: "果树编号",
                subtitle: "用于记录、导出和后续对比，建议与果园现场编号一致。"
            )

            inputCard

            StartNoteRow(
                icon: "link",
                text: "编号会写入扫描记录和导出文件，不会影响点云采集本身。",
                tint: Design.Colors.harvest
            )
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack {
                Text("编号")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            TextField("例：T001", text: $draft.value)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, 14)
                .background(Design.Colors.Dark.bgElevated)
                .cornerRadius(8)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textContentType(.none)
                .submitLabel(.next)

            if let error = validationErrorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.harvest)
            }
        }
        .padding(Design.Space.lg)
        .startSurface(cornerRadius: 10)
    }

    private var statusText: String {
        draft.isValid ? "可用" : (validationErrorMessage != nil ? "无效" : "必填")
    }

    private var statusColor: Color {
        draft.isValid ? Design.Colors.forest : Design.Colors.harvest
    }

    private var validationErrorMessage: String? {
        guard !draft.normalizedValue.isEmpty else { return nil }
        return TreeIdentifierPolicy.validationError(for: draft.normalizedValue)
    }
}
