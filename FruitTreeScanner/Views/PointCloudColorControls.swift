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
                        Text(mode.rawValue)
                        if mode == colorMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            PointCloudToolLabel(icon: colorMode.icon, label: "色彩", isActive: false)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PointCloudColorLegend: View {
    let colorMode: PointCloudColorMode
    let bounds: PointCloudBounds?

    var body: some View {
        HStack(spacing: 8) {
            Text("色彩: \(colorMode.rawValue)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.66))

            legendItems

            Spacer(minLength: 4)

            if let bounds {
                Text("真实高度 \(bounds.heightText)")
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
                Text("低").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
                Rectangle().fill(Design.Colors.harvest).frame(width: 14, height: 7).cornerRadius(2)
                Text("高").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .density:
            HStack(spacing: 4) {
                Rectangle().fill(Color(hex: "8E8E93").opacity(0.35)).frame(width: 14, height: 7).cornerRadius(2)
                Text("稀").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
                Rectangle().fill(Design.Colors.earth).frame(width: 14, height: 7).cornerRadius(2)
                Text("密").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .fruit:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.harvest).frame(width: 8, height: 8)
                Text("果实候选").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        case .uniform:
            HStack(spacing: 4) {
                Circle().fill(Design.Colors.forest).frame(width: 8, height: 8)
                Text("统一亮色").font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
            }
        }
    }
}
