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
            Design.Colors.bgBase
                .ignoresSafeArea()

            if scanRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
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
                .foregroundColor(Design.Colors.pebble)

            Text("暂无扫描记录")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.charcoal)

            Text("完成扫描后可以在这里导出数据")
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.slate)
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
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: Design.Space.xs) {
            Text(value)
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.forest)
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.slate)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 记录行
    private func recordRow(_ record: ScanRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("树 #\(record.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)

                Text(record.fruitType)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)

                Text(formatDate(record.scanDate))
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.slate)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(record.fruitCount) 个")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)

                Text(String(format: "%.2f kg", record.yieldKg))
                    .font(Design.Typography.monoSmall)
                    .foregroundColor(Design.Colors.forest)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
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
                let filename = url.deletingPathExtension().lastPathComponent
                let parts = filename.split(separator: "_")

                guard parts.count >= 5,
                      parts[parts.count - 2].hasPrefix("lat"),
                      parts[parts.count - 1].hasPrefix("lon") else { return nil }

                let treeID = parts[0..<parts.count - 4].joined(separator: "_")
                let latStr = parts[parts.count - 2].dropFirst(3)
                let lonStr = parts[parts.count - 1].dropFirst(3)
                let lat = Double(latStr) ?? 0
                let lon = Double(lonStr) ?? 0

                // Get creation date
                let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                // Estimate fruit count and yield from filename metadata
                // For now, create placeholder records (actual data would need PLY parsing)
                return ScanRecord(
                    id: UUID(),
                    treeID: treeID,
                    fruitType: "apple",
                    scanDate: creationDate,
                    fruitCount: 0,
                    yieldKg: 0,
                    gpsLat: lat,
                    gpsLon: lon
                )
            }
            .sorted { $0.scanDate > $1.scanDate }
    }

    // MARK: - 导出数据
    private func exportData() {
        isExporting = true

        do {
            // 生成 CSV 格式
            var csvContent = "树编号,水果类型,扫描日期,果实数量,产量(kg),GPS纬度,GPS经度\n"

            for record in scanRecords {
                csvContent += "\(record.treeID),\(record.fruitType),\(formatDate(record.scanDate)),"
                csvContent += "\(record.fruitCount),\(String(format: "%.2f", record.yieldKg)),"
                csvContent += "\(String(format: "%.6f", record.gpsLat)),\(String(format: "%.6f", record.gpsLon))\n"
            }

            // 保存到临时文件
            let filename = "FruitScanner_Export_\(getTimeStr()).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            exportedFileURL = tempURL
            showExportSheet = true
            isExporting = false
        } catch {
            print("❌ 导出失败: \(error.localizedDescription)")
            isExporting = false
        }
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
