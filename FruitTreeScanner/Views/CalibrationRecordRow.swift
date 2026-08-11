import SwiftUI

struct CalibrationRecordRow: View {
    let record: CalibrationRecord
    let onDelete: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    treeTitle
                    scanDate
                }
            } else {
                HStack {
                    treeTitle
                    Spacer()
                    scanDate
                }
            }
        }
    }

    private var treeTitle: some View {
        Text(L10n.CalibrationWorkspace.treeTitle(record.treeID))
            .font(Design.Typography.subheadlineMedium)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var scanDate: some View {
        Text(record.scanDate, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
            .font(Design.Typography.caption)
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    @ViewBuilder
    private var detailRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                estimatedValues

                if hasActualValues {
                    actualValues(arrowSystemName: "arrow.down")
                }

                HStack(alignment: .center, spacing: Design.Space.sm) {
                    errorBadges
                    Spacer()
                    deleteButton
                }
            }
        } else {
            HStack(spacing: Design.Space.lg) {
                estimatedValues

                if hasActualValues {
                    actualValues(arrowSystemName: "arrow.right")
                }

                Spacer()
                errorBadges
                deleteButton
            }
        }
    }

    private var hasActualValues: Bool {
        record.manualFruitCount != nil || record.actualYieldKg != nil
    }

    @ViewBuilder
    private var errorBadges: some View {
        if let countError = record.countError {
            ErrorBadge(label: L10n.CalibrationWorkspace.countError, error: countError)
        }
        if let yieldError = record.yieldError {
            ErrorBadge(label: L10n.CalibrationWorkspace.yieldError, error: yieldError)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.error)
                .frame(width: 32, height: 32)
                .background(Design.Colors.Dark.error.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.CalibrationWorkspace.deleteRecordAccessibility)
    }

    private var estimatedValues: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.CalibrationWorkspace.estimated)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(L10n.CalibrationWorkspace.countAndYield(
                count: record.estimatedFruitCount,
                yieldKilograms: record.estimatedYieldKg
            ))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actualValues(arrowSystemName: String) -> some View {
        HStack(spacing: Design.Space.lg) {
            Image(systemName: arrowSystemName)
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.CalibrationWorkspace.actual)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                actualValueText
            }
        }
    }

    @ViewBuilder
    private var actualValueText: some View {
        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
            Text(L10n.CalibrationWorkspace.countAndYield(
                count: manual,
                yieldKilograms: actual
            ))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let manual = record.manualFruitCount {
            Text(L10n.CalibrationWorkspace.fruitCount(manual))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        } else if let actual = record.actualYieldKg {
            Text(L10n.CalibrationWorkspace.yieldKilograms(actual))
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
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
                .font(.caption2)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xs)
        .background(color.opacity(0.1))
        .cornerRadius(Design.Radius.small)
    }
}
