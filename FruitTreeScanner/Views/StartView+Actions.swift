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
        guard canGoNext, !isLaunchingScan else { return }

        if currentStep < totalSteps {
            if currentStep == 1, let normalizedTreeID = treeIdentifierDraft.validatedValue {
                treeIdentifierDraft.value = normalizedTreeID
            }
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
                guard let treeID = treeIdentifierDraft.validatedValue else { return nil }
                return ScanLaunchRequest(
                    treeID: treeID,
                    selectedFruitCategory: selectedFruitCategory,
                    season: season,
                    gps: gps,
                    plotId: selectedPlotId,
                    tagIds: Array(selectedTagIds)
                )
            },
            deliver: { request in
                SettingsStore.shared.fruitType = selectedFruitCategory.rawValue
                onLaunchScan(request)
            }
        )
    }
}
