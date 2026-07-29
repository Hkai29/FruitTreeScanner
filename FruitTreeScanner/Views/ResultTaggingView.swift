import SwiftUI

struct QuickTaggingCard: View {
    let treeID: String
    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus

    @ObservedObject private var tagStore = TagStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var didSave = false

    private var selectedPlotName: String {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }?.name
            ?? L10n.QuickTagging.plotPlaceholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.QuickTagging.title)
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityAddTraits(.isHeader)

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
                    .foregroundColor(Design.Colors.earth)
                    .accessibilityHidden(true)
                Text(selectedPlotName)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: Design.Touch.minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Design.Colors.Dark.bgElevated)
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
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .accessibilityHidden(true)
                    Text(L10n.QuickTagging.noTags)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(12)
                .background(Design.Colors.Dark.bgElevated)
                .cornerRadius(10)
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
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected
                                                ? Color(hex: tag.colorHex)
                                                : Design.Colors.Dark.bgElevated)
                                    )
                                    .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
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
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected
                                    ? statusColor(for: status)
                                    : Design.Colors.Dark.bgElevated)
                        )
                        .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
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
                Image(systemName: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.body)
                    .accessibilityHidden(true)
                Text(didSave ? L10n.QuickTagging.saved : L10n.QuickTagging.save)
                    .font(.body.weight(.medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Design.Touch.minimumHeight)
            .padding(.vertical, 4)
            .background(didSave ? Design.Colors.earth : Design.Colors.forest)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didSave ? L10n.QuickTagging.saved : L10n.QuickTagging.save)
        .accessibilityHint(L10n.QuickTagging.saveHint)
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
