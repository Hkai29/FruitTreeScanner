import SwiftUI

struct PointCloudTopBar: View {
    let pointCount: Int
    let bounds: PointCloudBounds?
    let viewMode: PointCloudViewMode
    let canExport: Bool
    let onClose: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PointCloudCircleButton(
                icon: "xmark",
                isEnabled: true,
                action: onClose
            )
            .accessibilityLabel("关闭点云预览")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("点云查看")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(viewMode.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Design.Colors.harvest.opacity(0.16))
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    PointCloudMetricText(label: "点", value: pointCount.formatted())
                    if let bounds {
                        PointCloudMetricText(label: "高", value: bounds.heightText)
                        PointCloudMetricText(label: "冠幅", value: bounds.footprintText)
                    }
                }
            }
            .lineLimit(1)

            Spacer(minLength: 6)

            PointCloudCircleButton(
                icon: "square.and.arrow.up",
                isEnabled: canExport,
                action: onExport
            )
            .accessibilityLabel("分享点云")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Design.Colors.Dark.hudBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct PointCloudBottomControls: View {
    let pointCount: Int
    let canInteract: Bool
    let bounds: PointCloudBounds?
    @Binding var colorMode: PointCloudColorMode
    @Binding var viewMode: PointCloudViewMode
    let isMeasurementActive: Bool
    let onResetCamera: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onToggleMeasurement: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            PointCloudViewModePicker(viewMode: $viewMode, isEnabled: canInteract)

            HStack(spacing: 8) {
                PointCloudToolButton(icon: "arrow.uturn.backward", label: "重置", isEnabled: canInteract, action: onResetCamera)
                PointCloudColorModeMenu(colorMode: $colorMode, isEnabled: canInteract)
                PointCloudToolButton(icon: "plus.magnifyingglass", label: "放大", isEnabled: canInteract, action: onZoomIn)
                PointCloudToolButton(icon: "minus.magnifyingglass", label: "缩小", isEnabled: canInteract, action: onZoomOut)
                PointCloudToolButton(
                    icon: "ruler",
                    label: "测量",
                    isActive: isMeasurementActive,
                    isEnabled: canInteract,
                    action: onToggleMeasurement
                )
            }

            PointCloudColorLegend(colorMode: colorMode, bounds: bounds)
        }
        .padding(10)
        .background(Design.Colors.Dark.hudBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

private struct PointCloudMetricText: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundColor(.white.opacity(0.52))
            Text(value)
                .foregroundColor(.white.opacity(0.86))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }
}

private struct PointCloudViewModePicker: View {
    @Binding var viewMode: PointCloudViewMode
    var isEnabled = true

    var body: some View {
        HStack(spacing: 5) {
            ForEach(PointCloudViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(viewMode == mode ? Color.black.opacity(0.82) : .white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewMode == mode ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                    .cornerRadius(8)
                }
                .disabled(!isEnabled)
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

private struct PointCloudCircleButton: View {
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct PointCloudToolButton: View {
    let icon: String
    let label: String
    var isActive = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PointCloudToolLabel(icon: icon, label: label, isActive: isActive)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct PointCloudToolLabel: View {
    let icon: String
    let label: String
    var isActive = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))

            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isActive ? Design.Colors.harvest : .white.opacity(0.86))
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(isActive ? Design.Colors.harvest.opacity(0.18) : Design.Colors.Dark.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
