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
                            title: "设备",
                            icon: "cpu",
                            isExpanded: $deviceExpanded
                        ) {
                            NavigationLink {
                                CameraSettingsView()
                            } label: {
                                SettingsNavigationRow(
                                    icon: "camera.metering.center.weighted",
                                    title: "相机设置",
                                    subtitle: "分辨率与采集帧率"
                                )
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            GlassReadonlyRow(
                                icon: "rectangle.on.rectangle",
                                title: "实际分辨率",
                                value: settings.currentCameraResolutionDisplay
                            )
                        }

                        GlassExpandableSection(
                            title: "数据",
                            icon: "externaldrive.connected.to.line.below",
                            isExpanded: $dataExpanded
                        ) {
                            GlassToggleRow(
                                icon: "doc.text",
                                title: "扫描后自动导出",
                                isOn: $settings.autoExportCSV
                            )
                        }

                        GlassExpandableSection(
                            title: "扫描",
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
                                    title: "品种参数库",
                                    subtitle: "编辑当前水果的尺寸、重量与聚类参数"
                                )
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            SettingsMenuRow(
                                icon: "chart.bar",
                                title: "质量预设",
                                value: $settings.qualityPreset,
                                options: SettingsStore.qualityPresetOptions
                            )

                            GlassDivider()

                            GlassSliderRow(
                                icon: "circle.grid.3x3",
                                title: "最大点数",
                                value: maxPointCountBinding,
                                range: 100000...3000000,
                                step: 100000,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        commitMaxPointCountDraft()
                                    }
                                },
                                customDisplayValue: "\(Int(maxPointCountDraft) / 10000)万"
                            )

                            GlassDivider()

                            GlassSliderRow(
                                icon: "scope",
                                title: "精度",
                                value: scanPrecisionBinding,
                                range: 0.001...0.05,
                                step: 0.001,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        commitScanPrecisionDraft()
                                    }
                                },
                                customDisplayValue: String(format: "%.1f cm", scanPrecisionDraft * 100)
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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }

    private func refreshDraftsFromSettings() {
        maxPointCountDraft = Double(settings.maxPointCount)
        scanPrecisionDraft = settings.scanPrecision
        selectedFruitCategory = FruitCategory(rawValue: settings.fruitType) ?? .apple
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
