import SwiftUI
import UIKit

extension StartView {
    func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep > 1 {
                currentStep -= 1
            }
        }
    }

    func goNext() {
        if currentStep < totalSteps {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        } else {
            launchScan()
        }
    }

    func launchScan() {
        guard !launchGate.isSubmitting else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        launchGate.submit(
            makeRequest: { () -> ScanLaunchRequest? in
                let normalizedTreeID = TreeIdentifierPolicy.normalized(treeID)
                guard TreeIdentifierPolicy.isValid(normalizedTreeID) else {
                    return nil
                }
                let selection = resolvedSelection
                return ScanLaunchRequest(
                    treeID: normalizedTreeID,
                    selectedFruitCategory: selectedFruitCategory,
                    season: season,
                    gps: gps,
                    plotId: selection.plotId,
                    tagIds: selection.tagIds
                )
            },
            deliver: { request in
                SettingsStore.shared.fruitType = selectedFruitCategory.rawValue
                onLaunchScan(request)
            }
        )
    }

    func normalizeClassificationSelection() {
        let selection = resolvedSelection
        if selectedPlotId != selection.plotId {
            selectedPlotId = selection.plotId
        }
        let normalizedTagIDs = Set(selection.tagIds)
        if selectedTagIds != normalizedTagIDs {
            selectedTagIds = normalizedTagIDs
        }
    }
}
