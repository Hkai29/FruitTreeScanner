import SwiftUI

struct PointCloudTopBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let pointCount: Int
    let bounds: PointCloudBounds?
    let viewMode: PointCloudViewMode
    let canExport: Bool
    let onClose: () -> Void
    let onExport: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
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

    private var compactLayout: some View {
        HStack(spacing: 10) {
            closeButton

            VStack(alignment: .leading, spacing: 4) {
                identityRow
                metricsRow
            }
            .lineLimit(1)

            Spacer(minLength: 6)

            shareButton
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                closeButton

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.PointCloud.viewerTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    modeBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                shareButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                metricsRow
                    .padding(.vertical, 1)
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 8) {
            Text(L10n.PointCloud.viewerTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            modeBadge
        }
    }

    private var modeBadge: some View {
        Text(viewMode.displayName)
            .font(.caption2.weight(.medium))
            .foregroundColor(Design.Colors.harvest)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Design.Colors.harvest.opacity(0.16))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }

    private var metricsRow: some View {
        HStack(spacing: 10) {
            PointCloudMetricText(label: L10n.PointCloud.pointsMetric, value: pointCount.formatted())
                .accessibilityLabel(L10n.PointCloud.pointCountAccessibility(pointCount.formatted()))
            if let bounds {
                PointCloudMetricText(label: L10n.PointCloud.heightMetric, value: bounds.heightText)
                    .accessibilityLabel(L10n.PointCloud.heightAccessibility(bounds.heightText))
                PointCloudMetricText(label: L10n.PointCloud.footprintMetric, value: bounds.footprintText)
                    .accessibilityLabel(L10n.PointCloud.footprintAccessibility(bounds.footprintText))
            }
        }
    }

    private var closeButton: some View {
        PointCloudCircleButton(
            icon: "xmark",
            isEnabled: true,
            action: onClose
        )
        .accessibilityLabel(L10n.PointCloud.closePreviewAccessibility)
        .accessibilityIdentifier("pointCloud.close")
    }

    private var shareButton: some View {
        PointCloudCircleButton(
            icon: "square.and.arrow.up",
            isEnabled: canExport,
            action: onExport
        )
        .accessibilityLabel(L10n.PointCloud.shareAccessibility)
        .accessibilityIdentifier("pointCloud.share")
    }
}

struct PointCloudBottomControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        toolButtons
                    }
                    .padding(.vertical, 1)
                }
            } else {
                HStack(spacing: 8) {
                    toolButtons
                }
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

    @ViewBuilder
    private var toolButtons: some View {
        PointCloudToolButton(icon: "arrow.uturn.backward", label: L10n.PointCloud.reset, isEnabled: canInteract, action: onResetCamera)
            .accessibilityIdentifier("pointCloud.resetCamera")
        PointCloudColorModeMenu(colorMode: $colorMode, isEnabled: canInteract)
            .accessibilityIdentifier("pointCloud.colorMode")
        PointCloudToolButton(icon: "plus.magnifyingglass", label: L10n.PointCloud.zoomIn, isEnabled: canInteract, action: onZoomIn)
            .accessibilityIdentifier("pointCloud.zoomIn")
        PointCloudToolButton(icon: "minus.magnifyingglass", label: L10n.PointCloud.zoomOut, isEnabled: canInteract, action: onZoomOut)
            .accessibilityIdentifier("pointCloud.zoomOut")
        PointCloudToolButton(
            icon: "ruler",
            label: L10n.PointCloud.measure,
            isActive: isMeasurementActive,
            isEnabled: canInteract,
            action: onToggleMeasurement
        )
        .accessibilityIdentifier("pointCloud.measure")
    }
}
