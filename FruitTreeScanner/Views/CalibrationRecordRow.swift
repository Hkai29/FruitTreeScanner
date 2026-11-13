// CalibrationRecordRow.swift
// 一条校准记录：估算值、实测值、两者的误差，以及这条记录是否仍可用于自动校准。
//
// 误差值直接取自 CalibrationRecord.countError / yieldError，不做二次处理。

import SwiftUI

struct CalibrationRecordRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: CalibrationRecord
    let isDeleteEnabled: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            detailRow
            Text(calibrationStatusText)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }

    private var calibrationStatusText: String {
        if record.algorithmRevision == YieldAlgorithmRevision.current,
           record.calibrationContext != nil {
            return NSLocalizedString(
                "calibration.record.context_matched_if_current",
                value: "Applies only when the model and settings match",
                comment: "Calibration record with a captured algorithm context"
            )
        }
        return NSLocalizedString(
            "calibration.record.legacy_reference",
            value: "Kept for comparison; excluded from automatic calibration",
            comment: "Legacy or unversioned calibration record"
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.Calibration.recordTitle(treeID: record.treeID))
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(formatDate(record.scanDate))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                valuesContent
                errorAndDeleteActions
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                valuesContent
                Spacer(minLength: 8)
                errorAndDeleteActions
            }
        }
    }

    @ViewBuilder
    private var valuesContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            estimatedValues

            if record.manualFruitCount != nil || record.actualYieldKg != nil {
                actualValues
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                estimatedValues

                if record.manualFruitCount != nil || record.actualYieldKg != nil {
                    actualValues
                }
            }
        }
    }

    private var errorAndDeleteActions: some View {
        HStack(spacing: 12) {
            if let countError = record.countError {
                ErrorBadge(label: L10n.Calibration.countError, error: countError)
            }
            if let yieldError = record.yieldError {
                ErrorBadge(label: L10n.Calibration.yieldError, error: yieldError)
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Workspace.failure)
                    .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isDeleteEnabled)
            .accessibilityLabel(
                L10n.Calibration.deleteRecordAccessibility(treeID: record.treeID)
            )
        }
    }

    private var estimatedValues: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.Calibration.estimated)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)
            Text(
                L10n.Calibration.countAndYield(
                    count: record.estimatedFruitCount,
                    yieldKg: record.estimatedYieldKg
                )
            )
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var actualValues: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Workspace.faint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Calibration.actual)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                actualValueText
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actualValueText: some View {
        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
            Text(L10n.Calibration.countAndYield(count: manual, yieldKg: actual))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else if let manual = record.manualFruitCount {
            Text(L10n.Calibration.countOnly(manual))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else if let actual = record.actualYieldKg {
            Text(L10n.Calibration.yieldOnly(actual))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMddjmm")
        return formatter.string(from: date)
    }
}

/// 误差读数：数值用等宽字形，颜色只按误差大小分级。
struct ErrorBadge: View {
    let label: String
    let error: Double

    var body: some View {
        let color = CalibrationErrorPalette.color(for: error)

        HStack(spacing: 4) {
            Text(String(format: "%+.1f%%", error))
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundColor(color)
                .lineLimit(1)

            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%+.1f%%", error))
    }
}
