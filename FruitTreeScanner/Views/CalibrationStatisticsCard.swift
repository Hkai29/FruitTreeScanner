// CalibrationStatisticsCard.swift
// 误差统计：数值全部由 CalibrationValidationMetrics 从真实记录算出，
// 这里只负责呈现，不做任何再计算或硬编码。

import SwiftUI

struct CalibrationStatisticsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let records: [CalibrationRecord]

    private var metrics: CalibrationValidationMetrics {
        CalibrationValidationMetrics.make(from: records)
    }

    var body: some View {
        InstrumentPanel(
            label: L10n.Calibration.statisticsTitle,
            systemImage: "chart.xyaxis.line"
        ) {
            if !metrics.hasEvidence {
                Text(L10n.Calibration.noStatistics)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                statisticsRow
            }
        }
    }

    private var statisticsRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(spacing: 16))

        return layout {
            InstrumentDatum(
                label: L10n.Calibration.countMAPE,
                value: percentageValue(metrics.countMAPE),
                tint: metricColor(metrics.countMAPE)
            )

            InstrumentDatum(
                label: L10n.Calibration.yieldMAPE,
                value: percentageValue(metrics.yieldMAPE),
                tint: metricColor(metrics.yieldMAPE)
            )

            InstrumentDatum(
                label: L10n.Calibration.calibrationCount,
                value: "\(metrics.recordCount)",
                unit: "次",
                tint: Design.Colors.Workspace.ink
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func percentageValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func metricColor(_ value: Double?) -> Color {
        guard let value else { return Design.Colors.Workspace.secondary }
        return CalibrationErrorPalette.color(for: value)
    }
}

enum CalibrationErrorPalette {
    static func color(for error: Double) -> Color {
        let absError = abs(error)
        if absError <= 10 { return Design.Colors.Workspace.accent }
        if absError <= 20 { return Design.Colors.Workspace.attention }
        return Design.Colors.Workspace.failure
    }
}
