// ResultBadgesAndPills.swift
// 置信度徽标与结果计数。

import SwiftUI

/// 置信度徽标：描边小标签 + 状态点。
/// 颜色只表示置信度档位，不表示证据可靠性。
struct ConfidenceBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// 结果计数：标签在上，等宽数字在下。
struct ResultSummaryPill: View {
    let label: String
    let value: String
    var allowsValueWrapping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .instrumentLabel()
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(.title3, design: .default).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(allowsValueWrapping ? nil : 1)
                .minimumScaleFactor(allowsValueWrapping ? 1 : 0.7)
                .fixedSize(horizontal: false, vertical: allowsValueWrapping)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
