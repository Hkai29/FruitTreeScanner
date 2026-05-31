// DashboardView.swift
// 全新主界面 - 自然有机风格

import SwiftUI

struct DashboardView: View {
    @State private var selectedMode: AppMode = .scan
    @State private var showSettings = false
    @State private var showStartView = false
    @State private var showQuickScan = false
    @State private var showCalibration = false
    @State private var showScanHistory = false
    @State private var showPointCloud = false
    @State private var showTagManagement = false
    @State private var showYieldReport = false
    @State private var showCompare = false
    @State private var showTrends = false
    @State private var showMapView = false
    @State private var showImportFile = false
    @State private var showBatchExport = false
    @State private var selectedPointCloudURL: URL?
    @State private var pendingScanRequest: ScanLaunchRequest?
    @State private var activeScanRequest: ScanLaunchRequest?
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recentScans: [ScanFileRecord] {
        Array(historyStore.scanFiles.prefix(3))
    }

    var body: some View {
        ZStack {
            // 暗色渐变背景
            Design.Colors.darkGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopNavigationBar(
                    showSettings: $showSettings,
                    onHistoryTap: { showScanHistory = true },
                    historyCount: historyStore.scanFiles.count
                )
                .background(Design.Colors.Dark.bgSurface)

                ScrollView {
                    VStack(spacing: 32) {
                        HeroSection()
                        ModeSelector(selectedMode: $selectedMode)
                        QuickActionsGrid(mode: selectedMode, onAction: handleQuickAction)
                        RecentScansSection(
                            scans: recentScans,
                            onViewAll: { showScanHistory = true },
                            onScanTap: openPointCloud
                        )
                        StatsOverviewSection(records: historyStore.scanFiles)
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showStartView, onDismiss: presentPendingScanIfNeeded) {
            StartView { request in
                pendingScanRequest = request
                showStartView = false
            }
        }
        .fullScreenCover(isPresented: $showQuickScan, onDismiss: presentPendingScanIfNeeded) {
            QuickScanView { request in
                pendingScanRequest = request
                showQuickScan = false
            }
        }
        .fullScreenCover(item: $activeScanRequest, onDismiss: refreshScanHistory) { request in
            ScanView(
                treeID: request.treeID,
                nVisual: nil,
                season: request.season,
                gps: request.gps
            )
        }
        .sheet(isPresented: $showCalibration) { CalibrationView() }
        .sheet(isPresented: $showScanHistory) { HistorySheetView() }
        .sheet(isPresented: $showPointCloud) { PointCloudSheet(initialFileURL: selectedPointCloudURL) }
        .sheet(isPresented: $showTagManagement) {
            TagManagementView()
        }
        .sheet(isPresented: $showYieldReport) { YieldReportSheet() }
        .sheet(isPresented: $showCompare) { HistoricalCompareView() }
        .sheet(isPresented: $showTrends) { TrendsSheet() }
        .sheet(isPresented: $showMapView) {
            if #available(iOS 17, *) {
                MapSheet()
            } else {
                Text("地图功能需要 iOS 17")
            }
        }
        .sheet(isPresented: $showImportFile) { ImportFileView() }
        .sheet(isPresented: $showBatchExport) { BatchExportView() }
        .onAppear {
            historyStore.loadRecords()
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.title {
        case "新建扫描": showStartView = true
        case "快速扫描": showQuickScan = true
        case "校准设备": showCalibration = true
        case "全部扫描": showScanHistory = true
        case "点云预览":
            selectedPointCloudURL = nil
            showPointCloud = true
        case "标签管理": showTagManagement = true
        case "产量报告": showYieldReport = true
        case "对比分析": showCompare = true
        case "趋势图表": showTrends = true
        case "地图视图": showMapView = true
        case "导入文件": showImportFile = true
        case "批次导出": showBatchExport = true
        default: break
        }
    }

    private func presentPendingScanIfNeeded() {
        guard let request = pendingScanRequest else { return }
        pendingScanRequest = nil
        TagStore.shared.createOrUpdateAssignment(
            treeId: request.treeID,
            plotId: request.plotId,
            tagIds: request.tagIds,
            status: .reviewing
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            activeScanRequest = request
        }
    }

    private func refreshScanHistory() {
        historyStore.loadRecords()
    }

    private func openPointCloud(_ record: ScanFileRecord) {
        selectedPointCloudURL = record.fileURL
        showPointCloud = true
    }
}

// MARK: - Sheet Views

struct HistorySheetView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Design.Colors.Dark.bgDeep.ignoresSafeArea(); ScanHistoryView(customTitle: "扫描历史") }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.harvest) } }
        }
    }
}

