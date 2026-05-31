// DataExportView.swift
// 数据导出界面

import SwiftUI

struct DataExportView: View {
    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var exportedFileURL: URL?
    @State private var exportTask: Task<Void, Never>?
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    private var scanRecords: [ScanFileRecord] {
        historyStore.scanFiles
    }

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
        .preferredColorScheme(.dark)
        .navigationTitle("数据导出")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportData()
                } label: {
                    Label(isExporting ? "导出中" : "导出", systemImage: isExporting ? "clock" : "square.and.arrow.up")
                }
                .disabled(scanRecords.isEmpty || isExporting)
            }
        }
        .onAppear {
            loadRecords()
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导出失败", isPresented: $showExportError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
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
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("导出批次")
                        .font(Design.Typography.darkHeadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text("按当前记录生成 \(settings.exportFormat) 文件")
                        .font(Design.Typography.darkCaption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }

                Spacer()

                Picker("格式", selection: $settings.exportFormat) {
                    ForEach(SettingsStore.exportFormatOptions, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .tint(Design.Colors.harvest)
            }

            HStack(spacing: Design.Space.lg) {
                statBox(value: "\(scanRecords.count)", label: "扫描记录")
                statBox(value: "\(totalFruits)", label: "果实总数")
                statBox(value: String(format: "%.1f", totalYield), label: "产量(kg)")
            }
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
    private func recordRow(_ record: ScanFileRecord) -> some View {
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
        historyStore.loadRecords()
    }

    // MARK: - 导出数据
    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        exportErrorMessage = ""

        let records = scanRecords
        let format = settings.exportFormat
        exportTask?.cancel()
        exportTask = Task.detached(priority: .utility) {
            do {
                let exportedURL = try Self.makeExportFile(records: records, format: format)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    exportedFileURL = exportedURL
                    showExportSheet = true
                    isExporting = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("❌ 导出失败: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                    isExporting = false
                }
            }
        }
    }

    private var totalFruits: Int {
        scanRecords.reduce(0) { $0 + $1.fruitCount }
    }

    private var totalYield: Float {
        scanRecords.reduce(0) { $0 + $1.yieldKg }
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        Self.displayDateFormatter.string(from: date)
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private func getTimeStr() -> String {
        Self.exportDateFormatter.string(from: Date())
    }

    nonisolated private static func makeExportFile(records: [ScanFileRecord], format: String) throws -> URL {
        let timestamp = exportTimestamp()
        let exportID = "\(timestamp)_\(UUID().uuidString.prefix(8))"
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans")

        switch format {
        case "PLY":
            let plyFiles = records
                .map(\.fileURL)
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            guard !plyFiles.isEmpty else {
                throw NSError(domain: "DataExport", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "没有找到 PLY 文件"])
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitScanner_Export_\(exportID)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try copyFiles(plyFiles, to: tempDir)
            return tempDir

        case "OBJ":
            let objFiles = (try? FileManager.default.contentsOfDirectory(
                at: scansDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ))?.filter { $0.pathExtension == "obj" } ?? []

            guard !objFiles.isEmpty else {
                throw NSError(domain: "DataExport", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "没有找到 OBJ 文件（需要先扫描生成网格）"])
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitScanner_Export_OBJ_\(exportID)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try copyFiles(objFiles, to: tempDir)
            return tempDir

        case "CSV":
            let metadataByRecord = loadMetadataByRecord(records)
            let csvContent = makeCSVContent(records: records, metadataByRecord: metadataByRecord)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitScanner_Export_\(exportID).csv")
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL

        case "JSON":
            let metadataByRecord = loadMetadataByRecord(records)
            let exportStruct = makeJSONExport(records: records, metadataByRecord: metadataByRecord)
            let jsonData = try JSONEncoder().encode(exportStruct)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitScanner_Export_\(exportID).json")
            try jsonData.write(to: tempURL)
            return tempURL

        default:
            throw NSError(domain: "DataExport", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "不支持的格式: \(format)"])
        }
    }

    nonisolated private static func copyFiles(_ files: [URL], to directory: URL) throws {
        for src in files {
            let destination = directory.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: src, to: destination)
        }
    }

    nonisolated private static func makeCSVContent(
        records: [ScanFileRecord],
        metadataByRecord: [String: [String: Any]]
    ) -> String {
        let hasParams = !metadataByRecord.isEmpty
        var rows: [[String]] = [[
            "树编号",
            "水果类型",
            "扫描日期",
            "果实数量",
            "产量(kg)",
            "GPS纬度",
            "GPS经度"
        ]]
        if hasParams {
            rows[0] += ["聚类Eps", "聚类MinPoints", "颜色过滤", "遮挡系数K", "点云大小", "置信度", "方法", "备注"]
        }

        for record in records {
            var row = [
                record.treeID,
                record.fruitType,
                displayDateString(record.scanDate),
                "\(record.fruitCount)",
                String(format: "%.2f", record.yieldKg),
                String(format: "%.6f", record.gpsLat),
                String(format: "%.6f", record.gpsLon)
            ]
            if hasParams {
                let p = metadataByRecord[record.id]
                row += [
                    String(format: "%.3f", numberValue(p?["clusterEps"])),
                    "\(p?["clusterMinPoints"] as? Int ?? 0)",
                    p?["colorFilterDesc"] as? String ?? "N/A",
                    String(format: "%.2f", numberValue(p?["occlusionK"], fallback: 1)),
                    "\(p?["pointCloudSize"] as? Int ?? 0)",
                    p?["confidence"] as? String ?? "low",
                    p?["methodUsed"] as? String ?? "",
                    p?["note"] as? String ?? ""
                ]
            }
            rows.append(row)
        }

        return rows.map(csvLine).joined()
    }

    nonisolated private static func makeJSONExport(
        records: [ScanFileRecord],
        metadataByRecord: [String: [String: Any]]
    ) -> ScanExport {
        ScanExport(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            totalTrees: records.count,
            totalFruits: records.reduce(0) { $0 + $1.fruitCount },
            totalYieldKg: records.reduce(0) { $0 + $1.yieldKg },
            records: records.map { record in
                let p = metadataByRecord[record.id]
                return RecordExport(
                    treeID: record.treeID,
                    fruitType: record.fruitType,
                    scanDate: ISO8601DateFormatter().string(from: record.scanDate),
                    fruitCount: record.fruitCount,
                    yieldKg: record.yieldKg,
                    gpsLat: record.gpsLat,
                    gpsLon: record.gpsLon,
                    clusterEps: numberValue(p?["clusterEps"]),
                    clusterMinPoints: p?["clusterMinPoints"] as? Int,
                    colorFilterDesc: p?["colorFilterDesc"] as? String,
                    occlusionK: numberValue(p?["occlusionK"], fallback: 1),
                    pointCloudSize: p?["pointCloudSize"] as? Int,
                    confidence: p?["confidence"] as? String,
                    methodUsed: p?["methodUsed"] as? String
                )
            }
        )
    }

    nonisolated private static func loadMetadataByRecord(_ records: [ScanFileRecord]) -> [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: records.compactMap { record in
            guard let metadataURL = metadataURL(for: record),
                  let data = try? Data(contentsOf: metadataURL),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return (record.id, dict)
        })
    }

    nonisolated private static func metadataURL(for record: ScanFileRecord) -> URL? {
        let fileURL = record.fileURL
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        return fileURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_result.json")
    }

    nonisolated private static func numberValue(_ value: Any?, fallback: Float = 0) -> Float {
        if let float = value as? Float { return float }
        if let double = value as? Double { return Float(double) }
        if let number = value as? NSNumber { return number.floatValue }
        return fallback
    }

    nonisolated private static func displayDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    nonisolated private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    nonisolated private static func csvLine(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    nonisolated private static func csvEscape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}

#Preview {
    NavigationView {
        DataExportView()
    }
}
