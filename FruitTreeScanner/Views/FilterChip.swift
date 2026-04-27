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
                    .foregroundColor(isSelected ? .white : Color(hex: "3D3A36"))

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : Color(hex: "8E8E93"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color(hex: "007AFF").opacity(0.1) : Color(hex: "F2F2F7"))
            .foregroundColor(isSelected ? Color(hex: "007AFF") : Color(hex: "1C1C1E"))
            .clipShape(Capsule())
        }
    }
}
