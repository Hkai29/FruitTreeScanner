import SwiftUI

struct CrownVolumeResultSection: View {
    let result: YieldResult

    @ScaledMetric(relativeTo: .subheadline) private var noteFontSize: CGFloat = 13

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.crownVolumeMethod,
            icon: "tree.fill",
            color: Design.Colors.Workspace.accent
        ) {
            if let yA = result.yieldAKg {
                ResultInfoRow(label: L10n.Result.crownYield, value: ResultValueFormatter.kilograms(yA), highlight: true)
                ResultInfoRow(label: L10n.Result.crownVolume, value: ResultValueFormatter.cubicMeters(result.crownVolM3))
                ResultInfoRow(label: L10n.Result.treeHeight, value: ResultValueFormatter.meters(result.treeHeightM))
            } else if result.crownVolM3 > 0 || result.treeHeightM > 0 {
                ResultInfoRow(label: L10n.Result.crownVolume, value: ResultValueFormatter.cubicMeters(result.crownVolM3))
                ResultInfoRow(label: L10n.Result.treeHeight, value: ResultValueFormatter.meters(result.treeHeightM))
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Design.Colors.Workspace.secondary)
                    Text(L10n.Result.crownNotTrained)
                        .font(.system(size: noteFontSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Design.Colors.Workspace.secondary)
                    Text(L10n.Result.crownNotTrained)
                        .font(.system(size: noteFontSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }
}
