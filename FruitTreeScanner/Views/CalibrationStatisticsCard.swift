import SwiftUI

struct CalibrationStatisticsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    .accessibilityHidden(true)

                Text(L10n.Calibration.statisticsTitle)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()
            }

            Divider()

            if !metrics.hasEvidence {
                Text(L10n.Calibration.noStatistics)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Design.Space.md))
            : AnyLayout(HStackLayout(spacing: Design.Space.xl))

        return layout {
            CalibrationStatBox(
                title: L10n.Calibration.countMAPE,
                value: percentageValue(metrics.countMAPE),
                color: metricColor(metrics.countMAPE)
            )

            CalibrationStatBox(
                title: L10n.Calibration.yieldMAPE,
                value: percentageValue(metrics.yieldMAPE),
                color: metricColor(metrics.yieldMAPE)
            )

            CalibrationStatBox(
                title: L10n.Calibration.calibrationCount,
                value: "\(metrics.recordCount)",
                color: Design.Colors.Dark.glow
            )
        }
        .frame(maxWidth: .infinity)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
