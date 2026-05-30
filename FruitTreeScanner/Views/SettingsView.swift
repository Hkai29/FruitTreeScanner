// SettingsView.swift
// 设置页面 - 玻璃拟态暗色主题

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var deviceExpanded = true
    @State private var dataExpanded = true
    @State private var scanExpanded = true
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            // 暗色渐变背景
            Design.Colors.darkGradient
                .ignoresSafeArea()

            // 手指光效
            FingerGlowOverlay()

            ScrollView {
                VStack(spacing: 32) {
                    // 标题
                    GlassSectionHeader("设置", icon: "gearshape.fill")

                    // 设备
                    GlassExpandableSection(
                        title: "设备",
                        icon: "cpu",
                        isExpanded: $deviceExpanded
                    ) {
                        GlassRow(icon: "camera.metering.center.weighted", title: "相机设置") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                        }

                        GlassDivider()

                        GlassReadonlyRow(
                            icon: "rectangle.on.rectangle",
                            title: "实际分辨率",
                            value: SettingsStore.shared.currentCameraResolutionDisplay
                        )

                        GlassDivider()

                        GlassPickerRow(
                            icon: "speedometer",
                            title: "检测频率",
                            value: SettingsStore.shared.cameraFrameRate
                        )
                    }

                    // 数据
                    GlassExpandableSection(
                        title: "数据",
                        icon: "externaldrive.connected.to.line.below",
                        isExpanded: $dataExpanded
                    ) {
                        GlassPickerRow(
                            icon: "square.and.arrow.up",
                            title: "导出格式",
                            value: SettingsStore.shared.exportFormat
                        )

                        GlassDivider()

                        GlassToggleRow(
                            icon: "doc.text",
                            title: "扫描后自动导出",
                            isOn: SettingsStore.shared.autoExportCSVBinding
                        )
                    }

                    // 扫描
                    GlassExpandableSection(
                        title: "扫描",
                        icon: "viewfinder",
                        isExpanded: $scanExpanded
                    ) {
                        GlassPickerRow(
                            icon: "chart.bar",
                            title: "质量预设",
                            value: SettingsStore.shared.qualityPreset
                        )

                        GlassDivider()

                        GlassSliderRow(
                            icon: "circle.grid.3x3",
                            title: "最大点数",
                            value: Binding(
                                get: { Double(SettingsStore.shared.maxPointCount) },
                                set: { SettingsStore.shared.maxPointCount = Int($0) }
                            ),
                            range: 100000...3000000,
                            step: 100000,
                            displayValue: "\(SettingsStore.shared.maxPointCount)"
                        )

                        GlassDivider()

                        GlassSliderRow(
                            icon: "scope",
                            title: "精度",
                            value: SettingsStore.shared.scanPrecisionBinding,
                            range: 0.001...0.05,
                            step: 0.001,
                            displayValue: String(format: "%.3f", SettingsStore.shared.scanPrecision)
                        )
                    }
                }
                .padding(Design.Space.lg)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
                    .foregroundColor(Design.Colors.harvest)
            }
        }
    }
}

// MARK: - Camera Settings View
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
                                value: SettingsStore.shared.currentCameraResolutionDisplay
                            )

                            GlassDivider()

                            GlassPickerRow(
                                icon: "speedometer",
                                title: "检测频率",
                                value: SettingsStore.shared.cameraFrameRate
                            )
                        }
                    }

                    Text("检测频率：控制图像检测算法的执行频率。实际帧率由设备硬件决定，不受此设置影响。")
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

#Preview {
    NavigationStack {
        SettingsView()
    }
}
