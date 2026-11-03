// FilterChip.swift
// 共享的筛选器芯片组件：菜单型筛选片。
//
// 外观与 `InstrumentChip` 同一套语言（信号青实底 / 发丝线描边 / 6pt 圆角），
// 区别只在于它是一个菜单：右侧带下拉箭头，点击后展开选项。
//
// 无障碍：芯片的无障碍标签就是标题本身（箭头是装饰图形），
// 这样外部可以按标题定位并激活这个菜单。

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
            HStack(spacing: 5) {
                Text(title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Design.Colors.Workspace.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : Design.Colors.Workspace.muted)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: max(Design.Touch.minimumHeight, minimumHeight ?? Design.Touch.minimumHeight))
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(isSelected ? Design.Colors.Workspace.accent : Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Design.Colors.Workspace.line,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
