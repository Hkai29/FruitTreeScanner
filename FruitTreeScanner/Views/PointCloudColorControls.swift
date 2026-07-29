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
    let colorMode: PointCloudColorMode
    let bounds: PointCloudBounds?

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.PointCloud.colorLegend(modeName: colorMode.displayName))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.66))

            legendItems

            Spacer(minLength: 4)

            if let bounds {
                Text(L10n.PointCloud.actualHeight(bounds.heightText))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.harvest)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var legendItems: some View {
        switch colorMode {
        case .height:
            HStack(spacing: 4) {
                Rectangle().fill(Design.Colors.forest).frame(width: 14, height: 7).cornerRadius(2)
                Text(L10n.PointCloud.legendLow).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
                Rectangle().fill(Design.Colors.harvest).frame(width: 14, height: 7).cornerRadius(2)
                Text(L10n.PointCloud.legendHigh).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .density:
            HStack(spacing: 4) {
                Rectangle().fill(Color(hex: "8E8E93").opacity(0.35)).frame(width: 14, height: 7).cornerRadius(2)
                Text(L10n.PointCloud.legendSparse).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
                Rectangle().fill(Design.Colors.earth).frame(width: 14, height: 7).cornerRadius(2)
                Text(L10n.PointCloud.legendDense).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .fruit:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.harvest).frame(width: 8, height: 8)
                Text(L10n.PointCloud.legendFruitCandidates).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .uniform:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.forest).frame(width: 8, height: 8)
                Text(L10n.PointCloud.legendUniformBright).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        }
    }
}
