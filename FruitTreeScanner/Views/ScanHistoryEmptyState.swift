import SwiftUI

struct ScanHistoryEmptyState: View {
    let title: String
    let message: String
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "clock.arrow.circlepath",
                imageName: "FeatureScanHistory",
                title: title,
                message: message,
                accent: Design.Colors.harvest,
                primaryAction: action(
                    title: L10n.History.startScan,
                    icon: "viewfinder",
                    handler: onStartScan
                ),
                secondaryAction: action(
                    title: L10n.History.importPLY,
                    icon: "square.and.arrow.down",
                    handler: onImportFile
                )
            )

            Spacer()
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}
