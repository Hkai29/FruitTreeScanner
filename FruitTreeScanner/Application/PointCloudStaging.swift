import Foundation

struct FrozenPointCloudExport: Sendable {
    let pointCloud: FinalPointCloud
    /// Nil is supported only by the legacy Renderer async facade.
    let captureIdentity: ScanCaptureIdentity?
    let fallbackFolder: String
}

struct PointCloudStageInput: Sendable {
    let frozen: FrozenPointCloudExport
    let treeID: String
    let latitude: Double
    let longitude: Double
}

struct StagedPointCloud: Sendable {
    let draft: DraftScan
    let pointCloud: FinalPointCloud
}

enum PointCloudExportError: Error {
    case rendererUnavailable
    case gpuDrainTimedOut
    case gpuWriteFailed
    case captureChanged
    case emptyPointCloud
}

/// The only file orchestration for a frozen export. The worker owns values,
/// never a Renderer or mutable capture settings.
enum PointCloudStaging {
    static func stage(_ input: PointCloudStageInput,
                      repository: ScanRepository) async throws -> StagedPointCloud {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let scanDate = getTimeStr()
            let filename = makeTreeFileName(treeID: input.treeID, lat: input.latitude, lon: input.longitude)
            let destination = try repository.pointCloudDestination(
                filename: filename, fallbackFolder: input.frozen.fallbackFolder
            )
            try Task.checkCancellation()
            let draft = try repository.stagePointCloud(to: destination,
                                                      captureIdentity: input.frozen.captureIdentity) {
                try PLYPointCloudWriter.write(
                    points: input.frozen.pointCloud.points, treeID: input.treeID, scanDate: scanDate,
                    gpsLat: input.latitude, gpsLon: input.longitude, to: destination
                )
            }
            // Publication transfers a receipt even if cancellation raced with it.
            // Only the finalization owner may settle this published draft.
            return StagedPointCloud(draft: draft, pointCloud: input.frozen.pointCloud)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
