// PlotEditView.swift
// 地块编辑页面 - 创建和编辑 Plot 对象

import SwiftUI

// Import TagStore for Plot type - assuming it's in the same module
// If compilation fails, check that TagStore.swift is in the same target

struct PlotEditView: View {
    @Environment(\.dismiss) var dismiss

    private let plot: Plot?
    private let onSave: ((Plot) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#007AFF"

    private let colorOptions = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#007AFF", "#5856D6", "#AF52DE", "#8E8E93"
    ]

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
        _selectedColor = State(initialValue: plot?.colorHex ?? "#007AFF")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        // Name Section
                        nameSection

                        // Color Section
                        colorSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle(isEditing ? "编辑地块" : "添加地块")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.forest)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        savePlot()
                    }
                    .foregroundColor(Design.Colors.forest)
                    .fontWeight(.semibold)
                    .disabled(!isSaveEnabled)
                }
            }
        }
    }

    // MARK: - Name Section
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("名称")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            TextField("输入地块名称", text: $name)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(Design.Space.md)
                .background(Design.Colors.Dark.bgSurface)
                .cornerRadius(Design.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.medium)
                        .stroke(
                            name.isEmpty ? Design.Colors.Dark.glassBorder : Design.Colors.forest.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    // MARK: - Color Section
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("颜色")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Color(hex: "3D3A36"))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Design.Space.md) {
                ForEach(colorOptions, id: \.self) { colorHex in
                    colorCircle(colorHex: colorHex)
                }
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    // MARK: - Color Circle
    private func colorCircle(colorHex: String) -> some View {
        Button {
            selectedColor = colorHex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 44, height: 44)

                if selectedColor == colorHex {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Circle()
                        .strokeBorder(Color(hex: colorHex).opacity(0.5), lineWidth: 5)
                        .frame(width: 52, height: 52)
                }
            }
        }
        .buttonStyle(.plain)
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

#Preview {
    PlotEditView()
}
