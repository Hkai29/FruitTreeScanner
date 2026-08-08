import SwiftUI

struct ScanPostCapturePanel: View {
    let pointCount: Int
    let coveragePercent: Int
    let completion: ScanCompletion
    let canFinish: Bool
    let onResume: () -> Void
    let onFinish: () -> Void

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

            HStack(spacing: 8) {
                Button(action: onResume) {
                    Label("继续补扫", systemImage: "plus.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Design.Colors.Dark.bgElevated.opacity(0.86))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: onFinish) {
                    Label(
                        canFinish ? "完成估算" : L10n.ScanExport.requirementsAction,
                        systemImage: canFinish ? "checkmark" : "info.circle"
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(canFinish ? .black.opacity(0.84) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(canFinish ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityHint(canFinish ? "" : L10n.ScanExport.requirementsHint)
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
    let onDismiss: () -> Void

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
                    Button(L10n.ScanReadiness.openSettings) {
                        onOpenSettings()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Design.Colors.harvest))
                }

                Button(L10n.ScanReadiness.back) {
                    onDismiss()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
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
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 300)
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
                .padding(.horizontal, 24)
                .padding(.bottom, 112)
        }
        .transition(.opacity)
    }
}
