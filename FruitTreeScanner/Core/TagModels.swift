import Foundation

struct Plot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var displayOrder: Int
    var createdAt: Date

    init(name: String, colorHex: String = TagPalette.defaultPlotColor, displayOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.displayOrder = displayOrder
        self.createdAt = Date()
    }
}

struct GroupTag: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(name: String, colorHex: String = TagPalette.defaultTagColor) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

enum TagPalette {
    static let defaultPlotColor = "#4D7588"
    static let defaultTagColor = "#6F8F63"
}

enum ScanStatus: String, Codable, CaseIterable, Sendable {
    case notScanned = "未扫描"
    case scanned = "已扫描"
    case reviewing = "复查中"
    case completed = "已完成"
}

struct TreeAssignment: Identifiable, Codable, Equatable, Sendable {
    var id: String { treeId }
    let treeId: String
    var plotId: UUID?
    var tagIds: [UUID]
    var status: ScanStatus

    init(treeId: String, plotId: UUID? = nil, tagIds: [UUID] = [], status: ScanStatus = .notScanned) {
        self.treeId = treeId
        self.plotId = plotId
        self.tagIds = tagIds
        self.status = status
    }
}
