import SwiftUI

struct OrchardMapEmptyState: View {
    @Environment(\.orchardMapPresentation) private var presentation
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "map",
                imageName: "FeatureMap",
                title: presentation.emptyTitle,
                message: presentation.emptyMessage,
                accent: Design.Colors.Dark.info,
                primaryAction: action(
                    title: presentation.startScan,
                    icon: "viewfinder",
                    handler: onStartScan
                ),
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
