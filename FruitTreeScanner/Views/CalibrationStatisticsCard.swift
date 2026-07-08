import SwiftUI

struct CalibrationStatisticsCard: View {
    let records: [CalibrationRecord]

    private var validRecords: [CalibrationRecord] {
        records.filter { $0.countError != nil || $0.yieldError != nil }
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

            if validRecords.isEmpty {
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
        let countErrors = validRecords.compactMap { $0.countError }
        let avgCountError = countErrors.isEmpty ? 0 : countErrors.reduce(0, +) / Double(countErrors.count)
        let yieldErrors = validRecords.compactMap { $0.yieldError }
        let avgYieldError = yieldErrors.isEmpty ? 0 : yieldErrors.reduce(0, +) / Double(yieldErrors.count)

        return HStack(spacing: Design.Space.xl) {
            CalibrationStatBox(
                title: "计数误差",
                value: String(format: "%.1f%%", avgCountError),
                color: CalibrationErrorPalette.color(for: avgCountError)
            )

            CalibrationStatBox(
                title: "产量误差",
                value: String(format: "%.1f%%", avgYieldError),
                color: CalibrationErrorPalette.color(for: avgYieldError)
            )

            CalibrationStatBox(
                title: "校准次数",
                value: "\(validRecords.count)",
                color: Design.Colors.Dark.glow
            )
        }
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
