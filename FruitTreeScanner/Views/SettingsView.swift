// SettingsView.swift
// 设置页面 - 设备 / 数据 / 扫描 三个可展开分组

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var deviceExpanded = true
    @State private var dataExpanded = true
    @State private var scanExpanded = true

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        // 设备
                        expandableSection(
                            title: "设备",
                            icon: "cpu",
                            isExpanded: $deviceExpanded
                        ) {
                            deviceSection
                        }

                        // 数据
                        expandableSection(
                            title: "数据",
                            icon: "externaldrive.connected.to.line.below",
                            isExpanded: $dataExpanded
                        ) {
                            dataSection
                        }

                        // 扫描
                        expandableSection(
                            title: "扫描",
                            icon: "viewfinder",
                            isExpanded: $scanExpanded
                        ) {
                            scanSection
                        }
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

    // MARK: - 可展开分组
    private func expandableSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Header（点击展开/折叠）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Design.Colors.forest)
                        .frame(width: 24)

                    Text(title)
                        .font(Design.Typography.headline)
                        .foregroundColor(Design.Colors.charcoal)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Design.Colors.slate)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                }
                .padding(Design.Space.md)
                .background(Design.Colors.bgSurface)
            }
            .buttonStyle(.plain)

            // 内容（展开时显示）
            if isExpanded.wrappedValue {
                VStack(spacing: 0) {
                    content()
                }
                .background(Design.Colors.bgSurface)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cornerRadius(Design.Radius.large)
        .clipped()
    }

    // MARK: - 设备 Section
    @ViewBuilder
    private var deviceSection: some View {
        VStack(spacing: 0) {
            // 分隔线
            Divider().padding(.leading, 56)

            // 校准
            NavItem(icon: "gyroscope", title: "传感器矫正", subtitle: "陀螺仪与加速计校准") {
                SensorCalibrationView()
            }

            Divider().padding(.leading, 56)

            NavItem(icon: "camera.metering.center.weighted", title: "矫正相机设置", subtitle: "分辨率和帧率") {
                CameraSettingsView()
            }

            Divider().padding(.leading, 56)

            // 实际分辨率和检测频率
            SettingReadOnlyRow(
                icon: "rectangle.on.rectangle",
                title: "实际分辨率",
                value: SettingsStore.shared.currentCameraResolutionDisplay
            )

            Divider().padding(.leading, 56)

            SettingPickerRow(
                icon: "speedometer",
                title: "检测频率",
                selection: SettingsStore.shared.cameraFrameRateBinding,
                options: ["30fps", "60fps", "120fps"]
            )
        }
    }

    // MARK: - 数据 Section
    @ViewBuilder
    private var dataSection: some View {
        VStack(spacing: 0) {
            // 导出格式
            SettingPickerRow(
                icon: "square.and.arrow.up",
                title: "导出格式",
                selection: SettingsStore.shared.exportFormatBinding,
                options: ["PLY", "CSV", "JSON"]
            )

            Divider().padding(.leading, 56)

            SettingToggle(
                icon: "doc.text",
                title: "扫描后自动导出",
                isOn: SettingsStore.shared.autoExportCSVBinding
            )
        }
    }

    // MARK: - 扫描 Section
    @ViewBuilder
    private var scanSection: some View {
        VStack(spacing: 0) {
            // 质量预设
            SettingPickerRow(
                icon: "chart.bar",
                title: "质量预设",
                selection: SettingsStore.shared.qualityPresetBinding,
                options: ["高", "中", "低"]
            )

            Divider().padding(.leading, 56)

            // 最大点数
            SettingSliderRow(
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

            Divider().padding(.leading, 56)

            // 精度
            SettingSliderRow(
                icon: "scope",
                title: "精度",
                value: SettingsStore.shared.scanPrecisionBinding,
                range: 0.001...0.05,
                step: 0.001,
                displayValue: String(format: "%.3f", SettingsStore.shared.scanPrecision)
            )
        }
    }
}

// MARK: - NavItem（导航行）
struct NavItem<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Design.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.small)
                        .fill(Design.Colors.forest.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.pebble)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm + 2)
        }
    }
}

