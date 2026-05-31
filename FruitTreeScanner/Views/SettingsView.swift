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
                Design.Colors.darkGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        SettingsPageHeader()

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
                            SettingsMenuRow(
                                icon: "square.and.arrow.up",
                                title: "导出格式",
                                value: $settings.exportFormat,
                                options: SettingsStore.exportFormatOptions
                            )

                            GlassDivider()

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
                    .padding(Design.Space.lg)
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

private struct FruitCategorySettingsRow: View {
    @Binding var selection: FruitCategory

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("当前水果类型")
                    .font(Design.Typography.darkSubheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text("影响图像检测、点云聚类与产量换算")
                    .font(Design.Typography.darkCaption)
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }

            Spacer()

            Picker("当前水果类型", selection: $selection) {
                ForEach(FruitCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.xs)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.bgElevated.opacity(0.55))
        )
    }
}

struct CameraSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(spacing: 0) {
                            GlassReadonlyRow(
                                icon: "rectangle.on.rectangle",
                                title: "实际分辨率",
                                value: settings.currentCameraResolutionDisplay
                            )

                            GlassDivider()

                            SettingsMenuRow(
                                icon: "rectangle.on.rectangle",
                                title: "目标分辨率",
                                value: $settings.cameraResolution,
                                options: SettingsStore.cameraResolutionOptions
                            )

                            GlassDivider()

                            SettingsMenuRow(
                                icon: "speedometer",
                                title: "采集帧率",
                                value: $settings.cameraFrameRate,
                                options: SettingsStore.cameraFrameRateOptions
                            )
                        }
                    }

                    Text("目标分辨率与采集帧率会优先选择最接近的 ARKit 相机格式；实际结果由设备能力和系统负载决定。")
                        .font(Design.Typography.darkCaption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(Design.Space.lg)
            }
        }
        .navigationTitle("相机设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsPageHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)

                Text("设置")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Text("采集质量、数据输出与设备参数")
                .font(Design.Typography.darkCaption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.darkSubheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(subtitle)
                    .font(Design.Typography.darkCaption)
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.bgElevated.opacity(0.55))
        )
    }
}

private struct SettingsMenuRow: View {
    let icon: String
    let title: String
    @Binding var value: String
    let options: [String]

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)

            Text(title)
                .font(Design.Typography.darkSubheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            Picker(title, selection: $value) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.xs)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.bgElevated.opacity(0.55))
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
