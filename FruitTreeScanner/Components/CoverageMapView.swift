// CoverageMapView.swift
// 覆盖度面板：把“这次扫描拍到了多少、拍得均不均匀”做成仪器读数。
//
// 五个分项（用时、冠层、角度、均匀度、稳定性）共用同一色相，
// 颜色只承载整体状态，避免彩虹色阶。

import SwiftUI

struct CoverageMapView: View {
    let completion: ScanCompletion

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                mainGauge
                statusInfo
            }

            if completion.overall > 0.1 {
                DividerLine(color: Design.Colors.Dark.glassBorder)
                scoreIndicators
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Dark.bgSurface.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
    }

    // MARK: - 主仪表

    /// 刻度环：10 段刻度，按真实整体覆盖率点亮。
    private var mainGauge: some View {
        ZStack {
            Circle()
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 5)
                .frame(width: 58, height: 58)

            Circle()
                .trim(from: 0, to: CGFloat(completion.overall))
                .stroke(
                    statusColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .butt)
                )
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: completion.overall)

            VStack(spacing: 1) {
                Text("\(completion.overallPercent)%")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(completion.formattedDuration)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.ScanCoverage.coverage)
        .accessibilityValue(
            L10n.ScanCoverage.coverageAccessibilityValue(
                percent: completion.overallPercent,
                duration: completion.formattedDuration
            )
        )
    }

    private var statusInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.ScanCoverage.statusTitle(for: completion.coverageStatus))
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(L10n.ScanCoverage.statusHint(for: completion.coverageHint))
                .font(.system(.caption, design: .default))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if completion.voxelCount > 0 {
                Text(L10n.ScanCoverage.spatialSamples(completion.voxelCount))
                    .font(.system(size: 10, design: .default))
                    .foregroundColor(Design.Colors.Dark.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 分项

    private var scoreIndicators: some View {
        HStack(spacing: 8) {
            ScoreIndicator(
                label: L10n.ScanCoverage.metricDuration,
                value: completion.timeScore,
                color: Design.Colors.Dark.glow
            )
            ScoreIndicator(
                label: L10n.ScanCoverage.metricCanopy,
                value: completion.voxelScore,
                color: Design.Colors.Dark.glow
            )
            ScoreIndicator(
                label: L10n.ScanCoverage.metricAngle,
                value: completion.angleCoverageScore,
                color: Design.Colors.Dark.glow
            )
            ScoreIndicator(
                label: L10n.ScanCoverage.metricUniformity,
                value: completion.angleUniformityScore,
                color: Design.Colors.Dark.glow
            )
            ScoreIndicator(
                label: L10n.ScanCoverage.metricStability,
                value: completion.stabilityScore,
                color: statusColor
            )
        }
    }

    private var statusColor: Color {
        switch completion.coverageStatus {
        case .complete: return Design.Colors.Dark.success
        case .good: return Design.Colors.Dark.glow
        case .continueScanning: return Design.Colors.Dark.warning
        case .insufficient: return Design.Colors.Dark.error
        }
    }
}

private struct ScoreIndicator: View {
    let label: String
    let value: Float
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Design.Colors.Dark.glassBorder)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(height: geo.size.height * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(width: 22, height: 22)

            Text(label)
                .font(.system(size: 9, design: .default))
                .foregroundColor(Design.Colors.Dark.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(L10n.ScanCoverage.scoreAccessibilityValue(value))
    }
}
