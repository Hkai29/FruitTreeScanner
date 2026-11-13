// HistoricalCompareView.swift
// 树体对比：两条完整扫描并排比较。
//
// 阅读语言与档案页一致：证据行用 `InstrumentScanRow`，
// 差异用真实数字加证据等级表达，不只靠颜色。

import SwiftUI

// MARK: - HistoricalCompareView
struct HistoricalCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var historyStore: ScanHistoryStore
    private let onStartScan: (() -> Void)?
    private let presentation: HistoricalComparePresentation
    private let doneTitle: String
    @State private var selectedScan1: ScanItem?
    @State private var selectedScan2: ScanItem?
    @State private var activePicker: HistoricalComparePicker?

    @MainActor
    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main, historyStore: ScanHistoryStore? = nil) {
        self.onStartScan = onStartScan
        self.presentation = HistoricalComparePresentation(bundle: bundle)
        self.doneTitle = bundle.localizedString(forKey: "common.done", value: L10n.Common.done, table: nil)
        self.historyStore = historyStore ?? .shared
    }

    private var availableScans: [ScanItem] {
        HistoricalCompareDataSource.items(from: historyStore.scanFiles)
    }

    var body: some View {
        NavigationStack {
            comparisonContent
                .navigationTitle(presentation.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(doneTitle) { dismiss() }
                            .foregroundColor(Design.Colors.Workspace.accent)
                    }
                }
        }
        .preferredColorScheme(.light)
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
        .onAppear {
            historyStore.loadRecords()
        }
        .onChange(of: availableScans, perform: reconcileSelections)
    }

    private var comparisonContent: some View {
        ZStack {
            Design.Colors.Workspace.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
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
                    Spacer(minLength: Design.Space.lg)
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - 选择区

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
            .foregroundColor(Design.Colors.Workspace.secondary)
            .frame(minWidth: 28)
            .accessibilityHidden(true)
    }

    // MARK: - 对比区

    private func comparisonSection(scan1: ScanItem, scan2: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HistoricalYieldComparisonCard(
                scan1: scan1,
                scan2: scan2,
                proportionalChange: HistoricalCompareMetrics.proportionalYieldChange(
                    from: scan1.yieldKg,
                    to: scan2.yieldKg
                )
            )

            evidenceSection(scan1: scan1, scan2: scan2)
            metricSection(scan1: scan1, scan2: scan2)
        }
    }

    /// 两条记录按档案行的写法排出来：等级竖线 + 树号 + 时间 + 读数。
    private func evidenceSection(scan1: ScanItem, scan2: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.evidenceRowsTitle)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)

            InstrumentRowGroup {
                InstrumentScanRow(
                    record: scan1.record,
                    trailingAccessory: AnyView(slotBadge(presentation.scanA))
                )
                DividerLine(inset: 0)
                InstrumentScanRow(
                    record: scan2.record,
                    trailingAccessory: AnyView(slotBadge(presentation.scanB))
                )
            }
        }
    }

    private func slotBadge(_ slot: String) -> some View {
        Text(slot)
            .font(.caption2.weight(.semibold))
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize()
    }

    private func metricSection(scan1: ScanItem, scan2: ScanItem) -> some View {
        InstrumentRowGroup {
            StatCompareCard(
                title: presentation.archivedFruitCount,
                value1: presentation.fruitCountText(scan1.archivedFruitCount, locale: locale),
                value2: presentation.fruitCountText(scan2.archivedFruitCount, locale: locale),
                icon: "cube.fill",
                trend: HistoricalCompareMetrics.trend(from: scan1.archivedFruitCount, to: scan2.archivedFruitCount)
            )
            .padding(.vertical, 12)

            DividerLine(inset: 0)

            StatCompareCard(
                title: presentation.averageDiameter,
                value1: presentation.diameterText(scan1.meanDiameterCm, locale: locale),
                value2: presentation.diameterText(scan2.meanDiameterCm, locale: locale),
                icon: "circle.dotted",
                trend: HistoricalCompareMetrics.trend(from: scan1.meanDiameterCm, to: scan2.meanDiameterCm)
            )
            .padding(.vertical, 12)

            DividerLine(inset: 0)

            StatCompareCard(
                title: presentation.confidence,
                value1: presentation.confidenceText(scan1.confidence),
                value2: presentation.confidenceText(scan2.confidence),
                icon: "checkmark.seal.fill",
                trend: nil
            )
            .padding(.vertical, 12)

            DividerLine(inset: 0)

            StatCompareCard(
                title: presentation.scanDate,
                value1: presentation.dateText(scan1.scanDate, locale: locale),
                value2: presentation.dateText(scan2.scanDate, locale: locale),
                icon: "calendar",
                trend: nil
            )
            .padding(.vertical, 12)
        }
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
