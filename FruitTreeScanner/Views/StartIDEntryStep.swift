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
                title: L10n.StartSetup.text(.identifierTitle),
                subtitle: L10n.StartSetup.text(.identifierSubtitle)
            )

            inputCard

            StartNoteRow(
                icon: "link",
                text: L10n.StartSetup.text(.identifierNote),
                tint: Design.Colors.harvest
            )
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack {
                Text(L10n.StartSetup.text(.identifierFieldLabel))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            TextField(L10n.StartSetup.text(.identifierPlaceholder), text: $draft.value)
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
        draft.isValid
            ? L10n.StartSetup.text(.identifierAvailable)
            : (
                validationErrorMessage != nil
                    ? L10n.StartSetup.text(.identifierInvalid)
                    : L10n.StartSetup.text(.identifierRequired)
            )
    }

    private var statusColor: Color {
        draft.isValid ? Design.Colors.forest : Design.Colors.harvest
    }

    private var validationErrorMessage: String? {
        guard !draft.normalizedValue.isEmpty, let issue = draft.validationIssue else { return nil }
        return L10n.StartSetup.validationError(for: issue)
    }
}
