// HistoricalCompareView.swift
// Historical Yield Comparison — Compare scans side by side

import SwiftUI

// MARK: - Scan Item (for selection)
struct ScanItem: Identifiable, Equatable {
    let id: String
    let treeID: String
    let scanDate: Date
    let yieldKg: Double
    let nLidar: Int
    let meanDiameterCm: Double
    let confidence: String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var dateFormatted: String {
        Self.dateFormatter.string(from: scanDate)
    }

    var yieldFormatted: String {
        String(format: "%.1f kg", yieldKg)
    }

    var confidenceColor: Color {
        switch confidence {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.error
        }
    }
}

// MARK: - HistoricalCompareView
struct HistoricalCompareView: View {
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @State private var selectedScan1: ScanItem?
    @State private var selectedScan2: ScanItem?
    @State private var showScanPicker1 = false
    @State private var showScanPicker2 = false

    // Use real data from historyStore
    private var availableScans: [ScanItem] {
        historyStore.scanFiles.map { record in
            ScanItem(
                id: record.id,
                treeID: record.treeID,
                scanDate: record.scanDate,
                yieldKg: Double(record.yieldKg),
                nLidar: record.fruitCount,
                meanDiameterCm: 0,
                confidence: "medium"
            )
        }
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Design.Space.lg) {
                    headerSection
                        .padding(.top, Design.Space.md)
                    scanSelectionSection
                    if selectedScan1 != nil && selectedScan2 != nil {
                        comparisonSection
                    }
                    Spacer(minLength: Design.Space.xxl)
                }
                .padding(.horizontal, Design.Space.lg)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("历史对比")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showScanPicker1) {
            ScanPickerView(scans: availableScans, selectedScan: $selectedScan1)
        }
        .sheet(isPresented: $showScanPicker2) {
            ScanPickerView(scans: availableScans, selectedScan: $selectedScan2)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Design.Colors.Dark.glow)

            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("选择两条扫描进行对比")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text("分析不同时间段的产量变化")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface.glassCardStyle())
    }

    // MARK: - Scan Selection Section
    private var scanSelectionSection: some View {
        HStack(spacing: Design.Space.md) {
            ScanSelectionCard(scan: selectedScan1, label: "扫描 A") {
                showScanPicker1 = true
            }

            VStack {
                Text("VS")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .frame(width: 40)

            ScanSelectionCard(scan: selectedScan2, label: "扫描 B") {
                showScanPicker2 = true
            }
        }
    }

    // MARK: - Comparison Section
    private var comparisonSection: some View {
        VStack(spacing: Design.Space.lg) {
            // Yield Comparison Hero
            yieldComparisonCard

            // Stat Grid
            statComparisonGrid
        }
    }

    // MARK: - Yield Comparison Card
    private var yieldComparisonCard: some View {
        VStack(spacing: Design.Space.md) {
            Text("产量对比")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: Design.Space.md) {
                // Scan 1 Yield
                VStack(spacing: Design.Space.xs) {
                    Text(selectedScan1?.yieldFormatted ?? "--")
                        .font(Design.Typography.title1)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Text("扫描 #\(selectedScan1?.treeID ?? "--")")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

                // Arrow
                VStack(spacing: 2) {
                    Image(systemName: yieldChangeIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(yieldChangeColor)

                    Text(yieldChangePercent)
                        .font(Design.Typography.subheadlineMedium)
                        .foregroundColor(yieldChangeColor)
                }
                .padding(.horizontal, Design.Space.md)

                // Scan 2 Yield
                VStack(spacing: Design.Space.xs) {
                    Text(selectedScan2?.yieldFormatted ?? "--")
                        .font(Design.Typography.title1)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Text("扫描 #\(selectedScan2?.treeID ?? "--")")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.lg)
        .padding(.horizontal, Design.Space.md)
        .glassCardStyle(cornerRadius: Design.Radius.xl)
    }

    private var yieldChange: Double {
        guard let s1 = selectedScan1, let s2 = selectedScan2, s1.yieldKg > 0 else { return 0 }
        return ((s2.yieldKg - s1.yieldKg) / s1.yieldKg) * 100
    }

    private var yieldChangeIcon: String {
        yieldChange > 0 ? "arrow.up.right" : (yieldChange < 0 ? "arrow.down.right" : "arrow.right")
    }

    private var yieldChangeColor: Color {
        yieldChange > 0 ? Design.Colors.Dark.success : (yieldChange < 0 ? Design.Colors.Dark.error : Design.Colors.Dark.textSecondary)
    }

    private var yieldChangePercent: String {
        String(format: "%+.1f%%", yieldChange)
    }

    // MARK: - Stat Comparison Grid
    private var statComparisonGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Space.md) {
            // LiDAR Count
            StatCompareCard(
                title: "LiDAR 检测",
                value1: selectedScan1.map { "\($0.nLidar)" } ?? "--",
                value2: selectedScan2.map { "\($0.nLidar)" } ?? "--",
                unit: "个果实",
                icon: "cube.fill",
                trend: compareTrend(selectedScan1?.nLidar ?? 0, selectedScan2?.nLidar ?? 0)
            )

            // Mean Diameter
            StatCompareCard(
                title: "平均直径",
                value1: selectedScan1.map { String(format: "%.1f", $0.meanDiameterCm) } ?? "--",
                value2: selectedScan2.map { String(format: "%.1f", $0.meanDiameterCm) } ?? "--",
                unit: "cm",
                icon: "circle.dotted",
                trend: compareTrend(selectedScan1?.meanDiameterCm ?? 0, selectedScan2?.meanDiameterCm ?? 0)
            )

            // Confidence
            StatCompareCard(
                title: "置信度",
                value1: selectedScan1?.confidence ?? "--",
                value2: selectedScan2?.confidence ?? "--",
                unit: "",
                icon: "checkmark.seal.fill",
                trend: .neutral
            )

            // Scan Date
            StatCompareCard(
                title: "扫描日期",
                value1: selectedScan1?.dateFormatted ?? "--",
                value2: selectedScan2?.dateFormatted ?? "--",
                unit: "",
                icon: "calendar",
                trend: .neutral
            )
        }
    }

    private func compareTrend<T: Comparable>(_ v1: T, _ v2: T) -> TrendDirection {
        if v1 < v2 { return .up }
        if v1 > v2 { return .down }
        return .neutral
    }
}

// MARK: - Trend Direction
enum TrendDirection {
    case up, down, neutral

    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up: return Design.Colors.Dark.success
        case .down: return Design.Colors.Dark.error
        case .neutral: return Design.Colors.Dark.textSecondary
        }
    }
}

