import SwiftUI

struct ScanRenderLayer: View {
    let scanReadiness: ScanReadiness
    let coordinator: ScanCoordinator
    @ObservedObject var qualityMonitor: ScanQualityMonitor

    var body: some View {
        if scanReadiness == .ready {
            MetalView(coordinator: coordinator)
                .ignoresSafeArea()
                .onAppear(perform: bindQualityMonitor)
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private func bindQualityMonitor() {
        coordinator.onQualitySampleUpdate = { sample in
            DispatchQueue.main.async {
                qualityMonitor.update(with: sample)
            }
        }
    }
}
