import SwiftUI

/// 快速标记的保存编排。
/// 写入是异步的：排队成功不等于落盘成功。
/// 单独抽出来是为了能直接测「落盘之前不许说已保存」，而不用挂起整棵视图树。
@MainActor
final class QuickTaggingSaveController: ObservableObject {
    enum State: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let store: TagStore
    private var saveTask: Task<Void, Never>?

    init(store: TagStore) {
        self.store = store
    }

    /// 排队保存，并等到快照真的写入本地存储才回报成功。
    func save(treeId: String, plotId: UUID?, tagIds: [UUID], status: ScanStatus) {
        saveTask?.cancel()
        guard store.createOrUpdateAssignment(
            treeId: treeId,
            plotId: plotId,
            tagIds: tagIds,
            status: status
        ) else {
            state = .failed(L10n.QuickTagging.saveRejected)
            return
        }
        state = .saving
        saveTask = Task { @MainActor [weak self] in
            await self?.store.waitForPendingSave()
            guard let self else { return }
            /* 这条保存可能已经被作废：用户在写入期间改了选择，
               reset() 取消了本任务。等存储写完后任务仍会恢复执行，
               所以这里必须再看一次取消状态 —— 作废的保存不许再写「已保存」。 */
            guard !Task.isCancelled else { return }
            if let failure = self.store.lastPersistError {
                Log.general.error("Quick tagging save failed: \(failure)")
                self.state = .failed(L10n.QuickTagging.saveFailed)
            } else {
                self.state = .saved
            }
        }
    }

    /// 等当前这次写入结束（测试与「保存中」状态用）。
    func waitForCompletion() async {
        await saveTask?.value
    }

    /// 选择项变化后回到未保存状态。
    /// 保留任务句柄（已取消），这样「等这次保存结束」仍能等到它真正退出。
    func reset() {
        saveTask?.cancel()
        state = .idle
    }
}

struct QuickTaggingCard: View {
    let treeID: String
    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus
    @ObservedObject var tagStore: TagStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var saveController: QuickTaggingSaveController

    /// 保存编排必须绑到这张卡片正在显示的那份存储。
    /// 之前编排里写死了 TagStore.shared：隔离存储下保存会写进标准偏好，
    /// 页面显示的那棵树却没被写到 —— 现有测试因此失败。
    init(
        treeID: String,
        selectedPlotId: Binding<UUID?>,
        selectedTagIds: Binding<Set<UUID>>,
        selectedStatus: Binding<ScanStatus>,
        tagStore: TagStore = .shared
    ) {
        self.treeID = treeID
        _selectedPlotId = selectedPlotId
        _selectedTagIds = selectedTagIds
        _selectedStatus = selectedStatus
        self.tagStore = tagStore
        _saveController = StateObject(wrappedValue: QuickTaggingSaveController(store: tagStore))
    }

    private var saveState: QuickTaggingSaveController.State { saveController.state }

    private var selectedPlotName: String {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }?.name
            ?? L10n.QuickTagging.plotPlaceholder
    }

    var body: some View {
        ResultSectionCard(
            title: L10n.QuickTagging.title,
            icon: "tag",
            color: Design.Colors.Workspace.accent
        ) {
            VStack(alignment: .leading, spacing: 12) {
                plotMenu
                tagSelector
                statusSelector
                saveButton
                saveFailureNote
            }
        }
        .onChange(of: selectedPlotId) { _ in saveController.reset() }
        .onChange(of: selectedTagIds) { _ in saveController.reset() }
        .onChange(of: selectedStatus) { _ in saveController.reset() }
    }

    private var plotMenu: some View {
        Menu {
            Button(L10n.QuickTagging.noPlot) {
                selectedPlotId = nil
            }
            if tagStore.plots.isEmpty {
                Button(L10n.QuickTagging.noPlotsAvailable) {}
                    .disabled(true)
            } else {
                ForEach(tagStore.plots) { plot in
                    Button(plot.name) {
                        selectedPlotId = plot.id
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "map")
                    .foregroundColor(Design.Colors.Workspace.information)
                    .accessibilityHidden(true)
                Text(selectedPlotName)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: Design.Touch.minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.inset)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.QuickTagging.plotLabel)
        .accessibilityValue(selectedPlotName)
    }

    private var tagSelector: some View {
        Group {
            if tagStore.tags.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .accessibilityHidden(true)
                    Text(L10n.QuickTagging.noTags)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(12)
                .background(Design.Colors.Workspace.inset, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagStore.tags) { tag in
                            let isSelected = selectedTagIds.contains(tag.id)
                            Button {
                                toggleTag(tag.id)
                            } label: {
                                selectionLabel(tag.name, isSelected: isSelected)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: Design.Touch.minimumHeight)
                                    .background(
                                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                                            .fill(isSelected
                                                ? Color(hex: tag.colorHex)
                                                : Design.Colors.Workspace.inset)
                                    )
                                    .foregroundColor(isSelected ? .white : Design.Colors.Workspace.ink)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tag.name)
                            .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
                            .accessibilityHint(L10n.QuickTagging.tagHint)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private var statusSelector: some View {
        LazyVGrid(columns: statusColumns, alignment: .leading, spacing: 8) {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                let isSelected = selectedStatus == status
                Button {
                    selectedStatus = status
                } label: {
                    selectionLabel(
                        L10n.QuickTagging.statusName(for: status),
                        isSelected: isSelected
                    )
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: Design.Touch.minimumHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                                .fill(isSelected
                                    ? statusColor(for: status)
                                    : Design.Colors.Workspace.inset)
                        )
                        .foregroundColor(isSelected ? .white : Design.Colors.Workspace.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.QuickTagging.statusName(for: status))
                .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
                .accessibilityHint(L10n.QuickTagging.statusHint)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var saveButton: some View {
        Button(action: saveAssignment) {
            HStack(spacing: 8) {
                Image(systemName: saveIconName)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(saveLabel)
                    .font(.body.weight(.medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Design.Touch.minimumHeight)
            .padding(.vertical, 4)
            .background(saveState == .saved ? Design.Colors.Workspace.information : Design.Colors.Workspace.accent)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(saveState == .saving)
        .accessibilityLabel(saveLabel)
        .accessibilityHint(L10n.QuickTagging.saveHint)
    }

    /// 保存失败时把原因写在按钮下面，并保留按钮本身作为重试入口。
    @ViewBuilder
    private var saveFailureNote: some View {
        if case .failed(let message) = saveState {
            Text(message)
                .font(.footnote)
                .foregroundColor(Design.Colors.Workspace.failure)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quickTagging.saveError")
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle: return L10n.QuickTagging.save
        case .saving: return L10n.QuickTagging.saving
        case .saved: return L10n.QuickTagging.saved
        case .failed: return L10n.QuickTagging.save
        }
    }

    private var saveIconName: String {
        switch saveState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 112
                ),
                spacing: 8
            )
        ]
    }

    private func selectionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
    }

    private func saveAssignment() {
        /* 写入是异步的：先确认这次标记被接受，再等它真的落盘。
           中途失败要说清楚并留着重试入口，不能停在「已保存」。 */
        saveController.save(
            treeId: treeID,
            plotId: selectedPlotId,
            tagIds: Array(selectedTagIds),
            status: selectedStatus
        )
    }

    private func statusColor(for status: ScanStatus) -> Color {
        switch status {
        case .notScanned: return Design.Colors.slate
        case .scanned: return Design.Colors.earth
        case .reviewing: return Design.Colors.Workspace.accent
        case .completed: return Design.Colors.Workspace.accent
        }
    }
}
