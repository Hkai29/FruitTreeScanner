import SwiftUI

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
