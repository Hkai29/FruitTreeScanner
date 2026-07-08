import SwiftUI

struct DashboardPrimaryActions: View {
    let onStartScan: () -> Void
    let onQuickScan: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStartScan) {
                Label("新建扫描", systemImage: "viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.Colors.harvest)

            Button(action: onQuickScan) {
                Label("快速采集", systemImage: "bolt")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(Design.Colors.Dark.textPrimary)
        }
    }
}
