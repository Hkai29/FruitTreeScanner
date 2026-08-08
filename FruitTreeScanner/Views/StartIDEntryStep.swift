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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            inputHeader

            TextField(L10n.StartSetup.text(.identifierPlaceholder), text: $draft.value)
                .font(.title3.weight(.semibold).monospaced())
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, 14)
                .frame(minHeight: layoutPolicy.minimumControlHeight)
                .background(Design.Colors.Dark.bgElevated)
                .cornerRadius(8)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textContentType(.none)
                .submitLabel(.next)

            if let error = validationErrorMessage {
                Text(error)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Design.Colors.harvest)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Design.Space.lg)
        .startSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private var inputHeader: some View {
        switch layoutPolicy.arrangement {
        case .horizontal:
            HStack {
                inputLabel
                Spacer()
                inputStatus
            }
        case .vertical:
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                inputLabel
                inputStatus
            }
        }
    }

    private var inputLabel: some View {
        Text(L10n.StartSetup.text(.identifierFieldLabel))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    private var inputStatus: some View {
        Text(statusText)
            .font(.caption.weight(.semibold))
            .foregroundColor(statusColor)
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
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
