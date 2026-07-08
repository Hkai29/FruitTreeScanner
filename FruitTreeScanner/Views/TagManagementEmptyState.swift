import SwiftUI

struct TagManagementEmptyState: View {
    let icon: String
    var imageName: String? = nil
    let title: String
    let message: String
    var primaryAction: DashboardSheetAction? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: icon,
                imageName: imageName,
                title: title,
                message: message,
                accent: Design.Colors.harvest,
                primaryAction: primaryAction,
                outerPadding: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
    }
}
