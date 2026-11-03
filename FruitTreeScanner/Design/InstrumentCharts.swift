// InstrumentCharts.swift
// 只画真实数据的图表。没有记录支撑的曲线、插图、覆盖率一律不画。
//
// 图形遵循仪器读数习惯：基线明确、坐标克制、等宽数字、无网格噪声。

import SwiftUI

// MARK: - 趋势

/// 产量趋势：面积折线 + 端点读数。
struct InstrumentTrendChart: View {
    struct Point: Identifiable {
        let id: Int
        let label: String
        let value: Double
    }

    let points: [Point]
    var tint: Color = Design.Colors.Workspace.accent
    var showsAxisLabels: Bool = true

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 0, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if showsAxisLabels, points.count > 1 {
                axis
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var chart: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let step = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
            let baseY = size.height

            ZStack(alignment: .bottomLeading) {
                // 基线
                Rectangle()
                    .fill(Design.Colors.Workspace.line)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Path { path in
                    guard points.count > 1 else { return }
                    for (index, point) in points.enumerated() {
                        let x = CGFloat(index) * step
                        let y = baseY - CGFloat(point.value / maxValue) * (size.height - 6)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                Path { path in
                    guard points.count > 1 else { return }
                    for (index, point) in points.enumerated() {
                        let x = CGFloat(index) * step
                        let y = baseY - CGFloat(point.value / maxValue) * (size.height - 6)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: size.width, y: baseY))
                    path.addLine(to: CGPoint(x: 0, y: baseY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 端点
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = CGFloat(index) * step
                    let y = baseY - CGFloat(point.value / maxValue) * (size.height - 6)
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: 110)
    }

    private var axis: some View {
        HStack(spacing: 0) {
            Text(points.first?.label ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(points.last?.label ?? "")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(Design.Colors.Workspace.muted)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return points.first.map { "\($0.label) \($0.value)" } ?? ""
        }
        return "\(first.label) \(first.value), \(last.label) \(last.value)"
    }
}

// MARK: - 条形

/// 横向条形：分类读数。条长按最大值归一。
struct InstrumentBarChart: View {
    struct Bar: Identifiable {
        let id: String
        let label: String
        let value: Double
        var displayValue: String
        var tint: Color?
    }

    let bars: [Bar]
    var defaultTint: Color = Design.Colors.Workspace.accent

    private var maxValue: Double {
        max(bars.map(\.value).max() ?? 0, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bars) { bar in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(bar.label)
                            .font(.footnote)
                            .foregroundColor(Design.Colors.Workspace.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(bar.displayValue)
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(Design.Colors.Workspace.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Design.Colors.Workspace.inset)
                            Rectangle()
                                .fill(bar.tint ?? defaultTint)
                                .frame(
                                    width: proxy.size.width * CGFloat(bar.value / maxValue)
                                )
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bar.label)
                .accessibilityValue(bar.displayValue)
            }
        }
    }
}
