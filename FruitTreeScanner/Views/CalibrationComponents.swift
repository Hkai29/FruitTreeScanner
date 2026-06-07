import SwiftUI

// MARK: - 校准统计区

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
                HStack(spacing: Design.Space.xl) {
                    let countErrors = validRecords.compactMap { $0.countError }
                    let avgCountError = countErrors.isEmpty ? 0 : countErrors.reduce(0, +) / Double(countErrors.count)

                    StatBox(
                        title: "计数误差",
                        value: String(format: "%.1f%%", avgCountError),
                        color: CalibrationErrorPalette.color(for: avgCountError)
                    )

                    let yieldErrors = validRecords.compactMap { $0.yieldError }
                    let avgYieldError = yieldErrors.isEmpty ? 0 : yieldErrors.reduce(0, +) / Double(yieldErrors.count)

                    StatBox(
                        title: "产量误差",
                        value: String(format: "%.1f%%", avgYieldError),
                        color: CalibrationErrorPalette.color(for: avgYieldError)
                    )

                    StatBox(
                        title: "校准次数",
                        value: "\(validRecords.count)",
                        color: Design.Colors.Dark.glow
                    )
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }
}

// MARK: - 校准记录区

struct CalibrationRecordsSection: View {
    let records: [CalibrationRecord]
    let onAdd: () -> Void
    let onDelete: (CalibrationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text("校准记录")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()

            if records.isEmpty {
                CalibrationEmptyRecordState(onAdd: onAdd)
            } else {
                ForEach(records) { record in
                    CalibrationRecordRow(
                        record: record,
                        onDelete: { onDelete(record) }
                    )
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }
}

private struct CalibrationEmptyRecordState: View {
    let onAdd: () -> Void

    var body: some View {
        DashboardSheetEmptyState(
            icon: "plus",
            imageName: "FeatureCalibration",
            title: "暂无校准记录",
            message: "添加人工计数或实际重量后，这里会显示误差对比。",
            accent: Design.Colors.Dark.info,
            primaryAction: DashboardSheetAction(
                title: "添加记录",
                icon: "plus",
                action: onAdd
            ),
            outerPadding: false
        )
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

// MARK: - 统计框

struct StatBox: View {
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

// MARK: - 校准记录行

struct CalibrationRecordRow: View {
    let record: CalibrationRecord
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack {
                Text("树 #\(record.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()

                Text(formatDate(record.scanDate))
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack(spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("估算")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text("\(record.estimatedFruitCount) 个 / \(String(format: "%.1f", record.estimatedYieldKg)) kg")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                if record.manualFruitCount != nil || record.actualYieldKg != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实际")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
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
                }

                Spacer()

                // 误差显示
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
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(Design.Colors.Dark.bgSurface.opacity(0.3))
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 误差徽章

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
