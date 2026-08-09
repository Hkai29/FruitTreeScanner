import SwiftUI

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
            if dynamicTypeSize.isAccessibilitySize {
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
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.66))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actualHeight: some View {
        if let bounds {
            Text(L10n.PointCloud.actualHeight(bounds.heightText))
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundColor(Design.Colors.harvest)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var legendItems: some View {
        switch colorMode {
        case .height:
            HStack(spacing: 4) {
                Rectangle().fill(Design.Colors.forest).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendLow)
                Rectangle().fill(Design.Colors.harvest).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendHigh)
            }
        case .density:
            HStack(spacing: 4) {
                Rectangle().fill(Color(hex: "8E8E93").opacity(0.35)).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendSparse)
                Rectangle().fill(Design.Colors.earth).frame(width: 14, height: 7).cornerRadius(2).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendDense)
            }
        case .fruit:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.harvest).frame(width: 8, height: 8).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendFruitCandidates)
            }
        case .uniform:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.forest).frame(width: 8, height: 8).accessibilityHidden(true)
                legendText(L10n.PointCloud.legendUniformBright)
            }
        }
    }

    private func legendText(_ value: String) -> some View {
        Text(value)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.58))
            .fixedSize(horizontal: false, vertical: true)
    }
}
