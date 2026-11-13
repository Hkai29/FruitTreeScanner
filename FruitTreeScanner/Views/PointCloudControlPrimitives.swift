// PointCloudControlPrimitives.swift
// 点云视口的基础控件。深色画布上的文字层级与浅色页一致，只是换了明度。

import SwiftUI

struct PointCloudMetricText: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.5)
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct PointCloudViewModePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var viewMode: PointCloudViewMode
    var isEnabled = true

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        modeButtons(expandsToFill: false)
                    }
                    .padding(.vertical, 1)
                }
            } else {
                HStack(spacing: 5) {
                    modeButtons(expandsToFill: true)
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    @ViewBuilder
    private func modeButtons(expandsToFill: Bool) -> some View {
        ForEach(PointCloudViewMode.allCases, id: \.self) { mode in
            Button {
                viewMode = mode
            } label: {
                HStack(spacing: 5) {
                    Text(mode.displayName)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: !expandsToFill, vertical: true)
                }
                .foregroundColor(viewMode == mode ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textSecondary)
                .padding(.horizontal, expandsToFill ? 4 : 12)
                .frame(maxWidth: expandsToFill ? .infinity : nil, minHeight: 40)
                .fixedSize(horizontal: !expandsToFill, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(viewMode == mode ? Design.Colors.Dark.glow : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .stroke(
                            viewMode == mode ? Color.clear : Design.Colors.Dark.glassBorder,
                            lineWidth: 1
                        )
                )
            }
            .disabled(!isEnabled)
            .accessibilityLabel(mode.displayName)
            .accessibilityValue(mode.detail)
            .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
            .accessibilityIdentifier("pointCloud.viewMode.\(mode.rawValue)")
        }
    }
}

struct PointCloudCircleButton: View {
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PointCloudToolButton: View {
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
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct PointCloudToolLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let label: String
    var isActive = false

    private var usesExpandedLayout: Bool { dynamicTypeSize >= .xxxLarge }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(isActive ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(isActive ? Design.Colors.Dark.glow : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(
                    isActive ? Color.clear : Design.Colors.Dark.glassBorder,
                    lineWidth: 1
                )
        )
    }
}
