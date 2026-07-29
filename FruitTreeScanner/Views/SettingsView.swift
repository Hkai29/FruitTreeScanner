import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = SettingsStore.shared
    @State private var deviceExpanded = true
    @State private var dataExpanded = true
    @State private var scanExpanded = true
    @State private var maxPointCountDraft: Double = 1_000_000
    @State private var scanPrecisionDraft: Double = 0.01
    @State private var selectedFruitCategory: FruitCategory = .apple

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

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        GlassExpandableSection(
                            title: L10n.Settings.deviceSection,
                            icon: "cpu",
                            isExpanded: $deviceExpanded
                        ) {
                            NavigationLink {
                                CameraSettingsView()
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

                            GlassDivider()

                            GlassReadonlyRow(
                                icon: "rectangle.on.rectangle",
                                title: L10n.Settings.actualResolution,
                                value: settings.currentCameraResolutionDisplay
                            )
                        }

                        GlassExpandableSection(
                            title: L10n.Settings.dataSection,
                            icon: "externaldrive.connected.to.line.below",
                            isExpanded: $dataExpanded
                        ) {
                            GlassToggleRow(
                                icon: "doc.text",
                                title: L10n.Settings.autoExportCSV,
                                isOn: $settings.autoExportCSV,
                                accessibilityHint: L10n.Settings.autoExportCSVHint
                            )
                        }

                        GlassExpandableSection(
                            title: L10n.Settings.scanSection,
                            icon: "viewfinder",
                            isExpanded: $scanExpanded
                        ) {
                            FruitCategorySettingsRow(selection: $selectedFruitCategory)
                                .onChange(of: selectedFruitCategory) { category in
                                    settings.fruitType = category.rawValue
                                }

                            GlassDivider()

                            NavigationLink {
                                VarietyDatabaseView()
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

                            GlassDivider()

                            SettingsMenuRow(
                                icon: "chart.bar",
                                title: L10n.Settings.scanQuality,
                                value: $settings.qualityPreset,
                                options: SettingsStore.qualityPresetOptions,
                                optionLabel: { L10n.Settings.qualityPresetName(for: $0) },
                                accessibilityHint: L10n.Settings.qualityHint
                            )
                            SettingsInlineHint(
                                text: L10n.Settings.qualityHint
                            )

                            GlassDivider()

                            GlassSliderRow(
                                icon: "circle.grid.3x3",
                                title: L10n.Settings.maxPoints,
                                value: maxPointCountBinding,
                                range: 100000...3000000,
                                step: 100000,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        commitMaxPointCountDraft()
                                    }
                                },
                                customDisplayValue: L10n.Settings.maxPointCountValue(Int(maxPointCountDraft)),
                                accessibilityHint: L10n.Settings.maxPointsHint
                            )
                            SettingsInlineHint(
                                text: L10n.Settings.maxPointsHint
                            )

                            GlassDivider()

                            GlassSliderRow(
                                icon: "scope",
                                title: L10n.Settings.precision,
                                value: scanPrecisionBinding,
                                range: 0.001...0.05,
                                step: 0.001,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        commitScanPrecisionDraft()
                                    }
                                },
                                customDisplayValue: L10n.Settings.precisionValue(scanPrecisionDraft * 100),
                                accessibilityHint: L10n.Settings.precisionHint
                            )
                            SettingsInlineHint(
                                text: L10n.Settings.precisionHint
                            )
                        }
                    }
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.lg)
                }
            }
            .onAppear {
                refreshDraftsFromSettings()
            }
            .onDisappear {
                commitDrafts()
            }
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }

    private func refreshDraftsFromSettings() {
        maxPointCountDraft = Double(settings.maxPointCount)
        scanPrecisionDraft = settings.scanPrecision
        selectedFruitCategory = FruitCategory.scanCategory(for: settings.fruitType)
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