struct PointCloudSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedFile: URL?
    @ObservedObject var historyStore = ScanHistoryStore.shared

    init(initialFileURL: URL? = nil) {
        _selectedFile = State(initialValue: initialFileURL)
    }

    private var filteredFiles: [ScanFileRecord] {
        if searchText.isEmpty {
            return historyStore.scanFiles
        }
        return historyStore.scanFiles.filter { $0.treeID.lowercased().contains(searchText.lowercased()) }
    }

    private var effectiveSelectedFile: URL? {
        selectedFile ?? historyStore.scanFiles.first?.fileURL
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        // 搜索栏
                        searchBar

                        // 点云预览
                        PointCloudView(plyFileURL: effectiveSelectedFile)
                    }
                }
            }
            .navigationTitle("点云预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            historyStore.loadRecords()
            // 默认选中第一个
            if selectedFile == nil, let first = historyStore.scanFiles.first {
                selectedFile = first.fileURL
            }
        }
        .onChange(of: historyStore.scanFiles) { records in
            if selectedFile == nil, let first = records.first {
                selectedFile = first.fileURL
            } else if let selectedFile, !records.contains(where: { $0.fileURL == selectedFile }) {
                self.selectedFile = records.first?.fileURL
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.fill").font(.system(size: 60)).foregroundColor(Design.Colors.harvest.opacity(0.3))
            Text("暂无扫描数据").font(.system(size: 24, weight: .bold)).foregroundColor(Design.Colors.Dark.textPrimary)
            Text("完成扫描后自动显示").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var searchBar: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(Design.Colors.Dark.textSecondary)
                TextField("输入编号搜索（如 T001）", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(Design.Colors.Dark.bgElevated)
            .cornerRadius(10)

            // 搜索结果列表
            if !filteredFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filteredFiles) { record in
                            Button {
                                selectedFile = record.fileURL
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.treeID)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(effectiveSelectedFile == record.fileURL ? Design.Colors.Dark.textPrimary : Design.Colors.Dark.textPrimary)
                                    Text("\(record.fruitCount) 个果实")
                                        .font(.system(size: 11))
                                        .foregroundColor(effectiveSelectedFile == record.fileURL ? Design.Colors.Dark.textSecondary : Design.Colors.Dark.textSecondary)
                                    Text(String(format: "%.1f kg", record.yieldKg))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(effectiveSelectedFile == record.fileURL ? Design.Colors.Dark.textPrimary : Design.Colors.harvest)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(effectiveSelectedFile == record.fileURL ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text("未找到编号 \(searchText) 的记录").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding()
    }
}

struct YieldReportSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var historyStore = ScanHistoryStore.shared

    private var totalScans: Int { historyStore.scanFiles.count }
    private var totalYield: Float { historyStore.scanFiles.reduce(0) { $0 + $1.yieldKg } }
    private var avgYield: Float { totalScans > 0 ? totalYield / Float(totalScans) : 0 }
    private var totalFruit: Int { historyStore.scanFiles.reduce(0) { $0 + $1.fruitCount } }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.pie.fill").font(.system(size: 60)).foregroundColor(Design.Colors.harvest.opacity(0.3))
                        Text("产量报告").font(.system(size: 24, weight: .bold)).foregroundColor(Design.Colors.Dark.textPrimary)
                        Text("扫描数据后自动生成").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Design.Space.lg) {
                            // Summary Stats
                            HStack(spacing: Design.Space.md) {
                                YieldStatCard(title: "扫描次数", value: "\(totalScans)", icon: "cube.fill", color: Design.Colors.harvest)
                                YieldStatCard(title: "总产量", value: String(format: "%.1f kg", totalYield), icon: "scalemass.fill", color: Design.Colors.harvest)
                            }
                            HStack(spacing: Design.Space.md) {
                                YieldStatCard(title: "平均产量", value: String(format: "%.1f kg", avgYield), icon: "chart.bar.fill", color: Design.Colors.Dark.info)
                                YieldStatCard(title: "总果实", value: "\(totalFruit)", icon: "leaf.fill", color: Design.Colors.Dark.info)
                            }

                            // Per-tree breakdown
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("各树产量").font(.system(size: 16, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
                                ForEach(historyStore.scanFiles.prefix(20)) { record in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("树 #\(record.treeID)").font(.system(size: 14, weight: .medium)).foregroundColor(Design.Colors.Dark.textPrimary)
                                            Text(formatDate(record.scanDate)).font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(String(format: "%.1f kg", record.yieldKg)).font(.system(size: 14, weight: .semibold)).foregroundColor(Design.Colors.harvest)
                                            Text("\(record.fruitCount) 个果实").font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary)
                                        }
                                    }
                                    .padding(Design.Space.md)
                                    .background(Design.Colors.Dark.bgElevated)
                                    .cornerRadius(Design.Radius.medium)
                                }
                            }
                        }
                        .padding(Design.Space.lg)
                    }
                }
            }
            .navigationTitle("产量报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.harvest) } }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct YieldStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            Image(systemName: icon).font(.system(size: 24)).foregroundColor(color)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(Design.Colors.Dark.textPrimary)
            Text(title).font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgElevated)
        .cornerRadius(Design.Radius.large)
    }
}

