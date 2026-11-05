import SwiftUI

extension StartView {
    var canGoNext: Bool {
        switch currentStep {
        case 1: return treeIdentifierDraft.validatedValue != nil
        default: return true
        }
    }

    var resolvedSelection: StartScanSelectionSnapshot {
        StartScanSelectionPolicy.snapshot(
            selectedPlotId: selectedPlotId,
            selectedTagIds: selectedTagIds,
            availablePlots: tagStore.plots,
            availableTags: tagStore.tags
        )
    }

    var selectedPlot: Plot? {
        resolvedSelection.plotId.flatMap { tagStore.getPlot(id: $0) }
    }

    var selectedTags: [GroupTag] {
        let resolvedTagIDs = Set(resolvedSelection.tagIds)
        return tagStore.tags.filter { resolvedTagIDs.contains($0.id) }
    }

    /// 果园里已经归档过的编号，供第 1 步直接沿用。
    var existingTreeIDs: [String] {
        Array(Set(tagStore.assignments.map(\.treeId)))
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// 每个地块已归档的树木数量。
    var plotTreeCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for plot in tagStore.plots {
            counts[plot.id] = tagStore.treeCount(forPlotId: plot.id)
        }
        return counts
    }

    var stepHeader: StartFlowToolHeaderContent {
        switch currentStep {
        case 1:
            return StartFlowToolHeaderContent(
                imageName: "FeatureStartScan",
                title: L10n.StartSetup.text(.identifierTitle),
                subtitle: L10n.StartSetup.text(.identifierToolSubtitle),
                icon: "number",
                accent: Design.Colors.Workspace.accent
            )
        case 2:
            return StartFlowToolHeaderContent(
                imageName: "FeatureMap",
                title: L10n.StartSetup.text(.plotToolTitle),
                subtitle: L10n.StartSetup.text(.plotToolSubtitle),
                icon: "map.fill",
                accent: Design.Colors.Workspace.accent
            )
        case 3:
            return StartFlowToolHeaderContent(
                imageName: "FeatureYieldReport",
                title: L10n.StartSetup.text(.seasonTitle),
                subtitle: L10n.StartSetup.text(.seasonToolSubtitle),
                icon: "chart.bar.fill",
                accent: Design.Colors.Workspace.accent
            )
        case 4:
            return StartFlowToolHeaderContent(
                imageName: "FeatureTagManagement",
                title: L10n.StartSetup.text(.tagsToolTitle),
                subtitle: L10n.StartSetup.text(.tagsToolSubtitle),
                icon: "tag.fill",
                accent: Design.Colors.Workspace.accent
            )
        default:
            return StartFlowToolHeaderContent(
                imageName: "FeatureQuickScan",
                title: L10n.StartSetup.text(.confirmationToolTitle),
                subtitle: L10n.StartSetup.text(.confirmationToolSubtitle),
                icon: "viewfinder",
                accent: Design.Colors.Workspace.accent
            )
        }
    }
}
