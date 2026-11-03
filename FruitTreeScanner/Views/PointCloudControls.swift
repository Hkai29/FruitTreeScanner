// PointCloudControls.swift
// 点云视口的读数条与工具入口。
// 顶部读数条同时承担来源标注，避免把导入/外部样例误认为设备实采。

import SwiftUI

struct PointCloudTopBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let pointCount: Int
    let bounds: PointCloudBounds?
    let viewMode: PointCloudViewMode
    let canExport: Bool
    let onClose: () -> Void
    let onExport: () -> Void
    var title: String? = nil
    var provenance: PointCloudProvenance = .externalFile
    var onChooseArchive: (() -> Void)? = nil

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(10)
        .background(Design.Colors.Dark.bgSurface.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                closeButton
                titleControl.frame(maxWidth: .infinity, alignment: .leading)
                shareButton
            }
            ScrollView(.horizontal, showsIndicators: false) { metricsRow }
                .padding(.bottom, 2)
            DividerLine(color: Design.Colors.Dark.glassBorder)
            provenanceRow
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                closeButton

                VStack(alignment: .leading, spacing: 6) {
                    titleControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                shareButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                metricsRow
                    .padding(.vertical, 1)
            }

            DividerLine(color: Design.Colors.Dark.glassBorder)
            provenanceRow
        }
    }

    @ViewBuilder
    private var titleControl: some View {
        if let onChooseArchive {
            Button(action: onChooseArchive) {
                HStack(spacing: 6) {
                    titleText
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(WorkspaceText.chooseArchive)，\(title ?? L10n.PointCloud.viewerTitle)")
            .accessibilityIdentifier("pointCloud.selectArchive")
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title ?? L10n.PointCloud.viewerTitle)
            .font(.system(.headline, design: .monospaced).weight(.semibold))
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metricsRow: some View {
        HStack(spacing: 16) {
            PointCloudMetricText(label: L10n.PointCloud.pointsMetric, value: pointCount.formatted())
                .accessibilityLabel(L10n.PointCloud.pointCountAccessibility(pointCount.formatted()))
            if let bounds, !(dynamicTypeSize.isAccessibilitySize && verticalSizeClass == .compact) {
                PointCloudMetricText(label: L10n.PointCloud.heightMetric, value: bounds.heightText)
                    .accessibilityLabel(L10n.PointCloud.heightAccessibility(bounds.heightText))
                PointCloudMetricText(label: L10n.PointCloud.footprintMetric, value: bounds.footprintText)
                    .accessibilityLabel(L10n.PointCloud.footprintAccessibility(bounds.footprintText))
            }
        }
    }

    /// 来源标注：只陈述可证实的事实（是否在扫描档案内、是否带结果文件）。
    private var provenanceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: provenance.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(provenanceTint)
                .accessibilityHidden(true)
            Text(provenance.label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.6)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provenance.label)
    }

    private var provenanceTint: Color {
        switch provenance {
        case .archivedScan: return Design.Colors.Dark.success
        case .archivedWithoutResult: return Design.Colors.Dark.warning
        case .externalFile: return Design.Colors.Dark.textMuted
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
        VStack(alignment: .leading, spacing: 18) {
            if dynamicTypeSize.isAccessibilitySize, let bounds {
                ViewThatFits(in: .horizontal) {
                    boundsReadings(bounds)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.PointCloud.heightAccessibility(bounds.heightText))
                        Text(L10n.PointCloud.footprintAccessibility(bounds.footprintText))
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            PointCloudViewModePicker(viewMode: $viewMode, isEnabled: canInteract)
            DividerLine(color: Design.Colors.Dark.glassBorder)
            PointCloudColorChoices(colorMode: $colorMode, isEnabled: canInteract)
            PointCloudColorLegend(colorMode: colorMode, bounds: bounds)
            DividerLine(color: Design.Colors.Dark.glassBorder)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                      count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: 8) {
                toolButtons
            }
        }
    }

    private func boundsReadings(_ bounds: PointCloudBounds) -> some View {
        HStack(spacing: 20) {
            Text(L10n.PointCloud.heightAccessibility(bounds.heightText))
            Text(L10n.PointCloud.footprintAccessibility(bounds.footprintText))
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var toolButtons: some View {
        PointCloudToolButton(icon: "arrow.uturn.backward", label: L10n.PointCloud.reset, isEnabled: canInteract, action: onResetCamera)
            .accessibilityIdentifier("pointCloud.resetCamera")
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

/// 工具入口条。显示当前视角与着色方式。
struct PointCloudToolsEntry: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let viewMode: PointCloudViewMode
    let colorMode: PointCloudColorMode
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.PointCloud.toolsTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    if verticalSizeClass != .compact {
                        Text("\(viewMode.displayName) · \(colorMode.displayName)")
                            .font(.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .background(Design.Colors.Dark.bgSurface.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.PointCloud.toolsTitle)
        .accessibilityValue("\(viewMode.displayName)，\(colorMode.displayName)")
        .accessibilityIdentifier("pointCloud.tools")
    }
}