struct TrendsSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var historyStore = ScanHistoryStore.shared

    private var sortedRecords: [ScanFileRecord] {
        historyStore.scanFiles.sorted { $0.scanDate < $1.scanDate }
    }

    private var maxYield: Float {
        sortedRecords.map { $0.yieldKg }.max() ?? 1
    }

    var body: some View {
        NavigationView {
            ZStack { Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 60)).foregroundColor(Design.Colors.Dark.info.opacity(0.3))
                        Text("趋势图表").font(.system(size: 24, weight: .bold)).foregroundColor(Design.Colors.Dark.textPrimary)
                        Text("查看产量随时间变化的趋势").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Design.Space.lg) {
                            // Bar chart
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("产量趋势").font(.system(size: 16, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)

                                HStack(alignment: .bottom, spacing: 8) {
                                    ForEach(sortedRecords) { record in
                                        VStack(spacing: 4) {
                                            Text(String(format: "%.1f", record.yieldKg))
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(Design.Colors.Dark.textSecondary)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(barColor(for: record.yieldKg))
                                                .frame(width: 32, height: max(4, CGFloat(record.yieldKg / maxYield) * 150))

                                            Text(shortDate(record.scanDate))
                                                .font(.system(size: 10))
                                                .foregroundColor(Design.Colors.Dark.textSecondary)
                                                .rotationEffect(.degrees(-45))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .bottom)
                                .padding(.vertical, Design.Space.md)
                            }
                            .padding(Design.Space.md)
                            .background(Design.Colors.Dark.bgElevated)
                            .cornerRadius(Design.Radius.large)

                            // Data table
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("详细数据").font(.system(size: 16, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
                                ForEach(sortedRecords) { record in
                                    HStack {
                                        Text("树 #\(record.treeID)").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textPrimary)
                                        Spacer()
                                        Text(String(format: "%.1f kg", record.yieldKg)).font(.system(size: 14, weight: .semibold)).foregroundColor(Design.Colors.harvest)
                                        Text("\(record.fruitCount) 个").font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary)
                                    }
                                }
                            }
                            .padding(Design.Space.md)
                            .background(Design.Colors.Dark.bgElevated)
                            .cornerRadius(Design.Radius.large)
                        }
                        .padding(Design.Space.lg)
                    }
                }
            }
            .navigationTitle("趋势图表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.harvest) } }
        }
    }

    private func barColor(for yield: Float) -> Color {
        let ratio = yield / maxYield
        if ratio > 0.7 { return Design.Colors.harvest }
        if ratio > 0.4 { return Design.Colors.Dark.info }
        return Design.Colors.Dark.textMuted
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

@available(iOS 17, *)
struct MapSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        ZStack {
            OrchardMapView()
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                            .shadow(color: .black.opacity(0.15), radius: 4)
                    }
                    .padding(20)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Quick Scan View
struct QuickScanView: View {
    var onLaunchScan: ((ScanLaunchRequest) -> Void)?

    @Environment(\.dismiss) var dismiss
    @State private var gps = GPSRecorder()
    @State private var treeID: String = "Q\((Int.random(in: 1000...9999)))"
    @State private var draftTreeID: String = ""
    @State private var showScan = false
    @State private var isLaunchingScan = false

    var body: some View {
        ZStack {
            Design.Colors.darkGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回").font(.system(size: 16, weight: .medium))
                        }.foregroundColor(Design.Colors.harvest)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle().fill(Design.Colors.harvest.opacity(0.15)).frame(width: 100, height: 100)
                                Circle().strokeBorder(Design.Colors.harvest.opacity(0.5), lineWidth: 2).frame(width: 90, height: 90)
                                Image(systemName: "bolt.fill").font(.system(size: 40)).foregroundColor(Design.Colors.harvest)
                            }
                            Text("快速扫描").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Design.Colors.Dark.textPrimary)
                            Text("简化流程，快速采集").font(.system(size: 14)).foregroundColor(Design.Colors.Dark.textSecondary)
                        }
                        .padding(.top, 20)

                        InputCard(title: "树编号") {
                            TextField("自动生成", text: $draftTreeID)
                                .font(.system(size: 17)).foregroundColor(Design.Colors.Dark.textPrimary)
                                .padding(16).background(Design.Colors.Dark.bgElevated).cornerRadius(12)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                                .textContentType(.none)
                                .submitLabel(.done)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }

                Button(action: launchQuickScan) {
                    HStack(spacing: 12) {
                        if isLaunchingScan {
                            ProgressView()
                                .tint(Design.Colors.Dark.textPrimary)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.fill").font(.system(size: 18))
                        }
                        Text(isLaunchingScan ? "启动中..." : "开始快速扫描").font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(LinearGradient(colors: [Design.Colors.harvest, Design.Colors.harvestDark], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .disabled(!canLaunch)
                .opacity(canLaunch ? 1 : 0.55)
            }
        }
        .onAppear {
            if draftTreeID.isEmpty {
                draftTreeID = treeID
            }
        }
        .onChange(of: showScan) { isPresented in
            if !isPresented {
                isLaunchingScan = false
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView(treeID: treeID, nVisual: nil, season: .mature, gps: gps)
                .onAppear {
                    isLaunchingScan = false
                }
        }
    }

    private var canLaunch: Bool {
        !isLaunchingScan && !draftTreeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func launchQuickScan() {
        guard canLaunch else { return }
        isLaunchingScan = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let normalizedTreeID = draftTreeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTreeID.isEmpty else {
                isLaunchingScan = false
                return
            }

            treeID = normalizedTreeID
            let request = ScanLaunchRequest(
                treeID: normalizedTreeID,
                season: .mature,
                gps: gps,
                plotId: nil,
                tagIds: []
            )
            if let onLaunchScan {
                onLaunchScan(request)
            } else {
                showScan = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !showScan {
                isLaunchingScan = false
            }
        }
    }
}

// MARK: - Navigation Bar

struct TopNavigationBar: View {
    @Binding var showSettings: Bool
    var onHistoryTap: (() -> Void)? = nil
    var historyCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Design.Colors.Dark.bgElevated).frame(width: 44, height: 44)
                    Image(systemName: "cube.fill").font(.system(size: 18)).foregroundStyle(LinearGradient(colors: [Design.Colors.harvest, Design.Colors.harvestLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FruitScanner").font(.system(size: 15, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
                    Text("果树 LiDAR 扫描").font(.system(size: 10, weight: .medium)).foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onHistoryTap?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .medium)).foregroundColor(Design.Colors.Dark.textPrimary)
                        if historyCount > 0 {
                            Text("\(historyCount)").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "1C1C1E")).padding(.horizontal, 6).padding(.vertical, 2).background(Design.Colors.harvest).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Design.Colors.Dark.bgElevated).clipShape(Capsule())
                    .frame(minWidth: Design.Touch.minimumWidth, minHeight: Design.Touch.minimumHeight)
                }
                .accessibilityLabel("扫描历史\(historyCount > 0 ? "，\(historyCount)条记录" : "")")
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundColor(Design.Colors.Dark.textPrimary).frame(width: 44, height: 44).background(Design.Colors.Dark.bgElevated).clipShape(Circle())
                }
                .accessibilityLabel("设置")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Hero Section

