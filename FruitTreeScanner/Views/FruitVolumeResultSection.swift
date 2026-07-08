import SwiftUI

struct FruitVolumeResultSection: View {
    let result: YieldResult

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.fruitVolumeMethod,
            icon: "circle.grid.3x3",
            color: Design.Colors.forest
        ) {
            ResultInfoRow(label: L10n.Result.correctedFruitCount, value: "\(result.nLidar) \(L10n.Result.unit)")
            if let nV = result.nVisual {
                ResultInfoRow(label: L10n.Result.visualCount, value: "\(nV) \(L10n.Result.unit)")
            }
            ResultInfoRow(label: L10n.Result.correctionFactor, value: ResultValueFormatter.correctionFactor(result.correctionK))
            ResultInfoRow(label: L10n.Result.visibleWeight, value: ResultValueFormatter.kilograms(result.yieldBVisibleKg))
            ResultInfoRow(label: L10n.Result.correctedWeight, value: ResultValueFormatter.kilograms(result.yieldBCorrectedKg), highlight: true)
            if result.meanDiameterCm > 0 {
                ResultInfoRow(label: L10n.Result.measuredDiameter, value: ResultValueFormatter.centimeters(result.meanDiameterCm))
            }
        }
    }
}
