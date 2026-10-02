import Foundation

/// Recent scans and original calibration baselines share one root repository.
struct CalibrationScanSource: Sendable {
    let historyStore: ScanHistoryStore
    let loadBaseline: @Sendable (ScanFileRecord) -> CalibrationScanBaseline?

    @MainActor
    static func production(
        repository: ScanRepository,
        historyStore: ScanHistoryStore
    ) -> CalibrationScanSource {
        CalibrationScanSource(
            historyStore: historyStore,
            loadBaseline: { record in try? repository.readCalibrationBaseline(for: record) }
        )
    }
}
