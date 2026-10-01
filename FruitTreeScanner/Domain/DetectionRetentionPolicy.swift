import Foundation

enum DetectionRetentionPolicy {
    /// Bound live evidence by the existing capture-timestamp frame window.
    /// Stable archived evidence is retained separately.
    static let defaultMaxFrameCount = 360

    static func trimmedByFrameLimit(
        observations: [Observation],
        maxFrameCount: Int = defaultMaxFrameCount
    ) -> [Observation] {
        trimmedByFrameLimit(observations, timestamp: \.timestamp, maxFrameCount: maxFrameCount)
    }

    static func trimmedByFrameLimit<Element>(
        _ elements: [Element],
        timestamp: KeyPath<Element, TimeInterval>,
        maxFrameCount: Int
    ) -> [Element] {
        guard maxFrameCount > 0 else { return [] }
        let frameTimestamps = Array(Set(elements.map { $0[keyPath: timestamp] })).sorted()
        guard frameTimestamps.count > maxFrameCount else { return elements }

        let retainedTimestamps = Set(frameTimestamps.suffix(maxFrameCount))
        return elements.filter { retainedTimestamps.contains($0[keyPath: timestamp]) }
    }
}
