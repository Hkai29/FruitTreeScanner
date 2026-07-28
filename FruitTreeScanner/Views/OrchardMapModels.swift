import SwiftUI
import MapKit

struct OrchardMapData {
    let trees: [TreeAnnotation]

    init(records: [ScanFileRecord]) {
        trees = records
            .filter {
                $0.persistenceState == .complete &&
                    $0.gpsLat != 0 &&
                    $0.gpsLon != 0
            }
            .map(TreeAnnotation.init(record:))
    }
}

struct TreeAnnotation: Identifiable, Hashable {
    let id: String
    let treeID: String
    let coordinate: CLLocationCoordinate2D
    let weight: Double
    let confidence: String
    let scanDate: Date
    let fruitCount: Int

    init(
        id: String,
        treeID: String,
        coordinate: CLLocationCoordinate2D,
        weight: Double,
        confidence: String,
        scanDate: Date,
        fruitCount: Int
    ) {
        self.id = id
        self.treeID = treeID
        self.coordinate = coordinate
        self.weight = weight
        self.confidence = confidence
        self.scanDate = scanDate
        self.fruitCount = fruitCount
    }

    init(record: ScanFileRecord) {
        self.init(
            id: record.id,
            treeID: record.treeID,
            coordinate: CLLocationCoordinate2D(latitude: record.gpsLat, longitude: record.gpsLon),
            weight: Double(record.yieldKg),
            confidence: record.confidence,
            scanDate: record.scanDate,
            fruitCount: record.fruitCount
        )
    }

    var yieldLevel: YieldLevel {
        if weight > 45 { return .high }
        if weight >= 35 { return .medium }
        return .low
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TreeAnnotation, rhs: TreeAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

enum YieldLevel: CaseIterable {
    case high
    case medium
    case low

    var color: Color {
        switch self {
        case .high: return Design.Colors.Dark.success
        case .medium: return Design.Colors.Dark.warning
        case .low: return Design.Colors.Dark.error
        }
    }

    var label: String {
        switch self {
        case .high: return "高产"
        case .medium: return "中产"
        case .low: return "低产"
        }
    }

    var icon: String {
        switch self {
        case .high: return "arrow.up.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle.fill"
        }
    }
}

struct TreeYieldSummary {
    let totalCount: Int
    private let countsByLevel: [YieldLevel: Int]

    init(trees: [TreeAnnotation]) {
        var counts = Dictionary(uniqueKeysWithValues: YieldLevel.allCases.map { ($0, 0) })
        for tree in trees {
            counts[tree.yieldLevel, default: 0] += 1
        }
        totalCount = trees.count
        countsByLevel = counts
    }

    func count(for level: YieldLevel) -> Int {
        countsByLevel[level, default: 0]
    }
}

enum OrchardMapRegionCalculator {
    static func region(for trees: [TreeAnnotation]) -> MKCoordinateRegion? {
        guard let firstTree = trees.first else { return nil }

        let latValues = trees.map { $0.coordinate.latitude }
        let lonValues = trees.map { $0.coordinate.longitude }

        let minLat = latValues.min() ?? firstTree.coordinate.latitude
        let maxLat = latValues.max() ?? firstTree.coordinate.latitude
        let minLon = lonValues.min() ?? firstTree.coordinate.longitude
        let maxLon = lonValues.max() ?? firstTree.coordinate.longitude

        let latDelta = max((maxLat - minLat) * 1.5, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.005)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
