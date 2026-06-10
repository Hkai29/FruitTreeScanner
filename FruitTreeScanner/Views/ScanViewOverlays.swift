import SwiftUI

struct ScanFieldGuideOverlay: View {
    let onClose: () -> Void

    private let tips: [(icon: String, title: String, message: String)] = [
        ("figure.walk.motion", "慢速环绕", "从树干开始，绕树一圈；每一步都让树冠和主枝保持在画面中。"),
        ("scope", "先大后小", "先拿到整棵树的轮廓，再补果实密集区和背光枝条，避免一开始贴太近。"),
        ("square.3.layers.3d", "补齐盲区", "覆盖率到 60% 后重点看树冠背面、下层枝条和主干遮挡处。"),
        ("ruler", "可先测量", "停止后不用立刻分析，可以先用测量确认树高、冠幅或样方距离。")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("果树 LiDAR 扫描")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("目标是稳定覆盖树干、树冠和果实区域；红色停止键前，先让点云绕树闭合。")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    ForEach(tips, id: \.title) { tip in
                        ScanFieldGuideTipRow(icon: tip.icon, title: tip.title, message: tip.message)
                    }
                }

                HStack(spacing: 10) {
                    Label("默认模式", systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Design.Colors.harvest.opacity(0.14))
                        .clipShape(Capsule())

                    Text("果树全株扫描")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))

                    Spacer()
                }

                Button(action: onClose) {
                    Text("开始扫描")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Design.Colors.harvest)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                    .fill(Design.Colors.Dark.hudBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }
}

private struct ScanFieldGuideTipRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 26, height: 26)
                .background(Design.Colors.harvest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct ScanPostCapturePanel: View {
    let pointCount: Int
    let coveragePercent: Int
    let completion: ScanCompletion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)

                VStack(alignment: .leading, spacing: 2) {
                    Text("粗预览已就绪")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(nextStepText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.68))
                }

                Spacer()

                Text("\(coveragePercent)%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
            }

            HStack(spacing: 8) {
                ScanPostCaptureMetric(label: "点云", value: ScanHUDValueFormatter.pointCount(pointCount))
                ScanPostCaptureMetric(label: "时长", value: completion.formattedDuration)
                ScanPostCaptureMetric(label: "状态", value: completion.statusTitle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.Colors.Dark.hudBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.horizontal, Design.Space.lg)
        .padding(.bottom, Design.Space.sm)
    }

    private var nextStepText: String {
        if completion.overall >= 0.85 {
            return "覆盖充足，可直接完成并估算产量。"
        }
        if completion.overall >= 0.6 {
            return "可完成分析；若树冠背面缺失，继续录制补一圈。"
        }
        return "建议继续录制，补齐树冠背面和主干遮挡区域。"
    }

    private var statusColor: Color {
        if completion.overall >= 0.85 { return Design.Colors.harvest }
        if completion.overall >= 0.6 { return Design.Colors.success }
        return Design.Colors.warning
    }
}

private struct ScanPostCaptureMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScanCoverageCompleteToast: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Design.Colors.forest)
                    Text("扫描覆盖充足")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("可以点击完成保存结果")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(Design.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                        .fill(Design.Colors.Dark.hudBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                Spacer()
            }
            .padding(.bottom, 120)
        }
        .transition(.opacity)
    }
}

struct ScanReadinessOverlay: View {
    let scanReadiness: ScanReadiness
    let onOpenSettings: () -> Void

    var body: some View {
        if scanReadiness.blocksScanning {
            VStack(spacing: 14) {
                ProgressView()
                    .opacity(scanReadiness == .checking ? 1 : 0)

                Text(scanReadiness.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text(scanReadiness.message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if scanReadiness == .cameraDenied {
                    Button("打开设置") {
                        onOpenSettings()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Design.Colors.harvest))
                }
            }
            .padding(18)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .fill(Design.Colors.Dark.hudBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}

struct ScanNoticeToast: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Design.Colors.Dark.hudBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                .padding(.bottom, 112)
        }
        .transition(.opacity)
    }
}
