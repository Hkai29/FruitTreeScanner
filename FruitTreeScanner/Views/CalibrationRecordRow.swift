import SwiftUI

struct CalibrationRecordRow: View {
    let record: CalibrationRecord
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
            Text("树 #\(record.treeID)")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            Text(formatDate(record.scanDate))
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var detailRow: some View {
        HStack(spacing: Design.Space.lg) {
            estimatedValues

            if record.manualFruitCount != nil || record.actualYieldKg != nil {
                actualValues
            }

            Spacer()

            if let countError = record.countError {
                ErrorBadge(label: "计数", error: countError)
            }
            if let yieldError = record.yieldError {
                ErrorBadge(label: "产量", error: yieldError)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.error)
                    .frame(width: 32, height: 32)
                    .background(Design.Colors.Dark.error.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除校准记录")
        }
    }

    private var estimatedValues: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("估算")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text("\(record.estimatedFruitCount) 个 / \(String(format: "%.1f", record.estimatedYieldKg)) kg")
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private var actualValues: some View {
        HStack(spacing: Design.Space.lg) {
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("实际")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                actualValueText
            }
        }
    }

    @ViewBuilder
    private var actualValueText: some View {
        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
            Text("\(manual) 个 / \(String(format: "%.1f", actual)) kg")
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        } else if let manual = record.manualFruitCount {
            Text("\(manual) 个")
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        } else if let actual = record.actualYieldKg {
            Text("\(String(format: "%.1f", actual)) kg")
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
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
    }
}
