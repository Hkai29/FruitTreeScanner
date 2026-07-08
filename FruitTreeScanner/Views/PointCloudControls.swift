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
            .accessibilityIdentifier("pointCloud.close")

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
            .accessibilityIdentifier("pointCloud.share")
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
                    .accessibilityIdentifier("pointCloud.resetCamera")
                PointCloudColorModeMenu(colorMode: $colorMode, isEnabled: canInteract)
                    .accessibilityIdentifier("pointCloud.colorMode")
                PointCloudToolButton(icon: "plus.magnifyingglass", label: "放大", isEnabled: canInteract, action: onZoomIn)
                    .accessibilityIdentifier("pointCloud.zoomIn")
                PointCloudToolButton(icon: "minus.magnifyingglass", label: "缩小", isEnabled: canInteract, action: onZoomOut)
                    .accessibilityIdentifier("pointCloud.zoomOut")
                PointCloudToolButton(
                    icon: "ruler",
                    label: "测量",
                    isActive: isMeasurementActive,
                    isEnabled: canInteract,
                    action: onToggleMeasurement
                )
                .accessibilityIdentifier("pointCloud.measure")
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