struct HeroSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Design.Colors.forest.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Design.Colors.forest)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("果树三维扫描")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text("用 iPhone LiDAR 采集点云、识别果实并估算产量")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ProductBadge(title: "LiDAR", value: "点云采集")
                ProductBadge(title: "RGB", value: "果实识别")
                ProductBadge(title: "CSV", value: "数据导出")
            }
        }
        .padding(18)
        .dashboardSurface(cornerRadius: 12)
    }
}

private struct ProductBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.forest)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Design.Colors.Dark.bgElevated.opacity(0.7))
        .cornerRadius(8)
    }
}

// MARK: - Mode Selector

struct ModeSelector: View {
    @Binding var selectedMode: AppMode
    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                ModeButton(mode: mode, isSelected: selectedMode == mode) {
                    withAnimation(.easeOut(duration: Design.Animation.standard)) { selectedMode = mode }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Design.Colors.Dark.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        )
    }
}

struct ModeButton: View {
    let mode: AppMode
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon).font(.system(size: 14, weight: .semibold))
                Text(mode.title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Design.Colors.forest : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum AppMode: String, CaseIterable {
    case scan, history, analytics
    var title: String { switch self { case .scan: return "扫描"; case .history: return "历史"; case .analytics: return "分析" } }
    var icon: String { switch self { case .scan: return "viewfinder"; case .history: return "clock.arrow.circlepath"; case .analytics: return "chart.bar.xaxis" } }
}

// MARK: - Quick Actions

struct QuickActionsGrid: View {
    let mode: AppMode
    var onAction: ((QuickAction) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷操作").font(.system(size: 18, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(quickActions(for: mode)) { action in QuickActionCard(action: action) { onAction?(action) } }
            }
        }
    }
    func quickActions(for mode: AppMode) -> [QuickAction] {
        switch mode {
        case .scan:
            return [QuickAction(title: "新建扫描", icon: "plus.circle.fill", color: Design.Colors.harvest, description: "开始果树扫描"),
                    QuickAction(title: "快速扫描", icon: "bolt.fill", color: Design.Colors.harvest, description: "快速采集模式"),
                    QuickAction(title: "校准设备", icon: "gyroscope", color: Design.Colors.Dark.info, description: "检查相机与 LiDAR"),
                    QuickAction(title: "导入文件", icon: "square.and.arrow.down.fill", color: Design.Colors.Dark.info, description: "导入点云文件")]
        case .history:
            return [QuickAction(title: "全部扫描", icon: "folder.fill", color: Design.Colors.harvest, description: "查看所有记录"),
                    QuickAction(title: "点云预览", icon: "cube", color: Design.Colors.Dark.info, description: "3D 点云可视化"),
                    QuickAction(title: "标签管理", icon: "tag.fill", color: Design.Colors.harvest, description: "管理树标签"),
                    QuickAction(title: "批次导出", icon: "doc.richtext", color: Design.Colors.harvest, description: "批量导出Excel")]
        case .analytics:
            return [QuickAction(title: "产量报告", icon: "chart.pie.fill", color: Design.Colors.harvest, description: "生成分析报告"),
                    QuickAction(title: "对比分析", icon: "arrow.left.arrow.right", color: Design.Colors.harvest, description: "多棵树对比"),
                    QuickAction(title: "趋势图表", icon: "chart.xyaxis.line", color: Design.Colors.Dark.info, description: "产量趋势"),
                    QuickAction(title: "地图视图", icon: "map.fill", color: Design.Colors.Dark.info, description: "果园分布")]
        }
    }
}

