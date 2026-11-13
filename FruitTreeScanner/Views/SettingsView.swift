// SettingsView.swift
// 设置页：纸面工作区上的一组分栏。
//
// 读数一律来自 SettingsStore / FruitParametersStore；滑杆使用“草稿—提交”模型：
// 拖动期间只改草稿，结束编辑或离开页面才写入存储。
//
// 容器说明：这里用 ScrollView 而不是原生 List。原生 List 由 UICollectionView 承载，
// 现有 UI 测试驱动页面时需要能滚动并可定位的 UIScrollView；分组外观由
// InstrumentSectionLabel + InstrumentRowGroup 统一，与工作台其他页面一致。

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings: SettingsStore
    private let parametersStore: FruitParametersStore
    @State private var maxPointCountDraft: Double = 1_000_000
    @State private var scanPrecisionDraft: Double = 0.01

    @MainActor
    init(settings: SettingsStore = .shared, parametersStore: FruitParametersStore? = nil) {
        self.settings = settings
        self.parametersStore = parametersStore ?? .shared
    }

    private var maxPointCountBinding: Binding<Double> {
        Binding(
            get: { maxPointCountDraft },
            set: { maxPointCountDraft = $0 }
        )
    }

    private var scanPrecisionBinding: Binding<Double> {
        Binding(
            get: { scanPrecisionDraft },
            set: { scanPrecisionDraft = $0 }
        )
    }

    private var fruitCategoryBinding: Binding<FruitCategory> {
        Binding(
            get: { FruitCategory.scanCategory(for: settings.fruitType) },
            set: { settings.fruitType = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    deviceGroup
                    dataGroup
                    scanGroup
                    helpGroup
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .workspacePage()
            .onAppear {
                refreshDraftsFromSettings()
            }
            .onDisappear {
                commitDrafts()
            }
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) { dismiss() }
                        .foregroundColor(Design.Colors.Workspace.accent)
                }
            }
        }
    }

    // MARK: - 设备

    private var deviceGroup: some View {
        SettingsGroup(title: L10n.Settings.deviceSection) {
            NavigationLink {
                CameraSettingsView(settings: settings)
            } label: {
                SettingsNavigationRow(
                    icon: "camera.metering.center.weighted",
                    title: L10n.Settings.cameraSettings,
                    subtitle: L10n.Settings.cameraSettingsSubtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Settings.cameraSettings)
            .accessibilityHint(L10n.Settings.cameraSettingsSubtitle)

            DividerLine()

            SettingsValueRow(
                systemImage: "rectangle.on.rectangle",
                title: L10n.Settings.actualResolution,
                value: settings.currentCameraResolutionDisplay
            )
        }
    }

    // MARK: - 数据

    private var dataGroup: some View {
        SettingsGroup(title: L10n.Settings.dataSection) {
            SettingsToggleRow(
                systemImage: "doc.text",
                title: L10n.Settings.autoExportCSV,
                isOn: $settings.autoExportCSV,
                accessibilityHint: L10n.Settings.autoExportCSVHint
            )

            DividerLine()

            SettingsInlineHint(text: L10n.Settings.autoExportCSVHint)
        }
    }

    // MARK: - 扫描

    private var scanGroup: some View {
        SettingsGroup(title: L10n.Settings.scanSection) {
            FruitCategorySettingsRow(selection: fruitCategoryBinding)

            DividerLine()

            NavigationLink {
                VarietyDatabaseView(settings: settings, store: parametersStore)
            } label: {
                SettingsNavigationRow(
                    icon: "leaf.circle",
                    title: L10n.Settings.varietyDatabase,
                    subtitle: L10n.Settings.varietyDatabaseSubtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Settings.varietyDatabase)
            .accessibilityHint(L10n.Settings.varietyDatabaseSubtitle)

            DividerLine()

            SettingsMenuRow(
                icon: "chart.bar",
                title: L10n.Settings.scanQuality,
                value: $settings.qualityPreset,
                options: SettingsStore.qualityPresetOptions,
                optionLabel: { L10n.Settings.qualityPresetName(for: $0) },
                accessibilityHint: L10n.Settings.qualityHint
            )

            SettingsInlineHint(text: L10n.Settings.qualityHint)

            DividerLine()

            SettingsSliderRow(
                systemImage: "circle.grid.3x3",
                title: L10n.Settings.maxPoints,
                value: maxPointCountBinding,
                range: 100000...3000000,
                step: 100000,
                displayValue: L10n.Settings.maxPointCountValue(Int(maxPointCountDraft)),
                onEditingChanged: { isEditing in
                    if !isEditing {
                        commitMaxPointCountDraft()
                    }
                },
                accessibilityHint: L10n.Settings.maxPointsHint
            )

            SettingsInlineHint(text: L10n.Settings.maxPointsHint)

            DividerLine()

            SettingsSliderRow(
                systemImage: "scope",
                title: L10n.Settings.precision,
                value: scanPrecisionBinding,
                range: 0.001...0.05,
                step: 0.001,
                displayValue: L10n.Settings.precisionValue(scanPrecisionDraft * 100),
                onEditingChanged: { isEditing in
                    if !isEditing {
                        commitScanPrecisionDraft()
                    }
                },
                accessibilityHint: L10n.Settings.precisionHint
            )

            SettingsInlineHint(text: L10n.Settings.precisionHint)
        }
    }

    // MARK: - 帮助

    private var helpGroup: some View {
        SettingsGroup(title: HelpCopy.sectionTitle) {
            NavigationLink {
                HelpView()
            } label: {
                SettingsNavigationRow(
                    icon: "questionmark.circle",
                    title: HelpCopy.title,
                    subtitle: HelpCopy.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(HelpCopy.title)
            .accessibilityHint(HelpCopy.subtitle)
        }
    }

    // MARK: - 草稿

    private func refreshDraftsFromSettings() {
        maxPointCountDraft = Double(settings.maxPointCount)
        scanPrecisionDraft = settings.scanPrecision
    }

    private func commitDrafts() {
        commitMaxPointCountDraft()
        commitScanPrecisionDraft()
    }

    private func commitMaxPointCountDraft() {
        let rounded = Int((maxPointCountDraft / 100_000).rounded() * 100_000)
        guard settings.maxPointCount != rounded else { return }
        settings.maxPointCount = rounded
        maxPointCountDraft = Double(settings.maxPointCount)
    }

    private func commitScanPrecisionDraft() {
        let rounded = (scanPrecisionDraft / 0.001).rounded() * 0.001
        guard abs(settings.scanPrecision - rounded) > 0.000_1 else { return }
        settings.scanPrecision = rounded
        scanPrecisionDraft = settings.scanPrecision
    }
}
