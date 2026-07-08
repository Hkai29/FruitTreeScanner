import SwiftUI

struct ResultActionButtons: View {
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.Result.continueNext)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Design.Colors.Dark.bgDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Design.Colors.harvest)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button(action: onDismissToHome) {
                HStack(spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(size: 14))
                    Text(L10n.Result.backToHome)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Design.Colors.Dark.bgElevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
    }
}
