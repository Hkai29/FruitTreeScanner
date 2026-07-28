// FilterChip.swift
// 共享的筛选器芯片组件

import SwiftUI

struct FilterChip<Content: View>: View {
    let title: String
    let isSelected: Bool
    let minimumHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        isSelected: Bool,
        minimumHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isSelected = isSelected
        self.minimumHeight = minimumHeight
        self.content = content
    }

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : Design.Colors.Dark.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: minimumHeight)
            .contentShape(Capsule())
            .background(isSelected ? Design.Colors.earth.opacity(0.22) : Design.Colors.Dark.bgElevated)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Design.Colors.earth.opacity(0.55) : Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}
