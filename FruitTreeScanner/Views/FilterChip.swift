// FilterChip.swift
// 共享的筛选器芯片组件

import SwiftUI

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let menu: () -> Menu<Void, Never>

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: Design.Space.xs) {
                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(isSelected ? .white : Design.Colors.charcoal)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : Design.Colors.slate)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm + 2)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.forest : Design.Colors.bgSurface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Design.Colors.pebble, lineWidth: 1)
            )
        }
    }
}
