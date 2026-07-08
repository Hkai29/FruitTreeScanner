import SwiftUI

struct OrchardMapEmptyState: View {
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "map",
                imageName: "FeatureMap",
                title: "暂无定位扫描",
                message: "带 GPS 的扫描记录会显示在果园地图中，用于查看产量分布。",
                accent: Design.Colors.Dark.info,
                primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
                outerPadding: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 84)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
        .ignoresSafeArea()
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}