// MARK: - Scan Selection Card
struct ScanSelectionCard: View {
    let scan: ScanItem?
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Design.Space.md) {
                if let scan = scan {
                    // Filled state
                    VStack(spacing: Design.Space.sm) {
                        Text("树 #\(scan.treeID)")
                            .font(Design.Typography.headline)
                            .foregroundColor(Design.Colors.Dark.textPrimary)

                        Text(scan.dateFormatted)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)

                        Text(scan.yieldFormatted)
                            .font(Design.Typography.title2)
                            .foregroundColor(Design.Colors.Dark.glow)
                    }
                } else {
                    // Empty state
                    VStack(spacing: Design.Space.sm) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Design.Colors.Dark.textSecondary)

                        Text("选择扫描")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Space.lg)
            .background(Design.Colors.Dark.bgSurface)
            .cornerRadius(Design.Radius.large)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.large)
                    .stroke(scan != nil ? Design.Colors.Dark.glow.opacity(0.3) : Design.Colors.sand, lineWidth: 1.5)
            )
            .shadow(color: Design.Shadow.subtle.color, radius: Design.Shadow.subtle.radius, y: Design.Shadow.subtle.y)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Compare Card
struct StatCompareCard: View {
    let title: String
    let value1: String
    let value2: String
    let unit: String
    let icon: String
    let trend: TrendDirection

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text(title)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            // Values
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value1)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    if !unit.isEmpty && value1 != "--" {
                        Text(unit)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: trend.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(trend.color)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(value2)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    if !unit.isEmpty && value2 != "--" {
                        Text(unit)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.medium)
        .shadow(color: Design.Shadow.subtle.color, radius: Design.Shadow.subtle.radius, y: Design.Shadow.subtle.y)
    }
}

// MARK: - Scan Picker View
struct ScanPickerView: View {
    let scans: [ScanItem]
    @Binding var selectedScan: ScanItem?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: Design.Space.md) {
                        ForEach(scans) { scan in
                            Button {
                                selectedScan = scan
                                dismiss()
                            } label: {
                                ScanPickerRow(scan: scan, isSelected: selectedScan?.id == scan.id)
                            }
                        }
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("选择扫描")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Scan Picker Row
struct ScanPickerRow: View {
    let scan: ScanItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Design.Space.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? Design.Colors.Dark.glow.opacity(0.12) : Design.Colors.Dark.bgSurface)
                    .frame(width: 44, height: 44)

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? Design.Colors.Dark.glow : Design.Colors.Dark.textSecondary)
            }

            // Info
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("树 #\(scan.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                HStack(spacing: Design.Space.md) {
                    Text(scan.dateFormatted)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    Text(scan.yieldFormatted)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.glow)
                }
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Design.Colors.Dark.glow)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .stroke(isSelected ? Design.Colors.Dark.glow : Color.clear, lineWidth: 2)
        )
        .shadow(color: Design.Shadow.subtle.color, radius: Design.Shadow.subtle.radius, y: Design.Shadow.subtle.y)
    }
}

#Preview {
    NavigationView {
        HistoricalCompareView()
    }
}
