import SwiftUI

struct QuickTaggingCard: View {
    let treeID: String
    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus

    @ObservedObject private var tagStore = TagStore.shared
    @State private var didSave = false

    private var selectedPlotName: String {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }?.name ?? "选择地块"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快速标记")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            plotMenu
            tagSelector
            statusSelector
            saveButton
        }
        .padding(16)
        .resultSurface(cornerRadius: 12)
        .padding(.horizontal, 24)
        .onChange(of: selectedPlotId) { _ in didSave = false }
        .onChange(of: selectedTagIds) { _ in didSave = false }
        .onChange(of: selectedStatus) { _ in didSave = false }
    }

    private var plotMenu: some View {
        Menu {
            Button("无地块") {
                selectedPlotId = nil
            }
            if tagStore.plots.isEmpty {
                Button("暂无地块") {}
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
                    .foregroundColor(Design.Colors.earth)
                Text(selectedPlotName)
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Design.Colors.Dark.bgElevated)
            )
        }
        .buttonStyle(.plain)
    }

    private var tagSelector: some View {
        Group {
            if tagStore.tags.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text("暂无标签，可稍后在地块标签中添加")
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Spacer()
                }
                .padding(12)
                .background(Design.Colors.Dark.bgElevated)
                .cornerRadius(10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagStore.tags) { tag in
                            Button {
                                toggleTag(tag.id)
                            } label: {
                                Text(tag.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedTagIds.contains(tag.id)
                                                ? Color(hex: tag.colorHex)
                                                : Design.Colors.Dark.bgElevated)
                                    )
                                    .foregroundColor(selectedTagIds.contains(tag.id) ? .white : Design.Colors.Dark.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var statusSelector: some View {
        HStack(spacing: 8) {
            ForEach(ScanStatus.allCases, id: \.self) { status in
                Button {
                    selectedStatus = status
                } label: {
                    Text(status.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedStatus == status
                                    ? statusColor(for: status)
                                    : Design.Colors.Dark.bgElevated)
                        )
                        .foregroundColor(selectedStatus == status ? .white : Design.Colors.Dark.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var saveButton: some View {
        Button(action: saveAssignment) {
            HStack(spacing: 8) {
                Image(systemName: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 14))
                Text(didSave ? "已保存标记" : "保存标记")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(didSave ? Design.Colors.earth : Design.Colors.forest)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
    }

    private func saveAssignment() {
        tagStore.createOrUpdateAssignment(
            treeId: treeID,
            plotId: selectedPlotId,
            tagIds: Array(selectedTagIds),
            status: selectedStatus
        )
        withAnimation(.easeInOut(duration: 0.18)) {
            didSave = true
        }
    }

    private func statusColor(for status: ScanStatus) -> Color {
        switch status {
        case .notScanned: return Design.Colors.slate
        case .scanned: return Design.Colors.earth
        case .reviewing: return Design.Colors.harvest
        case .completed: return Design.Colors.forest
        }
    }
}
