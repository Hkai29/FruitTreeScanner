// PlotEditView.swift
// 地块编辑页面 - 创建和编辑 Plot 对象

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
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                TagEntityEditForm(
                    name: $name,
                    selectedColor: $selectedColor,
                    namePlaceholder: L10n.TagManagement.plotPlaceholder
                )
            }
            .navigationTitle(isEditing ? L10n.TagManagement.editPlot : L10n.TagManagement.addPlot)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.cancel) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.forest)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.TagManagement.save) {
                        savePlot()
                    }
                    .foregroundColor(Design.Colors.forest)
                    .fontWeight(.semibold)
                    .disabled(!isSaveEnabled)
                }
            }
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
