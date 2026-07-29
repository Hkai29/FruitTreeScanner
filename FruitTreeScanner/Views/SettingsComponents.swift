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
                            title: L10n.Settings.actualResolution,
                            value: settings.currentCameraResolutionDisplay
                        )

                        GlassDivider()

                        SettingsMenuRow(
                            icon: "rectangle.on.rectangle",
                            title: L10n.Settings.targetResolution,
                            value: $settings.cameraResolution,
                            options: SettingsStore.cameraResolutionOptions
                        )

                        GlassDivider()

                        SettingsMenuRow(
                            icon: "speedometer",
                            title: L10n.Settings.captureFrameRate,
                            value: $settings.cameraFrameRate,
                            options: SettingsStore.cameraFrameRateOptions
                        )
                    }
                    .padding(Design.Space.sm)
                    .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)

                    Text(L10n.Settings.cameraFormatHint)
                        .font(Design.Typography.darkCaption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(Design.Space.lg)
            }
        }
        .navigationTitle(L10n.Settings.cameraSettings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Settings.currentFruitType)
                    .font(Design.Typography.darkSubheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(L10n.Settings.fruitTypeHint)
                    .font(Design.Typography.darkCaption)
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            .accessibilityHidden(true)

            Spacer()

            Picker(L10n.Settings.currentFruitType, selection: $selection) {
                ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                    Text(L10n.Fruit.name(for: category)).tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
            .accessibilityLabel(L10n.Settings.currentFruitType)
            .accessibilityValue(L10n.Fruit.name(for: selection))
            .accessibilityHint(L10n.Settings.fruitTypeHint)
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
                .accessibilityHidden(true)

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
                .accessibilityHidden(true)
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
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(Design.Typography.darkSubheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Picker(title, selection: $value) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
            .accessibilityLabel(title)
            .accessibilityValue(optionLabel(value))
            .accessibilityHint(accessibilityHint)
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
