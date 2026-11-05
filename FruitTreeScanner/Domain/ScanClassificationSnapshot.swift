import Foundation

/// Classification accepted when the scan launches, independent of later catalog edits.
struct ScanClassificationSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let id: UUID
        let name: String
    }

    let plot: Item?
    let tags: [Item]

    static let empty = ScanClassificationSnapshot(plot: nil, tags: [])
}
