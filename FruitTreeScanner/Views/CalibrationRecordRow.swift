import SwiftUI

struct CalibrationRecordRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: CalibrationRecord
    let isDeleteEnabled: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            header
            detailRow
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(Design.Colors.Dark.bgSurface.opacity(0.3))
        )
    }

    private var header: some View {
        HStack {
            Text(L10n.Calibration.recordTitle(treeID: record.treeID))
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            Text(formatDate(record.scanDate))
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                valuesContent
                errorAndDeleteActions
            }
        } else {
            HStack(spacing: Design.Space.lg) {
                valuesContent
                Spacer()
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
            HStack(spacing: Design.Space.lg) {
                estimatedValues

                if record.manualFruitCount != nil || record.actualYieldKg != nil {
                    actualValues
                }
            }
        }
    }

    private var errorAndDeleteActions: some View {
        HStack(spacing: Design.Space.sm) {
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
                    .foregroundColor(Design.Colors.Dark.error)
                    .frame(width: 32, height: 32)
                    .background(Design.Colors.Dark.error.opacity(0.1))
                    .clipShape(Circle())
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
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(
                L10n.Calibration.countAndYield(
                    count: record.estimatedFruitCount,
                    yieldKg: record.estimatedYieldKg
                )
            )
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var actualValues: some View {
        HStack(spacing: Design.Space.lg) {
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Calibration.actual)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                actualValueText
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actualValueText: some View {
        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
            Text(L10n.Calibration.countAndYield(count: manual, yieldKg: actual))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        } else if let manual = record.manualFruitCount {
            Text(L10n.Calibration.countOnly(manual))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        } else if let actual = record.actualYieldKg {
            Text(L10n.Calibration.yieldOnly(actual))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMddjmm")
        return formatter.string(from: date)
    }
}

struct ErrorBadge: View {
    let label: String
    let error: Double

    var body: some View {
        let color = CalibrationErrorPalette.color(for: error)

        VStack(spacing: 2) {
            Text(String(format: "%+.1f%%", error))
                .font(Design.Typography.monoSmall)
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xs)
        .background(color.opacity(0.1))
        .cornerRadius(Design.Radius.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%+.1f%%", error))
    }
}
