// FlowLayout.swift
// Wraps child views into rows for chip-style controls.
//
// 排布规则：一行放不下就换行，行内间距固定，不在行尾留下多余间距。
// 当父容器没有给出确定宽度时（例如被放进自适应尺寸的容器），
// 退化为"按自然宽度单行排布"，避免子视图被裁切或溢出。

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: FlowLayout.boundedWidth(proposal.width), subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: FlowLayout.boundedWidth(bounds.width), subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    /// 只有有限的正宽度才是可用宽度；`nil` 与 `infinity` 都按"宽度未知"处理。
    private static func boundedWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite, width > 0 else { return nil }
        return width
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat?, subviews: Subviews, spacing: CGFloat) {
            let limit = width ?? .greatestFiniteMagnitude
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var widestRow: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > limit, x > 0 {
                    widestRow = max(widestRow, x - spacing)
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            widestRow = max(widestRow, x - spacing)
            self.size = CGSize(width: width ?? widestRow, height: y + rowHeight)
        }
    }
}
