// HistoricalCompareView.swift
// Historical Yield Comparison — Compare scans side by side

import SwiftUI

// MARK: - HistoricalCompareView
struct HistoricalCompareView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var historyStore = ScanHistoryStore.shared
    private let onStartScan: (() -> Void)?
    private let presentation: HistoricalComparePresentation
    @State private var selectedScan1: ScanItem?
    @State private var selectedScan2: ScanItem?
    @State private var activePicker: HistoricalComparePicker?

    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main) {
        self.onStartScan = onStartScan
        self.presentation = HistoricalComparePresentation(bundle: bundle)
    }

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
                        title: presentation.title,
                        subtitle: presentation.subtitle,
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
                        if let selectedScan1, let selectedScan2 {
                            comparisonSection(scan1: selectedScan1, scan2: selectedScan2)
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
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.historicalComparePresentation, presentation)
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .first:
                ScanPickerView(
                    scans: HistoricalCompareSelectionPolicy.selectableItems(
                        from: availableScans,
                        excluding: selectedScan2
                    ),
                    selectedScan: $selectedScan1,
                    slot: presentation.scanA,
                    presentation: presentation
                )
            case .second:
                ScanPickerView(
                    scans: HistoricalCompareSelectionPolicy.selectableItems(
                        from: availableScans,
                        excluding: selectedScan1
                    ),
                    selectedScan: $selectedScan2,
                    slot: presentation.scanB,
                    presentation: presentation
                )
            }
        }
        .onChange(of: availableScans, perform: reconcileSelections)
    }

    // MARK: - Scan Selection Section
    @ViewBuilder
    private var scanSelectionSection: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Design.Space.sm) {
                selectionCard(scan: selectedScan1, label: presentation.scanA, picker: .first)
                versusLabel
                selectionCard(scan: selectedScan2, label: presentation.scanB, picker: .second)
            }
        } else {
            HStack(spacing: Design.Space.md) {
                selectionCard(scan: selectedScan1, label: presentation.scanA, picker: .first)
                versusLabel
                selectionCard(scan: selectedScan2, label: presentation.scanB, picker: .second)
            }
        }
    }

    private func selectionCard(
        scan: ScanItem?,
        label: String,
        picker: HistoricalComparePicker
    ) -> some View {
        ScanSelectionCard(scan: scan, label: label) {
            activePicker = picker
        }
    }

    private var versusLabel: some View {
        Text(presentation.versus)
            .font(.caption.weight(.semibold))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .frame(minWidth: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Comparison Section
    private func comparisonSection(scan1: ScanItem, scan2: ScanItem) -> some View {
        VStack(spacing: Design.Space.lg) {
            HistoricalYieldComparisonCard(
                scan1: scan1,
                scan2: scan2,
                proportionalChange: HistoricalCompareMetrics.proportionalYieldChange(
                    from: scan1.yieldKg,
                    to: scan2.yieldKg
                )
            )
            statComparisonGrid(scan1: scan1, scan2: scan2)
        }
    }

    // MARK: - Stat Comparison Grid
    private func statComparisonGrid(scan1: ScanItem, scan2: ScanItem) -> some View {
        LazyVGrid(columns: statColumns, spacing: Design.Space.md) {
            StatCompareCard(
                title: presentation.lidarDetections,
                value1: presentation.fruitCountText(scan1.nLidar, locale: locale),
                value2: presentation.fruitCountText(scan2.nLidar, locale: locale),
                icon: "cube.fill",
                trend: HistoricalCompareMetrics.trend(from: scan1.nLidar, to: scan2.nLidar)
            )

            StatCompareCard(
                title: presentation.averageDiameter,
                value1: presentation.diameterText(scan1.meanDiameterCm, locale: locale),
                value2: presentation.diameterText(scan2.meanDiameterCm, locale: locale),
                icon: "circle.dotted",
                trend: HistoricalCompareMetrics.trend(from: scan1.meanDiameterCm, to: scan2.meanDiameterCm)
            )

            StatCompareCard(
                title: presentation.confidence,
                value1: presentation.confidenceText(scan1.confidence),
                value2: presentation.confidenceText(scan2.confidence),
                icon: "checkmark.seal.fill",
                trend: nil
            )

            StatCompareCard(
                title: presentation.scanDate,
                value1: presentation.dateText(scan1.scanDate, locale: locale),
                value2: presentation.dateText(scan2.scanDate, locale: locale),
                icon: "calendar",
                trend: nil
            )
        }
    }

    private var statColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func reconcileSelections(with scans: [ScanItem]) {
        let selection = HistoricalCompareSelectionPolicy.reconciled(
            first: selectedScan1,
            second: selectedScan2,
            availableItems: scans
        )
        if selection.first != selectedScan1 { selectedScan1 = selection.first }
        if selection.second != selectedScan2 { selectedScan2 = selection.second }
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
