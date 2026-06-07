// DashboardAnalyticsComponents.swift
// 首页分析 sheet 的通用组件

import SwiftUI

struct DashboardSheetMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
}

struct DashboardSheetMetricGrid: View {
    let items: [DashboardSheetMetric]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(items) { item in
                DashboardSheetMetricCell(item: item)
            }
        }
    }
}

private struct DashboardSheetMetricCell: View {
    let item: DashboardSheetMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(item.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Design.Colors.Dark.bgElevated)
        .cornerRadius(8)
    }
}

struct YieldRecordRow: View {
    let record: ScanFileRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.treeID)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(Self.formatDate(record.scanDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f kg", record.yieldKg))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.harvest)

                Text("\(record.fruitCount) 个")
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct TrendBar: View {
    let record: ScanFileRecord
    let maxYield: Float
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: "%.1f", record.yieldKg))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 24, height: max(6, CGFloat(record.yieldKg / maxYield) * 120))

            Text(Self.shortDate(record.scanDate))
                .font(.system(size: 10))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(width: 42)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}
