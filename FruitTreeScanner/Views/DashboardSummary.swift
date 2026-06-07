import Foundation

struct DashboardDailySummary {
    let scanCount: Int
    let yieldKg: Float
    let treeCount: Int

    init(records: [ScanFileRecord], calendar: Calendar = .current) {
        var todaysScanCount = 0
        var todaysYield: Float = 0
        var treeIDs = Set<String>()

        for record in records where calendar.isDateInToday(record.scanDate) {
            todaysScanCount += 1
            todaysYield += record.yieldKg
            treeIDs.insert(record.treeID)
        }

        scanCount = todaysScanCount
        yieldKg = todaysYield
        treeCount = treeIDs.count
    }
}
