// HistoricalCompareView.swift
// Historical Yield Comparison — Compare scans side by side

import SwiftUI

// MARK: - HistoricalCompareView
struct HistoricalCompareView: View {
    @ObservedObject var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil
    @State private var selectedScan1: ScanItem?
    @State private var selectedScan2: ScanItem?
    @State private var activePicker: HistoricalComparePicker?

    // Use real data from historyStore
    private var availableScans: [ScanItem] {
        HistoricalCompareDataSource.items(from: historyStore.scanFiles)
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Design.Space.md) {
                    DashboardToolHeader(
                        imageName: "FeatureCompare",
                        title: "树体对比",
                        subtitle: "选择两条扫描，并排比较产量、果数和日期变化。",
                        icon: "arrow.left.arrow.right",
                        accent: Design.Colors.harvest
                    )

                    if availableScans.count < 2 {
                        HistoricalCompareEmptyState(
                            scanCount: availableScans.count,
                            onStartScan: onStartScan
                        )
                    } else {
                        scanSelectionSection
                        if selectedScan1 != nil && selectedScan2 != nil {
                            comparisonSection
                        } else {
                            HistoricalComparePrompt()
                        }
                    }
                    Spacer(minLength: Design.Space.xxl)
                }
                .padding(.horizontal, Design.Space.md)
                .padding(.top, Design.Space.md)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("历史对比")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            historyStore.loadRecords()
            reconcileSelections(with: availableScans)
        }
        .onChange(of: availableScans) { scans in
            reconcileSelections(with: scans)
        }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .first:
                ScanPickerView(
                    scans: HistoricalCompareSelectionPolicy.selectableItems(
                        from: availableScans,
                        excluding: selectedScan2
                    ),
                    selectedScan: $selectedScan1
                )
            case .second:
                ScanPickerView(
                    scans: HistoricalCompareSelectionPolicy.selectableItems(
                        from: availableScans,
                        excluding: selectedScan1
                    ),
                    selectedScan: $selectedScan2
                )
            }
        }
    }

    // MARK: - Scan Selection Section
    private var scanSelectionSection: some View {
        HStack(spacing: Design.Space.md) {
            ScanSelectionCard(scan: selectedScan1, label: "扫描 A") {
                activePicker = .first
            }

            Text("VS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 28)

            ScanSelectionCard(scan: selectedScan2, label: "扫描 B") {
                activePicker = .second
            }
        }
    }

    // MARK: - Comparison Section
    private var comparisonSection: some View {
        VStack(spacing: Design.Space.lg) {
            yieldComparisonCard
            statComparisonGrid
        }
    }

    // MARK: - Yield Comparison Card
    private var yieldComparisonCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("产量变化")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack(alignment: .center, spacing: Design.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedScan1?.yieldFormatted ?? "--")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Text("扫描 #\(selectedScan1?.treeID ?? "--")")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: yieldChangeIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(yieldChangeColor)

                    Text(yieldChangePercent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(yieldChangeColor)
                }
                .frame(minWidth: 64)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(selectedScan2?.yieldFormatted ?? "--")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    Text("扫描 #\(selectedScan2?.treeID ?? "--")")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var yieldChange: Double? {
        guard let selectedScan1, let selectedScan2 else { return nil }
        return selectedScan1.yieldChangePercent(to: selectedScan2)
    }

    private var yieldChangeIcon: String {
        guard let yieldChange else { return "minus" }
        return yieldChange > 0 ? "arrow.up.right" : (yieldChange < 0 ? "arrow.down.right" : "arrow.right")
    }

    private var yieldChangeColor: Color {
        guard let yieldChange else { return Design.Colors.Dark.textSecondary }
        return yieldChange > 0
            ? Design.Colors.Dark.success
            : (yieldChange < 0 ? Design.Colors.Dark.error : Design.Colors.Dark.textSecondary)
    }

    private var yieldChangePercent: String {
        guard let yieldChange else { return "--" }
        return String(format: "%+.1f%%", yieldChange)
    }

    // MARK: - Stat Comparison Grid
    private var statComparisonGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Space.md) {
            // Persisted fruit count
            StatCompareCard(
                title: "果实数",
                value1: selectedScan1.map { "\($0.fruitCount)" } ?? "--",
                value2: selectedScan2.map { "\($0.fruitCount)" } ?? "--",
                unit: "个果实",
                icon: "cube.fill",
                trend: compareTrend(
                    selectedScan1?.fruitCount ?? 0,
                    selectedScan2?.fruitCount ?? 0
                )
            )

            // Mean Diameter
            StatCompareCard(
                title: "平均直径",
                value1: selectedScan1?.diameterFormatted ?? "--",
                value2: selectedScan2?.diameterFormatted ?? "--",
                unit: "cm",
                icon: "circle.dotted",
                trend: compareTrend(selectedScan1?.meanDiameterCm, selectedScan2?.meanDiameterCm)
            )

            // Confidence
            StatCompareCard(
                title: "置信度",
                value1: selectedScan1?.confidenceFormatted ?? "--",
                value2: selectedScan2?.confidenceFormatted ?? "--",
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

    private func compareTrend<T: Comparable>(_ v1: T?, _ v2: T?) -> TrendDirection {
        guard let v1, let v2 else { return .neutral }
        return compareTrend(v1, v2)
    }

    private func reconcileSelections(with scans: [ScanItem]) {
        let selection = HistoricalCompareSelectionPolicy.reconciled(
            first: selectedScan1,
            second: selectedScan2,
            availableItems: scans
        )
        if selectedScan1 != selection.first {
            selectedScan1 = selection.first
        }
        if selectedScan2 != selection.second {
            selectedScan2 = selection.second
        }
    }
}

private enum HistoricalComparePicker: Identifiable {
    case first
    case second

    var id: String {
        switch self {
        case .first: return "first"
        case .second: return "second"
        }
    }
}