struct QuickAction: Identifiable {
    let title: String, icon: String, color: Color, description: String
    var id: String { title }
}

struct QuickActionCard: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil
    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(action.color.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: action.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(action.color)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textMuted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(action.description).font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 112, alignment: .top)
            .padding(14)
            .dashboardSurface(cornerRadius: 10)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(action.title)，\(action.description)")
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

// MARK: - Recent Scans

struct RecentScansSection: View {
    var scans: [ScanFileRecord]
    var onViewAll: (() -> Void)? = nil
    var onScanTap: ((ScanFileRecord) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近扫描").font(.system(size: 18, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Button("查看全部") { onViewAll?() }.font(.system(size: 13, weight: .medium)).foregroundColor(Design.Colors.forest)
            }
            if scans.isEmpty {
                VStack(spacing: 10) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 30)).foregroundColor(Design.Colors.Dark.textMuted)
                    Text("还没有扫描记录").font(.system(size: 14, weight: .medium)).foregroundColor(Design.Colors.Dark.textSecondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(scans) { record in
                        Button {
                            onScanTap?(record)
                        } label: {
                            RecentScanCard(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看 \(record.treeID) 点云")
                    }
                }
            }
        }
        .padding(16)
        .dashboardSurface(cornerRadius: 12)
    }
}

