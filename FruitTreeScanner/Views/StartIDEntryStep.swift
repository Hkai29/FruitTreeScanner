import SwiftUI

struct Step1_IDEntry: View {
    @Binding var treeID: String
    @Binding var isValid: Bool

    @State private var draftTreeID = ""
    @State private var localIsValid = false
    @State private var validationErrorMessage: String?
    @State private var syncTask: Task<Void, Never>?

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
        .onAppear(perform: prepareInitialValue)
        .onDisappear {
            syncImmediately()
            syncTask?.cancel()
        }
        .onChange(of: draftTreeID, perform: schedulePublish)
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

            TextField("例：T001", text: $draftTreeID)
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
                .onSubmit(syncImmediately)

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
        localIsValid ? "可用" : (validationErrorMessage != nil ? "无效" : "必填")
    }

    private var statusColor: Color {
        localIsValid ? Design.Colors.forest : Design.Colors.harvest
    }

    private func prepareInitialValue() {
        if draftTreeID.isEmpty {
            draftTreeID = treeID
        }
        updateLocalValidity(for: draftTreeID)
        syncImmediately()
    }

    private func schedulePublish(_ newValue: String) {
        updateLocalValidity(for: newValue)
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                publish(newValue)
            }
        }
    }

    private func syncImmediately() {
        publish(draftTreeID)
    }

    private func updateLocalValidity(for value: String) {
        let normalized = TreeIdentifierPolicy.normalized(value)
        if normalized.isEmpty {
            localIsValid = false
            validationErrorMessage = nil
        } else if let error = TreeIdentifierPolicy.validationError(for: normalized) {
            localIsValid = false
            validationErrorMessage = error
        } else {
            localIsValid = true
            validationErrorMessage = nil
        }
    }

    private func publish(_ value: String) {
        let normalized = TreeIdentifierPolicy.normalized(value)
        treeID = normalized
        isValid = TreeIdentifierPolicy.isValid(normalized)
    }
}
