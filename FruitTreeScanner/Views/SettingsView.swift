// SettingsView.swift
// 设置页面 - 设备 / 数据 / 扫描 三个板块

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedSection: SettingsSection = .device

    enum SettingsSection: String, CaseIterable {
        case device = "设备"
        case data = "数据"
        case scan = "扫描"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, Design.Space.lg)
                        .padding(.top, Design.Space.md)

                    ScrollView {
                        VStack(spacing: Design.Space.lg) {
                            contentForSection
                        }
                        .padding(Design.Space.lg)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Design.Colors.forest)
                }
            }
        }
    }

    // MARK: - Section Picker
    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(section.rawValue)
                            .font(Design.Typography.subheadlineMedium)
                            .foregroundColor(selectedSection == section
                                ? Design.Colors.forest
                                : Design.Colors.slate)

                        Rectangle()
                            .fill(selectedSection == section
                                ? Design.Colors.forest
                                : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.medium)
    }

    // MARK: - Section Content
    @ViewBuilder
    private var contentForSection: some View {
        switch selectedSection {
        case .device:
            deviceSection
        case .data:
            dataSection
        case .scan:
            scanSection
        }
    }

    // MARK: - 设备
    private var deviceSection: some View {
        VStack(spacing: Design.Space.lg) {
            SettingsSection(title: "相机") {
                SettingsToggle(
                    title: "启用 LiDAR",
                    subtitle: "使用激光雷达增强深度感知",
                    icon: "sensor.tag.radiowaves.forward",
                    isOn: $SettingsStore.shared.enableLidar
                )

                SettingsRow(label: "RGB 采样半径", value: String(format: "%.1f", SettingsStore.shared.rgbRadius)) {
                    Slider(value: $SettingsStore.shared.rgbRadius, in: 1...10, step: 0.5)
                }

                SettingsRow(label: "置信度阈值", value: "\(SettingsStore.shared.confidenceThreshold)") {
                    Slider(value: Binding(
                        get: { Double(SettingsStore.shared.confidenceThreshold) },
                        set: { SettingsStore.shared.confidenceThreshold = Int($0) }
                    ), in: 0...2, step: 1)
                }
            }

            SettingsSection(title: "GPS") {
                SettingsToggle(
                    title: "高精度 GPS",
                    subtitle: "使用差分 GPS 提升定位精度",
                    icon: "location.fill",
                    isOn: .constant(true)
                )

                SettingsRow(label: "GPS 更新频率", value: String(format: "%.1f Hz", SettingsStore.shared.gpsUpdateRate)) {
                    Slider(value: $SettingsStore.shared.gpsUpdateRate, in: 0.5...5, step: 0.5)
                }
            }

            SettingsSection(title: "设备校准") {
                NavigationLink {
                    CalibrationView()
                } label: {
                    SettingsNavRow(
                        title: "陀螺仪校准",
                        subtitle: "指南针与加速计校准",
                        icon: "gyroscope"
                    )
                }

                SettingsNavRow(
                    title: "深度相机校准",
                    subtitle: "红外点阵投影仪校准",
                    icon: "camera.metering.center.weighted"
                )
            }
        }
    }

    // MARK: - 数据
    private var dataSection: some View {
        VStack(spacing: Design.Space.lg) {
            SettingsSection(title: "存储") {
                SettingsToggle(
                    title: "自动保存 PLY",
                    subtitle: "扫描后自动保存点云文件",
                    icon: "square.and.arrow.down",
                    isOn: $SettingsStore.shared.autoSavePLY
                )

                SettingsRow(label: "点云最大存储 (MB)", value: "\(SettingsStore.shared.maxStorageMB)") {
                    Slider(value: Binding(
                        get: { Double(SettingsStore.shared.maxStorageMB) },
                        set: { SettingsStore.shared.maxStorageMB = Int($0) }
                    ), in: 100...2000, step: 100)
                }
            }

            SettingsSection(title: "云同步") {
                SettingsToggle(
                    title: "iCloud 同步",
                    subtitle: "跨设备同步扫描记录",
                    icon: "icloud",
                    isOn: $SettingsStore.shared.enableCloudSync
                )

                SettingsToggle(
                    title: "Wi-Fi 下自动上传",
                    subtitle: "仅在连接 Wi-Fi 时上传数据",
                    icon: "wifi",
                    isOn: $SettingsStore.shared.wifiOnlyUpload
                )
            }

            SettingsSection(title: "导出") {
                SettingsToggle(
                    title: "扫描后自动导出 CSV",
                    subtitle: "每次扫描完成后自动导出数据表",
                    icon: "doc.text",
                    isOn: $SettingsStore.shared.autoExportCSV
                )

                SettingsNavRow(
                    title: "导出格式",
                    subtitle: "CSV / JSON / PLY",
                    icon: "square.and.arrow.up"
                )
            }

            SettingsSection(title: "关于") {
                HStack {
                    Text("版本")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Text("1.0.0")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
    }

    // MARK: - 扫描
    private var scanSection: some View {
        VStack(spacing: Design.Space.lg) {
            SettingsSection(title: "水果参数") {
                Picker("水果类型", selection: $SettingsStore.shared.fruitType) {
                    Text("苹果 🍎").tag("apple")
                    Text("橙子 🍊").tag("orange")
                    Text("梨 🍐").tag("pear")
                    Text("桃 🍑").tag("peach")
                    Text("樱桃 🍒").tag("cherry")
                }
                .pickerStyle(.segmented)

                Picker("季节", selection: $SettingsStore.shared.season) {
                    Text("成熟期").tag("mature")
                    Text("非成熟期").tag("off")
                }
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "聚类参数") {
                SettingsRow(label: "最小点数", value: "\(SettingsStore.shared.clusterMinPoints)") {
                    Slider(value: Binding(
                        get: { Double(SettingsStore.shared.clusterMinPoints) },
                        set: { SettingsStore.shared.clusterMinPoints = Int($0) }
                    ), in: 1...20, step: 1)
                }

                SettingsRow(label: "最小直径 (m)", value: String(format: "%.2f", SettingsStore.shared.clusterMinDiameter)) {
                    Slider(value: $SettingsStore.shared.clusterMinDiameter, in: 0.01...0.1, step: 0.01)
                }

                SettingsRow(label: "最大直径 (m)", value: String(format: "%.2f", SettingsStore.shared.clusterMaxDiameter)) {
                    Slider(value: $SettingsStore.shared.clusterMaxDiameter, in: 0.05...0.3, step: 0.01)
                }

                SettingsRow(label: "邻域半径 (m)", value: String(format: "%.2f", SettingsStore.shared.clusterBaseEps)) {
                    Slider(value: $SettingsStore.shared.clusterBaseEps, in: 0.05...0.3, step: 0.01)
                }
            }

            SettingsSection(title: "检测参数") {
                SettingsRow(label: "检测间隔 (帧)", value: "\(SettingsStore.shared.detectionInterval)") {
                    Slider(value: Binding(
                        get: { Double(SettingsStore.shared.detectionInterval) },
                        set: { SettingsStore.shared.detectionInterval = Int($0) }
                    ), in: 1...30, step: 1)
                }

                SettingsRow(label: "最低置信度", value: String(format: "%.2f", SettingsStore.shared.minConfidence)) {
                    Slider(value: $SettingsStore.shared.minConfidence, in: 0.1...0.9, step: 0.05)
                }

                SettingsRow(label: "球形度阈值", value: String(format: "%.2f", SettingsStore.shared.sphericityThreshold)) {
                    Slider(value: $SettingsStore.shared.sphericityThreshold, in: 0.3...0.9, step: 0.05)
                }
            }

            SettingsSection(title: "深度范围") {
                SettingsRow(label: "最近距离 (m)", value: String(format: "%.1f", SettingsStore.shared.depthRangeMin)) {
                    Slider(value: $SettingsStore.shared.depthRangeMin, in: 0.3...2.0, step: 0.1)
                }

                SettingsRow(label: "最远距离 (m)", value: String(format: "%.1f", SettingsStore.shared.depthRangeMax)) {
                    Slider(value: $SettingsStore.shared.depthRangeMax, in: 2.0...10.0, step: 0.5)
                }
            }

            SettingsSection(title: "帮助") {
                NavigationLink {
                    HelpView()
                } label: {
                    SettingsNavRow(
                        title: "使用指南",
                        subtitle: "扫描步骤与技巧",
                        icon: "questionmark.circle"
                    )
                }
            }
        }
    }
}

// MARK: - Settings Toggle
struct SettingsToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Design.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.forest.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Design.Colors.forest)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)
                Text(subtitle)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Design.Colors.forest)
        }
    }
}

// MARK: - Settings Nav Row
struct SettingsNavRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: Design.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.sage.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Design.Colors.sage)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)
                Text(subtitle)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Design.Colors.pebble)
        }
    }
}

#Preview {
    SettingsView()
}
