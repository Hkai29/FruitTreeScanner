// DataExportView.swift
// 数据导出界面

import SwiftUI

struct DataExportView: View {
    @State private var scanRecords: [ScanRecord] = []
    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?
    @ObservedObject var historyStore = ScanHistoryStore.shared

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if scanRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .overlay(FingerGlowOverlay())
        .preferredColorScheme(.dark)
        .navigationTitle("数据导出")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportData()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                }
                .disabled(scanRecords.isEmpty || isExporting)
            }
        }
        .onAppear {
            loadRecords()
        }
        .onReceive(NotificationCenter.default.publisher(for: ScanHistoryStore.didUpdateNotification)) { _ in
            loadRecords()
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 空状态
    private var emptyState: some View {
        VStack(spacing: Design.Space.lg) {
            Image(systemName: "doc.text")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text("暂无扫描记录")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text("完成扫描后可以在这里导出数据")
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    // MARK: - 记录列表
    private var recordsList: some View {
        ScrollView {
            VStack(spacing: Design.Space.md) {
                // 导出统计
                exportStats

                // 记录列表
                ForEach(scanRecords) { record in
                    recordRow(record)
                }
            }
            .padding(Design.Space.lg)
        }
    }

    // MARK: - 导出统计
    private var exportStats: some View {
        HStack(spacing: Design.Space.lg) {
            statBox(value: "\(scanRecords.count)", label: "扫描记录")
            statBox(value: "\(totalFruits)", label: "果实总数")
            statBox(value: String(format: "%.1f", totalYield), label: "产量(kg)")
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: Design.Space.xs) {
            Text(value)
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.Dark.glow)
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 记录行
    private func recordRow(_ record: ScanRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("树 #\(record.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(record.fruitType)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text(formatDate(record.scanDate))
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(record.fruitCount) 个")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(String(format: "%.2f kg", record.yieldKg))
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.Dark.glow)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.medium)
    }

    // MARK: - 加载记录
    private func loadRecords() {
        // Load from scans directory (same source as ScanHistoryView)
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            scanRecords = []
            return
        }

        // Parse PLY files to create scan records
        // Filename format: \(treeID)_\(yyyyMMdd)_\(HHmmss)_lat\(lat)_lon\(lon).ply
        scanRecords = files
            .filter { $0.pathExtension == "ply" }
            .compactMap { url -> ScanRecord? in
                guard let result = PLYParserHelper.parsePLYFile(at: url) else { return nil }
                return ScanRecord(
                    id: UUID(),
                    treeID: result.treeID,
                    fruitType: result.fruitType,
                    scanDate: result.scanDate,
                    fruitCount: result.fruitCount,
                    yieldKg: result.yieldKg,
                    gpsLat: result.gpsLat,
                    gpsLon: result.gpsLon
                )
            }
            .sorted { $0.scanDate > $1.scanDate }
    }

    // MARK: - 导出数据
    private func exportData() {
        isExporting = true

        do {
            let format = SettingsStore.shared.exportFormat
            let timestamp = getTimeStr()
            let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("scans")

            switch format {
            case "PLY":
                // 收集所有 PLY 文件打包导出
                let plyFiles = scanRecords.compactMap { record -> URL? in
                    let filename = makeTreeFileName(
                        treeID: record.treeID,
                        date: record.scanDate,
                        lat: record.gpsLat,
                        lon: record.gpsLon,
                        ext: "ply"
                    )
                    return scansDir.appendingPathComponent(filename)
                }.filter { FileManager.default.fileExists(atPath: $0.path) }

                if plyFiles.isEmpty {
                    throw NSError(domain: "DataExport", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "没有找到 PLY 文件"])
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FruitScanner_Export_\(timestamp)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                for src in plyFiles {
                    try FileManager.default.copyItem(at: src,
                        to: tempDir.appendingPathComponent(src.lastPathComponent))
                }
                exportedFileURL = tempDir

            case "CSV":
                var csvContent = "树编号,水果类型,扫描日期,果实数量,产量(kg),GPS纬度,GPS经度\n"
                for record in scanRecords {
                    csvContent += "\(record.treeID),\(record.fruitType),\(formatDate(record.scanDate)),"
                    csvContent += "\(record.fruitCount),\(String(format: "%.2f", record.yieldKg)),"
                    csvContent += "\(String(format: "%.6f", record.gpsLat)),\(String(format: "%.6f", record.gpsLon))\n"
                }
                let filename = "FruitScanner_Export_\(timestamp).csv"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
                exportedFileURL = tempURL

            case "JSON":
                let exportStruct = ScanExport(
                    exportDate: ISO8601DateFormatter().string(from: Date()),
                    totalTrees: scanRecords.count,
                    totalFruits: scanRecords.reduce(0) { $0 + $1.fruitCount },
                    totalYieldKg: scanRecords.reduce(0) { $0 + $1.yieldKg },
                    records: scanRecords.map { record in
                        RecordExport(
                            treeID: record.treeID,
                            fruitType: record.fruitType,
                            scanDate: ISO8601DateFormatter().string(from: record.scanDate),
                            fruitCount: record.fruitCount,
                            yieldKg: record.yieldKg,
                            gpsLat: record.gpsLat,
                            gpsLon: record.gpsLon
                        )
                    }
                )
                let jsonData = try JSONEncoder().encode(exportStruct)
                let filename = "FruitScanner_Export_\(timestamp).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try jsonData.write(to: tempURL)
                exportedFileURL = tempURL

            default:
                throw NSError(domain: "DataExport", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "不支持的格式: \(format)"])
            }

            showExportSheet = true
            isExporting = false
        } catch {
            #if DEBUG
            print("❌ 导出失败: \(error.localizedDescription)")
            #endif
            isExporting = false
        }
    }

    private func makeTreeFileName(treeID: String, date: Date, lat: Double, lon: Double, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timeStr = formatter.string(from: date)
        let latStr = String(format: "%.4f", abs(lat))
        let lonStr = String(format: "%.4f", abs(lon))
        return "\(treeID)_\(timeStr)_lat\(latStr)_lon\(lonStr).\(ext)"
    }

    private var totalFruits: Int {
        scanRecords.reduce(0) { $0 + $1.fruitCount }
    }

    private var totalYield: Float {
        scanRecords.reduce(0) { $0 + $1.yieldKg }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func getTimeStr() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - 导出模型
struct RecordExport: Codable {
    let treeID: String
    let fruitType: String
    let scanDate: String
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
}

struct ScanExport: Codable {
    let exportDate: String
    let totalTrees: Int
    let totalFruits: Int
    let totalYieldKg: Float
    let records: [RecordExport]
}

// MARK: - 扫描记录
struct ScanRecord: Identifiable {
    let id: UUID
    let treeID: String
    let fruitType: String
    let scanDate: Date
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
}

#Preview {
    NavigationView {
        DataExportView()
    }
}
