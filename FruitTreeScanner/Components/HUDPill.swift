// HUDPill.swift
// HUD 数据胶囊组件 - 专业扫描软件风格

import SwiftUI

// MARK: - HUD Pill (单个数据胶囊)
struct HUDPill: View {
    let label: String
    let value: String
    var accentColor: Color = Design.Colors.harvest

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Design.Typography.hudLabel)
                .foregroundColor(Design.Colors.Dark.textMuted)

            Text(value)
                .font(Design.Typography.hudValue)
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
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

    private var color: Color {
        switch status {
        case .ready: return Design.Colors.forest
        case .recording: return Design.Colors.apple
        case .processing: return Design.Colors.harvest
        case .error: return Design.Colors.error
        }
    }

    private var label: String {
        switch status {
        case .ready: return "就绪"
        case .recording: return "采集中"
        case .processing: return "处理中"
        case .error: return "错误"
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
                .font(.system(size: 10))
                .foregroundColor(color)

            Text(label)
                .font(Design.Typography.darkCaption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 0.5)
        )
    }
}