struct RecentScanCard: View {
    let record: ScanFileRecord
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.scanDate)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack { RoundedRectangle(cornerRadius: 9).fill(Design.Colors.forest.opacity(0.12)).frame(width: 44, height: 44)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundColor(Design.Colors.forest)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.treeID).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Design.Colors.Dark.textPrimary).lineLimit(1)
                Text(dateString).font(.system(size: 12)).foregroundColor(Design.Colors.Dark.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f kg", record.yieldKg)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(Design.Colors.Dark.textPrimary)
                Text("\(record.fruitCount) 个果实").font(.system(size: 11)).foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding(12)
        .background(Design.Colors.Dark.bgElevated.opacity(0.55))
        .cornerRadius(8)
    }
}

// MARK: - Stats Overview

struct StatsOverviewSection: View {
    var records: [ScanFileRecord] = []

    private var todaysRecords: [ScanFileRecord] {
        records.filter { Calendar.current.isDateInToday($0.scanDate) }
    }

    private var todaysYield: Float {
        todaysRecords.reduce(0) { $0 + $1.yieldKg }
    }

    private var todaysTrees: Int {
        Set(todaysRecords.map(\.treeID)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今日概览").font(.system(size: 18, weight: .semibold)).foregroundColor(Design.Colors.Dark.textPrimary)
            HStack(spacing: 16) {
                StatCard(value: "\(todaysRecords.count)", label: "扫描数量", icon: "viewfinder", color: Design.Colors.harvest)
                StatCard(value: String(format: "%.1f", todaysYield), label: "总产量/kg", icon: "scalemass.fill", color: Design.Colors.harvest)
                StatCard(value: "\(todaysTrees)", label: "树编号", icon: "tree.fill", color: Design.Colors.Dark.info)
            }
        }
        .padding(16)
        .dashboardSurface(cornerRadius: 12)
    }
}

struct StatCard: View {
    let value: String, label: String, icon: String, color: Color
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.system(size: 24, weight: .semibold, design: .monospaced)).foregroundColor(Design.Colors.Dark.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Design.Colors.Dark.bgElevated.opacity(0.55))
        .cornerRadius(8)
    }
}

// MARK: - Input Card (for QuickScanView)

struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardSurface(cornerRadius: 10)
    }
}

private extension View {
    func dashboardSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Design.Colors.Dark.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }
}
