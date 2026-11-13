// SettingsComponents.swift
// 设置页与相机设置页的行组件。
//
// 约定：
//   1. 控件直接读写 SettingsStore，页面不持有参数副本。
//   2. 行内的说明文字从无障碍树中隐藏，名称与读数由 Picker / Slider / Toggle 自身承载，
//      这样读屏只会念一次标题，数值由控件的 accessibilityValue 播报。
//   3. 图标是装饰，一律 accessibilityHidden。

import SwiftUI

// MARK: - 分组

/// 设置页的一个分区：小标签 + 白色列表组，组内以发丝线分隔。
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: title)

            InstrumentRowGroup {
                content()
            }
        }
    }
}

// MARK: - 相机设置

struct CameraSettingsView: View {
    @ObservedObject private var settings: SettingsStore

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InstrumentPanel(
                    label: L10n.Settings.cameraSettings,
                    systemImage: "camera.metering.center.weighted"
                ) {
                    VStack(spacing: 0) {
                        SettingsValueRow(
                            systemImage: "rectangle.on.rectangle",
                            title: L10n.Settings.actualResolution,
                            value: settings.currentCameraResolutionDisplay
                        )

                        DividerLine()

                        SettingsMenuRow(
                            icon: "rectangle.on.rectangle",
                            title: L10n.Settings.targetResolution,
                            value: $settings.cameraResolution,
                            options: SettingsStore.cameraResolutionOptions
                        )

                        DividerLine()

                        SettingsMenuRow(
                            icon: "speedometer",
                            title: L10n.Settings.captureFrameRate,
                            value: $settings.cameraFrameRate,
                            options: SettingsStore.cameraFrameRateOptions
                        )
                    }
                }

                Text(L10n.Settings.cameraFormatHint)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .workspacePage()
        .navigationTitle(L10n.Settings.cameraSettings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Design.Colors.Workspace.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - 水果类型

struct FruitCategorySettingsRow: View {
    @Binding var selection: FruitCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Settings.currentFruitType)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                Text(L10n.Settings.fruitTypeHint)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 8)

            Picker(L10n.Settings.currentFruitType, selection: $selection) {
                ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                    Text(L10n.Fruit.name(for: category)).tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Design.Colors.Workspace.accent)
            .accessibilityLabel(L10n.Settings.currentFruitType)
            .accessibilityValue(L10n.Fruit.name(for: selection))
            .accessibilityHint(L10n.Settings.fruitTypeHint)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - 跳转行

/// 设置列表里的跳转行。名称由外层 NavigationLink 统一播报。
struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            InstrumentChevron()
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - 读数行

/// 只读读数行：标题 + 当前值（等宽数字）。
struct SettingsValueRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.ink)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - 开关行

struct SettingsToggleRow: View {
    let systemImage: String
    let title: String
    @Binding var isOn: Bool
    var accessibilityHint: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
            }
            .tint(Design.Colors.Workspace.accent)
            .accessibilityHint(accessibilityHint)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - 枚举行

struct SettingsMenuRow: View {
    let icon: String
    let title: String
    @Binding var value: String
    let options: [String]
    let optionLabel: (String) -> String
    let accessibilityHint: String

    init(
        icon: String,
        title: String,
        value: Binding<String>,
        options: [String],
        optionLabel: @escaping (String) -> String = { $0 },
        accessibilityHint: String = ""
    ) {
        self.icon = icon
        self.title = title
        _value = value
        self.options = options
        self.optionLabel = optionLabel
        self.accessibilityHint = accessibilityHint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.ink)
                .accessibilityHidden(true)

            Spacer(minLength: 8)

            Picker(title, selection: $value) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Design.Colors.Workspace.accent)
            .accessibilityLabel(title)
            .accessibilityValue(optionLabel(value))
            .accessibilityHint(accessibilityHint)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - 滑杆行

/// 数值滑杆行。拖动期间只改草稿，编辑结束由外部回调提交。
struct SettingsSliderRow: View {
    let systemImage: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var displayValue: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    var accessibilityHint: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Text(displayValue)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }

            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: onEditingChanged
            )
            .tint(Design.Colors.Workspace.accent)
            .accessibilityLabel(title)
            .accessibilityValue(displayValue)
            .accessibilityHint(accessibilityHint)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

// MARK: - 说明文字

struct SettingsInlineHint: View {
    let text: String
    var inset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(Design.Colors.Workspace.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, inset)
            .padding(.vertical, 6)
    }
}
