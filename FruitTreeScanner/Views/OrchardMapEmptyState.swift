import SwiftUI

struct OrchardMapEmptyStatePresentation: Equatable {
    let title: String
    let message: String
    let startScanTitle: String

    init(bundle: Bundle = .main) {
        title = bundle.localizedString(
            forKey: "orchard_map.empty.title",
            value: "暂无定位扫描",
            table: nil
        )
        message = bundle.localizedString(
            forKey: "orchard_map.empty.message",
            value: "带 GPS 的完整扫描记录会显示在果园地图中，用于查看可靠产量分布。",
            table: nil
        )
        startScanTitle = bundle.localizedString(
            forKey: "orchard_map.empty.start_scan",
            value: "开始扫描",
            table: nil
        )
    }
}

struct OrchardMapEmptyState: View {
    private let onStartScan: (() -> Void)?
    private let presentation: OrchardMapEmptyStatePresentation

    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main) {
        self.onStartScan = onStartScan
        presentation = OrchardMapEmptyStatePresentation(bundle: bundle)
    }

    var body: some View {
        ScrollView {
            DashboardSheetEmptyState(
                icon: "map",
                imageName: "FeatureMap",
                title: presentation.title,
                message: presentation.message,
                accent: Design.Colors.Dark.info,
                primaryAction: action(
                    title: presentation.startScanTitle,
                    icon: "viewfinder",
                    handler: onStartScan
                ),
                outerPadding: false,
                adaptsForAccessibility: true
            )
            .padding(.horizontal, 16)
            .padding(.top, 84)
            .padding(.bottom, Design.Space.xxl)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
        .ignoresSafeArea()
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}
