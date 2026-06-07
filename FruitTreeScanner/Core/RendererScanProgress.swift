import Foundation

struct RendererScanProgress {
    private(set) var scanStartTime = Date()
    private var voxelDiscoveryHistory: [Int] = []
    private var lastVoxelCount = 0
    private var lastDiscoveryCheckTime = Date()
    private let discoveryCheckInterval: TimeInterval = 1.0

    var scanDuration: TimeInterval {
        Date().timeIntervalSince(scanStartTime)
    }

    var voxelDiscoveryRate: Float {
        guard !voxelDiscoveryHistory.isEmpty else { return 0 }
        let sum = voxelDiscoveryHistory.reduce(0, +)
        return Float(sum) / Float(voxelDiscoveryHistory.count)
    }

    var voxelDiscoveryTrend: VoxelDiscoveryTrend {
        guard voxelDiscoveryHistory.count >= 3 else { return .collecting }
        let recent = Array(voxelDiscoveryHistory.suffix(3))
        let avgRecent = Float(recent.reduce(0, +)) / Float(recent.count)
        if avgRecent < 5 { return .stable }

        if voxelDiscoveryHistory.count >= 6 {
            let previousWindow = Array(voxelDiscoveryHistory.dropLast(3).suffix(3))
            let avgPrevious = Float(previousWindow.reduce(0, +)) / Float(previousWindow.count)
            if avgRecent < avgPrevious * 0.75 { return .decreasing }
        }

        return .increasing
    }

    mutating func reset(now: Date = Date()) {
        scanStartTime = now
        voxelDiscoveryHistory.removeAll()
        lastVoxelCount = 0
        lastDiscoveryCheckTime = now
    }

    mutating func recordVoxelCount(_ voxelCount: Int, now: Date = Date()) {
        guard now.timeIntervalSince(lastDiscoveryCheckTime) >= discoveryCheckInterval else { return }

        let discovered = voxelCount - lastVoxelCount
        voxelDiscoveryHistory.append(discovered)

        if voxelDiscoveryHistory.count > 10 {
            voxelDiscoveryHistory.removeFirst()
        }

        lastVoxelCount = voxelCount
        lastDiscoveryCheckTime = now
    }
}
