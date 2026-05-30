// HUDPill.swift
// HUD 数据胶囊组件 - 专业扫描软件风格

import SwiftUI

// MARK: - HUD Pill (单个数据胶囊)
struct HUDPill: View {
    let label: String
    let value: String
    var accentColor: Color = Design.Colors.harvest
    var showPulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Design.Typography.hudLabel)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(value)
                .font(Design.Typography.hudValue)
                .foregroundColor(accentColor)
                .overlay {
                    if showPulse {
                        PulseIndicator(color: accentColor)
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            Capsule()
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Pulse Indicator (脉冲动画)
struct PulseIndicator: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - HUD Bar (顶部状态栏)
struct HUDBar: View {
    let fps: Int
    let pointCount: Int
    let trackingState: String
    var gps: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            HUDPill(label: "FPS", value: "\(fps)", accentColor: Design.Colors.Dark.info)

            HUDPill(label: "PTS", value: formatNumber(pointCount), accentColor: Design.Colors.harvest)

            HUDPill(
                label: "TRK",
                value: trackingState,
                accentColor: trackingState == "OK" ? Design.Colors.Dark.success : Design.Colors.error
            )

            if let gps = gps {
                HUDPill(label: "GPS", value: gps, accentColor: Design.Colors.Dark.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - HUD Compact (紧凑版)
struct HUDCompact: View {
    let items: [(label: String, value: String, color: Color)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HUDPill(
                    label: items[index].label,
                    value: items[index].value,
                    accentColor: items[index].color
                )
            }
        }
    }
}

// MARK: - HUD Vertical (垂直布局)
struct HUDVertical: View {
    let label: String
    let value: String
    var accentColor: Color = Design.Colors.harvest
    var showPulse: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Design.Typography.hudLabel)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(value)
                .font(Design.Typography.hudValueLarge)
                .foregroundColor(accentColor)
                .overlay {
                    if showPulse {
                        PulseIndicator(color: accentColor)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.small)
                .fill(Design.Colors.Dark.hudBackground)
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
            Capsule()
                .fill(Design.Colors.Dark.hudBackground)
        )
    }
}

#Preview {
    ZStack {
        Design.Colors.Dark.bgDeep.ignoresSafeArea()

        VStack(spacing: 20) {
            // 单个胶囊
            HUDPill(label: "FPS", value: "60", accentColor: Design.Colors.Dark.info)

            // 紧凑版
            HUDCompact(items: [
                ("FPS", "60", Design.Colors.Dark.info),
                ("PTS", "12.5K", Design.Colors.harvest),
                ("TRK", "OK", Design.Colors.Dark.success)
            ])

            // 垂直布局
            HStack(spacing: 12) {
                HUDVertical(label: "点数", value: "12,450", accentColor: Design.Colors.harvest)
                HUDVertical(label: "精度", value: "0.01m", accentColor: Design.Colors.Dark.info)
            }

            // 状态指示器
            HStack(spacing: 12) {
                StatusIndicator(status: .ready)
                StatusIndicator(status: .recording)
                StatusIndicator(status: .processing)
            }
        }
        .padding()
    }
}
