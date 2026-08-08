import SwiftUI

extension StartView {
    var canGoNext: Bool {
        switch currentStep {
        case 1: return isTreeIDValid
        default: return true
        }
    }

    var selectedPlot: Plot? {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }
    }

    var selectedTags: [GroupTag] {
        tagStore.tags.filter { selectedTagIds.contains($0.id) }
    }

    var stepHeader: StartFlowToolHeaderContent {
        switch currentStep {
        case 1:
            return StartFlowToolHeaderContent(
                imageName: "FeatureStartScan",
                title: L10n.StartSetup.text(.identifierTitle),
                subtitle: L10n.StartSetup.text(.identifierToolSubtitle),
                icon: "number",
                accent: Design.Colors.harvest
            )
        case 2:
            return StartFlowToolHeaderContent(
                imageName: "FeatureMap",
                title: L10n.StartSetup.text(.plotToolTitle),
                subtitle: L10n.StartSetup.text(.plotToolSubtitle),
                icon: "map.fill",
                accent: Design.Colors.forest
            )
        case 3:
            return StartFlowToolHeaderContent(
                imageName: "FeatureYieldReport",
                title: L10n.StartSetup.text(.seasonTitle),
                subtitle: L10n.StartSetup.text(.seasonToolSubtitle),
                icon: "chart.bar.fill",
                accent: Design.Colors.harvest
            )
        case 4:
            return StartFlowToolHeaderContent(
                imageName: "FeatureTagManagement",
                title: L10n.StartSetup.text(.tagsToolTitle),
                subtitle: L10n.StartSetup.text(.tagsToolSubtitle),
                icon: "tag.fill",
                accent: Design.Colors.forest
            )
        default:
            return StartFlowToolHeaderContent(
                imageName: "FeatureQuickScan",
                title: L10n.StartSetup.text(.confirmationToolTitle),
                subtitle: L10n.StartSetup.text(.confirmationToolSubtitle),
                icon: "viewfinder",
                accent: Design.Colors.harvest
            )
        }
    }
}
