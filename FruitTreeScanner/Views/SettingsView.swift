// SettingsView.swift
// 设置页面 - 扫描参数、云同步、GPS、About

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("fruitType") private var fruitType: String = "apple"
    @AppStorage("season") private var season: String = "mature"
    @AppStorage("enableCloudSync") private var enableCloudSync: Bool = false
    @AppStorage("autoExport") private var autoExport: Bool = false
    @AppStorage("depthRangeMin") private var depthRangeMin: Double = 0.5
    @AppStorage("depthRangeMax") private var depthRangeMax: Double = 5.0

    // 聚类参数
    @AppStorage("clusterMinPoints") private var clusterMinPoints: Int = 5
    @AppStorage("clusterMinDiameter") private var clusterMinDiameter: Double = 0.02
    @AppStorage("clusterMaxDiameter") private var clusterMaxDiameter: Double = 0.15
    @AppStorage("clusterBaseEps") private var clusterBaseEps: Double = 0.1

    // 检测参数
    @AppStorage("detectionInterval") private var detectionInterval: Int = 10
    @AppStorage("minConfidence") private var minConfidence: Double = 0.5
    @AppStorage("sphericityThreshold") private var sphericityThreshold: Double = 0.5

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        fruitTypeSection
                        seasonSection
                        clusterSection
                        detectionSection
                        depthRangeSection
                        syncSection
                        aboutSection
                    }
                    .padding(Design.Space.lg)
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

    // MARK: - 水果类型
    private var fruitTypeSection: some View {
        SettingsSection(title: "水果类型") {
            Picker("水果", selection: $fruitType) {
                Text("苹果 🍎").tag("apple")
                Text("橙子 🍊").tag("orange")
                Text("梨 🍐").tag("pear")
                Text("桃 🍑").tag("peach")
                Text("樱桃 🍒").tag("cherry")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 季节
    private var seasonSection: some View {
        SettingsSection(title: "季节模式") {
            Picker("季节", selection: $season) {
                Text("成熟期").tag("mature")
                Text("非成熟期").tag("off")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 聚类参数
    private var clusterSection: some View {
        SettingsSection(title: "聚类参数") {
            SettingsRow(label: "最小点数", value: "\(clusterMinPoints)") {
                Slider(value: Binding(
                    get: { Double(clusterMinPoints) },
                    set: { clusterMinPoints = Int($0) }
                ), in: 1...20, step: 1)
            }

            SettingsRow(label: "最小直径 (m)", value: String(format: "%.2f", clusterMinDiameter)) {
                Slider(value: $clusterMinDiameter, in: 0.01...0.1, step: 0.01)
            }

            SettingsRow(label: "最大直径 (m)", value: String(format: "%.2f", clusterMaxDiameter)) {
                Slider(value: $clusterMaxDiameter, in: 0.05...0.3, step: 0.01)
            }

            SettingsRow(label: "邻域半径 (m)", value: String(format: "%.2f", clusterBaseEps)) {
                Slider(value: $clusterBaseEps, in: 0.05...0.3, step: 0.01)
            }
        }
    }

    // MARK: - 检测参数
    private var detectionSection: some View {
        SettingsSection(title: "检测参数") {
            SettingsRow(label: "检测间隔 (帧)", value: "\(detectionInterval)") {
                Slider(value: Binding(
                    get: { Double(detectionInterval) },
                    set: { detectionInterval = Int($0) }
                ), in: 1...30, step: 1)
            }

            SettingsRow(label: "最低置信度", value: String(format: "%.2f", minConfidence)) {
                Slider(value: $minConfidence, in: 0.1...0.9, step: 0.05)
            }

            SettingsRow(label: "球形度阈值", value: String(format: "%.2f", sphericityThreshold)) {
                Slider(value: $sphericityThreshold, in: 0.3...0.9, step: 0.05)
            }
        }
    }

    // MARK: - 深度范围
    private var depthRangeSection: some View {
        SettingsSection(title: "扫描深度范围") {
            SettingsRow(label: "最近 (m)", value: String(format: "%.1f", depthRangeMin)) {
                Slider(value: $depthRangeMin, in: 0.3...2.0, step: 0.1)
            }

            SettingsRow(label: "最远 (m)", value: String(format: "%.1f", depthRangeMax)) {
                Slider(value: $depthRangeMax, in: 2.0...10.0, step: 0.5)
            }
        }
    }

    // MARK: - 云同步
    private var syncSection: some View {
        SettingsSection(title: "云同步") {
            Toggle("启用 iCloud 同步", isOn: $enableCloudSync)
                .tint(Design.Colors.forest)

            Toggle("扫描后自动导出 CSV", isOn: $autoExport)
                .tint(Design.Colors.forest)
        }
    }

    // MARK: - 关于
    private var aboutSection: some View {
        SettingsSection(title: "关于") {
            HStack {
                Text("版本")
                    .foregroundColor(Design.Colors.charcoal)
                Spacer()
                Text("1.0.0")
                    .foregroundColor(Design.Colors.slate)
            }

            NavigationLink {
                HelpView()
            } label: {
                HStack {
                    Text("使用帮助")
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.slate)
                }
            }

            NavigationLink {
                CalibrationView()
            } label: {
                HStack {
                    Text("设备校准")
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text(title)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.slate)
                .textCase(.uppercase)

            VStack(spacing: Design.Space.md) {
                content
            }
            .padding(Design.Space.md)
            .background(Design.Colors.bgSurface)
            .cornerRadius(Design.Radius.large)
        }
    }
}

// MARK: - Settings Row
struct SettingsRow<SliderContent: View>: View {
    let label: String
    let value: String
    @ViewBuilder let slider: SliderContent

    var body: some View {
        VStack(spacing: Design.Space.xs) {
            HStack {
                Text(label)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.charcoal)
                Spacer()
                Text(value)
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.forest)
            }
            slider
        }
    }
}

#Preview {
    SettingsView()
}
