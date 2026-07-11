import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
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
                    .padding(Design.Space.sm)
                    .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)

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

struct FruitCategorySettingsRow: View {
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
                ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                    Text(L10n.Fruit.name(for: category)).tag(category)
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

struct SettingsNavigationRow: View {
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

struct SettingsMenuRow: View {
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

struct SettingsInlineHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Design.Typography.darkCaption)
            .foregroundColor(Design.Colors.Dark.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Space.md)
            .padding(.top, Design.Space.xs)
            .padding(.bottom, Design.Space.sm)
    }
}
