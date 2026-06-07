// FilterChip.swift
// 共享的筛选器芯片组件

import SwiftUI

struct FilterChip<Content: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let content: () -> Content

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
            .background(isSelected ? Design.Colors.earth.opacity(0.22) : Design.Colors.Dark.bgElevated)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Design.Colors.earth.opacity(0.55) : Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}
