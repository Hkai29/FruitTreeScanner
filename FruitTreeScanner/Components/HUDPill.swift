// HUDPill.swift
// 采集 HUD 数据胶囊。深色画布上的读数，标签小字、数值等宽。

import SwiftUI

// MARK: - HUD Pill (单个数据胶囊)
struct HUDPill: View {
    let label: String
    let value: String
    var accentColor: Color = Design.Colors.Dark.glow
    var labelSize: CGFloat = 10
    var valueSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(Design.Colors.Dark.textMuted)

            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Status Indicator (状态指示器)
struct StatusIndicator: View {
    enum Status {
        case ready, recording, processing, error
    }

    let status: Status
    var iconSize: CGFloat = 10
    var labelSize: CGFloat = 12

    private var color: Color {
        switch status {
        case .ready: return Design.Colors.Dark.success
        case .recording: return Design.Colors.Dark.error
        case .processing: return Design.Colors.Dark.glow
        case .error: return Design.Colors.Dark.error
        }
    }

    private var label: String {
        switch status {
        case .ready: return L10n.ScanHUD.ready
        case .recording: return L10n.ScanHUD.recording
        case .processing: return L10n.ScanHUD.processing
        case .error: return L10n.ScanHUD.error
        }
    }

    private var icon: String {
        switch status {
        case .ready: return "circle.fill"
        case .recording: return "record.circle"
        case .processing: return "gearshape.2"
        case .error: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(color)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: labelSize, weight: .regular))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 0.5)
        )
    }
}