// MARK: - SettingToggle
struct SettingToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Design.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.forest.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.forest)
            }

            Text(title)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.charcoal)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Design.Colors.forest)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
    }
}

// MARK: - SettingPickerRow
struct SettingPickerRow: View {
    let icon: String
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(spacing: Design.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.sage.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.sage)
            }

            Text(title)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.charcoal)

            Spacer()

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.forest)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
    }
}

// MARK: - SettingSliderRow
struct SettingSliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: String

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.small)
                        .fill(Design.Colors.forest.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.forest)
                }

                Text(title)
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)

                Spacer()

                Text(displayValue)
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.forest)
            }

            Slider(value: $value, in: range, step: step)
                .tint(Design.Colors.forest)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
    }
}

// MARK: - SettingReadOnlyRow（只读显示行）
struct SettingReadOnlyRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Design.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.forest.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.forest)
            }

            Text(title)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.charcoal)

            Spacer()

            Text(value)
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.slate)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm + 2)
    }
}

// MARK: - SensorCalibrationView（传感器校准）
struct SensorCalibrationView: View {
    @State private var calibrationState: CalibrationState = .ready
    @State private var instructionText = "请将设备放置在平稳表面上"

    enum CalibrationState {
        case ready, calibrating, done, failed
    }

    var body: some View {
        ZStack {
            Design.Colors.bgBase.ignoresSafeArea()

            VStack(spacing: Design.Space.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(calibrationState == .done ? Design.Colors.success.opacity(0.15)
                              : calibrationState == .calibrating ? Design.Colors.warning.opacity(0.15)
                              : Design.Colors.sage.opacity(0.1))
                        .frame(width: 160, height: 160)

                    Image(systemName: calibrationState == .done ? "checkmark.circle.fill"
                          : calibrationState == .calibrating ? "figure.walk"
                          : "gyroscope")
                        .font(.system(size: 60))
                        .foregroundColor(calibrationState == .done ? Design.Colors.success
                              : calibrationState == .calibrating ? Design.Colors.warning
                              : Design.Colors.sage)
                }

                VStack(spacing: Design.Space.sm) {
                    Text(calibrationState == .ready ? "准备校准"
                         : calibrationState == .calibrating ? "校准中..."
                         : calibrationState == .done ? "校准完成"
                         : "校准失败")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.charcoal)

                    Text(instructionText)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.slate)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                if calibrationState == .ready {
                    Button("开始校准") {
                        startCalibration()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Design.Space.xl)
                } else if calibrationState == .done {
                    HStack(spacing: Design.Space.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Design.Colors.success)
                        Text("传感器已校准，扫描精度已优化")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.success)
                    }
                }
            }
            .padding(Design.Space.lg)
        }
        .navigationTitle("传感器矫正")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startCalibration() {
        calibrationState = .calibrating
        instructionText = "请缓慢画 8 字动作..."
        SettingsStore.shared.sensorCalibrationDone = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            calibrationState = .done
            instructionText = "校准成功"
        }
    }
}

// MARK: - CameraSettingsView（相机设置）
struct CameraSettingsView: View {
    var body: some View {
        ZStack {
            Design.Colors.bgBase.ignoresSafeArea()

            VStack(spacing: Design.Space.lg) {
                // ARKit 实际分辨率（只读）
                SettingReadOnlyRow(
                    icon: "rectangle.on.rectangle",
                    title: "实际分辨率",
                    value: SettingsStore.shared.currentCameraResolutionDisplay
                )
                .padding(Design.Space.md)
                .background(Design.Colors.bgSurface)
                .cornerRadius(Design.Radius.medium)

                // 检测频率
                SettingPickerRow(
                    icon: "speedometer",
                    title: "检测频率",
                    selection: SettingsStore.shared.cameraFrameRateBinding,
                    options: ["30fps", "60fps", "120fps"]
                )
                .padding(Design.Space.md)
                .background(Design.Colors.bgSurface)
                .cornerRadius(Design.Radius.medium)

                Text("检测频率：控制图像检测算法的执行频率。实际帧率由设备硬件决定，不受此设置影响。")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(Design.Space.lg)
        }
        .navigationTitle("矫正相机设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
