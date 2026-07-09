import SwiftUI

struct CalibrationStatisticsCard: View {
    let records: [CalibrationRecord]

    private var metrics: CalibrationValidationMetrics {
        CalibrationValidationMetrics.make(from: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text("误差统计")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()

            if !metrics.hasEvidence {
                Text("暂无校准数据")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Design.Space.md)
            } else {
                statisticsRow
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    private var statisticsRow: some View {
        return HStack(spacing: Design.Space.xl) {
            CalibrationStatBox(
                title: "果数 MAPE",
                value: percentageValue(metrics.countMAPE),
                color: metricColor(metrics.countMAPE)
            )

            CalibrationStatBox(
                title: "产量 MAPE",
                value: percentageValue(metrics.yieldMAPE),
                color: metricColor(metrics.yieldMAPE)
            )

            CalibrationStatBox(
                title: "校准次数",
                value: "\(metrics.recordCount)",
                color: Design.Colors.Dark.glow
            )
        }
    }

    private func percentageValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func metricColor(_ value: Double?) -> Color {
        guard let value else { return Design.Colors.Dark.textSecondary }
        return CalibrationErrorPalette.color(for: value)
    }
}

enum CalibrationErrorPalette {
    static func color(for error: Double) -> Color {
        let absError = abs(error)
        if absError <= 10 { return Design.Colors.Dark.success }
        if absError <= 20 { return Design.Colors.Dark.warning }
        return Design.Colors.Dark.error
    }
}

private struct CalibrationStatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Design.Space.xs) {
            Text(value)
                .font(Design.Typography.title2)
                .foregroundColor(color)

            Text(title)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
