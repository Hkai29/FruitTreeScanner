import SwiftUI

struct ImportHeader: View {
    var body: some View {
        DashboardToolHeader(
            imageName: "FeatureImportFile",
            title: L10n.Import.headerTitle,
            subtitle: L10n.Import.headerSubtitle,
            icon: "square.and.arrow.down",
            accent: Design.Colors.Dark.info
        )
    }
}

struct ImportStatusPanel: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Design.Colors.harvest
    var showsProgress: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                if showsProgress {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10)
    }
}

struct ImportRulesList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImportRuleRow(icon: "clock.arrow.circlepath", text: L10n.Import.historyRule)
            ImportRuleRow(icon: "doc.badge.gearshape", text: L10n.Import.metadataRule)
            ImportRuleRow(icon: "square.on.square", text: L10n.Import.duplicateRule)
        }
        .padding(14)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private struct ImportRuleRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.info)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer(minLength: 0)
        }
    }
}
