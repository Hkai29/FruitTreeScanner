// PlotEditView.swift
// 地块编辑页面 - 创建和编辑 Plot 对象。
//
// 草稿语义：表单只改本地草稿；保存提交并关闭，取消丢弃草稿。

import SwiftUI

struct PlotEditView: View {
    @Environment(\.dismiss) var dismiss

    private let plot: Plot?
    private let onSave: ((Plot) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#4D7588"

    private var isEditing: Bool {
        plot != nil
    }

    private var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(plot: Plot? = nil, onSave: ((Plot) -> Void)? = nil) {
        self.plot = plot
        self.onSave = onSave
        _name = State(initialValue: plot?.name ?? "")
        _selectedColor = State(initialValue: plot?.colorHex ?? "#4D7588")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TagEntityEditForm(
                    name: $name,
                    selectedColor: $selectedColor,
                    namePlaceholder: L10n.TagManagement.plotPlaceholder
                )
            }
            .workspacePage()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBand
            }
            .navigationTitle(isEditing ? L10n.TagManagement.editPlot : L10n.TagManagement.addPlot)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.cancel) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.Workspace.accent)
                }
            }
        }
    }

    // MARK: - 底部主操作

    private var saveBand: some View {
        VStack(spacing: 0) {
            Button(action: savePlot) {
                Label(L10n.TagManagement.save, systemImage: "checkmark")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .disabled(!isSaveEnabled)
            .opacity(isSaveEnabled ? 1 : 0.5)
            .accessibilityLabel(L10n.TagManagement.save)
            .accessibilityIdentifier("plotManagement.save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Save
    private func savePlot() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var existingPlot = plot {
            existingPlot.name = trimmedName
            existingPlot.colorHex = selectedColor
            onSave?(existingPlot)
        } else {
            let newPlot = Plot(name: trimmedName, colorHex: selectedColor)
            onSave?(newPlot)
        }

        dismiss()
    }
}
