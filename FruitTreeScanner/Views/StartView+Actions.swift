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
        guard !isLaunchingScan else { return }
        isLaunchingScan = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let normalizedTreeID = TreeIdentifierPolicy.normalized(treeID)
            guard TreeIdentifierPolicy.isValid(normalizedTreeID) else {
                isLaunchingScan = false
                return
            }
            let request = ScanLaunchRequest(
                treeID: normalizedTreeID,
                season: season,
                gps: gps,
                plotId: selectedPlotId,
                tagIds: Array(selectedTagIds)
            )

            onLaunchScan(request)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isLaunchingScan = false
        }
    }
}
