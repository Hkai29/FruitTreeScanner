import SwiftUI

struct PointCloudColorChoices: View {
    @ScaledMetric(relativeTo: .subheadline) private var symbolWidth: CGFloat = 24
    @Binding var colorMode: PointCloudColorMode
    var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.PointCloud.color)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(Design.Colors.Dark.textMuted)
                .padding(.bottom, 4)
            ForEach(PointCloudColorMode.allCases, id: \.self) { mode in
                Button { colorMode = mode } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon).frame(width: symbolWidth).accessibilityHidden(true)
                        Text(mode.displayName).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if colorMode == mode {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(colorMode == mode ? Design.Colors.Dark.glow : Design.Colors.Dark.textSecondary)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(
                        colorMode == mode
                            ? Design.Colors.Dark.glow.opacity(0.12)
                            : Color.clear
                    )
                    .overlay(alignment: .leading) {
                        if colorMode == mode {
                            Rectangle()
                                .fill(Design.Colors.Dark.glow)
                                .frame(width: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(colorMode == mode ? .isSelected : [])
                .accessibilityIdentifier("pointCloud.colorMode.\(mode.rawValue)")
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PointCloudColorModeMenu: View {
    @Binding var colorMode: PointCloudColorMode
    var isEnabled = true

    var body: some View {
        Menu {
            ForEach(PointCloudColorMode.allCases, id: \.self) { mode in
                Button {
                    colorMode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.displayName)
                        if mode == colorMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            PointCloudToolLabel(icon: colorMode.icon, label: L10n.PointCloud.color, isActive: false)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(L10n.PointCloud.color)
        .accessibilityValue(colorMode.displayName)
    }
}

struct PointCloudColorLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let colorMode: PointCloudColorMode
    let bounds: PointCloudBounds?

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxxLarge {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        colorModeLabel
                        legendItems
                        actualHeight
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 1)
                }
            } else {
                HStack(spacing: 8) {
                    colorModeLabel

                    legendItems

                    Spacer(minLength: 4)

                    actualHeight
                }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var colorModeLabel: some View {
        Text(L10n.PointCloud.colorLegend(modeName: colorMode.displayName))
            .font(.system(.caption2, design: .default).weight(.medium))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actualHeight: some View {
        if let bounds {
            Text(L10n.PointCloud.actualHeight(bounds.heightText))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Dark.glow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var legendItems: some View {
        switch colorMode {
        case .height:
            HStack(spacing: 4) {
                Rectangle().fill(Color(.sRGB, red: 0.24, green: 0.28, blue: 1, opacity: 1)).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendLow)
                Rectangle().fill(Color(.sRGB, red: 1, green: 0.28, blue: 0.30, opacity: 1)).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendHigh)
            }
        case .density:
            HStack(spacing: 4) {
                Rectangle().fill(Color(.sRGB, red: 0.16, green: 0.22, blue: 0.30, opacity: 1)).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendSparse)
                Rectangle().fill(Color(.sRGB, red: 0.61, green: 0.80, blue: 0.98, opacity: 1)).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendDense)
            }
        case .fruit:
            HStack(spacing: 4) {
                Circle().fill(Color(.sRGB, red: 1, green: 0.58, blue: 0.04, opacity: 1)).frame(width: 8, height: 8).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendFruitCandidates)
            }
        case .uniform:
            HStack(spacing: 4) {
                Circle().fill(Color(.sRGB, red: 0.48, green: 0.88, blue: 0.46, opacity: 1)).frame(width: 8, height: 8).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendUniformBright)
            }
        }
    }

    private func legendText(_ value: String) -> some View {
        Text(value)
            .font(.system(.caption2, design: .default))
            .foregroundColor(Design.Colors.Dark.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
