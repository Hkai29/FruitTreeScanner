// DashboardView.swift
// 全新主界面 - 自然有机风格

import SwiftUI

struct DashboardView: View {
    @State private var selectedMode: AppMode = .scan
    @State private var showSettings = false
    @State private var showStartView = false
    @State private var showQuickScan = false
    @State private var showCalibration = false
    @State private var showExport = false
    @State private var showScanHistory = false
    @State private var showPointCloud = false
    @State private var showTagManagement = false
    @State private var showYieldReport = false
    @State private var showCompare = false
    @State private var showTrends = false
    @State private var showMapView = false
    @State private var recentScans: [URL] = []
    @StateObject private var historyStore = ScanHistoryStore.shared

    var body: some View {
        ZStack {
            Color(hex: "FAF8F5")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopNavigationBar(
                    showSettings: $showSettings,
                    onHistoryTap: { showScanHistory = true },
                    historyCount: historyStore.scanFiles.count
                )
                .background(Color.white)

                ScrollView {
                    VStack(spacing: 32) {
                        HeroSection()
                        ModeSelector(selectedMode: $selectedMode)
                        QuickActionsGrid(mode: selectedMode, onAction: handleQuickAction)
                        RecentScansSection(scans: recentScans, onViewAll: { showScanHistory = true })
                        StatsOverviewSection(scansCount: recentScans.count)
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScanHistoryStore.didUpdateNotification)) { _ in
            DispatchQueue.main.async {
                historyStore.loadRecords()
                loadRecentScans()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showStartView) { StartView() }
        .fullScreenCover(isPresented: $showQuickScan) { QuickScanView() }
        .sheet(isPresented: $showCalibration) { CalibrationView() }
        .sheet(isPresented: $showExport) { DataExportView() }
        .sheet(isPresented: $showScanHistory) { HistorySheetView() }
        .sheet(isPresented: $showPointCloud) { PointCloudSheet() }
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
        .onAppear { historyStore.loadRecords(); loadRecentScans() }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.title {
        case "新建扫描": showStartView = true
        case "快速扫描": showQuickScan = true
        case "校准设备": showCalibration = true
        case "数据导出": showExport = true
        case "全部扫描": showScanHistory = true
        case "点云预览": showPointCloud = true
        case "标签管理": showTagManagement = true
        case "导出": showExport = true
        case "产量报告": showYieldReport = true
        case "对比分析": showCompare = true
        case "趋势图表": showTrends = true
        case "地图视图": showMapView = true
        default: break
        }
    }

    private func loadRecentScans() {
        let scansDir = getDocumentsDirectory().appendingPathComponent("scans")
        recentScans = (try? FileManager.default.contentsOfDirectory(
            at: scansDir, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles)) ?? []
            .filter { $0.pathExtension == "ply" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
    }
}

// MARK: - Sheet Views

struct HistorySheetView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color.white.ignoresSafeArea(); ScanHistoryView(customTitle: "扫描历史") }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.forest) } }
        }
    }
}

struct PointCloudSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedFile: URL?
    @ObservedObject var historyStore = ScanHistoryStore.shared

    private var filteredFiles: [ScanFileRecord] {
        if searchText.isEmpty {
            return historyStore.scanFiles
        }
        return historyStore.scanFiles.filter { $0.treeID.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        // 搜索栏
                        searchBar

                        // 点云预览
                        PointCloudView(plyFileURL: selectedFile)
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
                            .foregroundColor(Color(hex: "8E8E93"))
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
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.fill").font(.system(size: 60)).foregroundColor(Design.Colors.forest.opacity(0.3))
            Text("暂无扫描数据").font(.system(size: 24, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            Text("完成扫描后自动显示").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
        }
    }

    private var searchBar: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(Color(hex: "8E8E93"))
                TextField("输入编号搜索（如 T001）", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Color(hex: "1C1C1E"))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color(hex: "8E8E93"))
                    }
                }
            }
            .padding(12)
            .background(Color(hex: "F2F2F7"))
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
                                        .foregroundColor(selectedFile == record.fileURL ? Color(hex: "1C1C1E") : Color(hex: "1C1C1E"))
                                    Text("\(record.fruitCount) 个果实")
                                        .font(.system(size: 11))
                                        .foregroundColor(selectedFile == record.fileURL ? Color(hex: "8E8E93") : Color(hex: "8E8E93"))
                                    Text(String(format: "%.1f kg", record.yieldKg))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(selectedFile == record.fileURL ? Color(hex: "1C1C1E") : Design.Colors.forest)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedFile == record.fileURL ? Design.Colors.forest : Color.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text("未找到编号 \(searchText) 的记录").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
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
                Color.white.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.pie.fill").font(.system(size: 60)).foregroundColor(Design.Colors.forest.opacity(0.3))
                        Text("产量报告").font(.system(size: 24, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
                        Text("扫描数据后自动生成").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Design.Space.lg) {
                            // Summary Stats
                            HStack(spacing: Design.Space.md) {
                                YieldStatCard(title: "扫描次数", value: "\(totalScans)", icon: "cube.fill", color: Design.Colors.forest)
                                YieldStatCard(title: "总产量", value: String(format: "%.1f kg", totalYield), icon: "scalemass.fill", color: Design.Colors.harvest)
                            }
                            HStack(spacing: Design.Space.md) {
                                YieldStatCard(title: "平均产量", value: String(format: "%.1f kg", avgYield), icon: "chart.bar.fill", color: Design.Colors.info)
                                YieldStatCard(title: "总果实", value: "\(totalFruit)", icon: "leaf.fill", color: Design.Colors.earth)
                            }

                            // Per-tree breakdown
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("各树产量").font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: "1C1C1E"))
                                ForEach(historyStore.scanFiles.prefix(20)) { record in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("树 #\(record.treeID)").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "1C1C1E"))
                                            Text(formatDate(record.scanDate)).font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(String(format: "%.1f kg", record.yieldKg)).font(.system(size: 14, weight: .semibold)).foregroundColor(Design.Colors.harvest)
                                            Text("\(record.fruitCount) 个果实").font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
                                        }
                                    }
                                    .padding(Design.Space.md)
                                    .background(Color(hex: "F2F2F7"))
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
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.forest) } }
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
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            Text(title).font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Space.md)
        .background(Color(hex: "F2F2F7"))
        .cornerRadius(Design.Radius.large)
    }
}

struct CompareSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            HistoricalCompareView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { dismiss() }.foregroundColor(Design.Colors.forest)
                    }
                }
        }
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
            ZStack { Color.white.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 60)).foregroundColor(Design.Colors.info.opacity(0.3))
                        Text("趋势图表").font(.system(size: 24, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
                        Text("查看产量随时间变化的趋势").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Design.Space.lg) {
                            // Bar chart
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("产量趋势").font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: "1C1C1E"))

                                HStack(alignment: .bottom, spacing: 8) {
                                    ForEach(sortedRecords) { record in
                                        VStack(spacing: 4) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(barColor(for: record.yieldKg))
                                                .frame(width: 32, height: max(4, CGFloat(record.yieldKg / maxYield) * 150))

                                            Text(shortDate(record.scanDate))
                                                .font(.system(size: 10))
                                                .foregroundColor(Color(hex: "8E8E93"))
                                                .rotationEffect(.degrees(-45))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .bottom)
                                .padding(.vertical, Design.Space.md)
                            }
                            .padding(Design.Space.md)
                            .background(Color(hex: "F2F2F7"))
                            .cornerRadius(Design.Radius.large)

                            // Data table
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("详细数据").font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: "1C1C1E"))
                                ForEach(sortedRecords) { record in
                                    HStack {
                                        Text("树 #\(record.treeID)").font(.system(size: 14)).foregroundColor(Color(hex: "1C1C1E"))
                                        Spacer()
                                        Text(String(format: "%.1f kg", record.yieldKg)).font(.system(size: 14, weight: .semibold)).foregroundColor(Design.Colors.harvest)
                                        Text("\(record.fruitCount) 个").font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
                                    }
                                }
                            }
                            .padding(Design.Space.md)
                            .background(Color(hex: "F2F2F7"))
                            .cornerRadius(Design.Radius.large)
                        }
                        .padding(Design.Space.lg)
                    }
                }
            }
            .navigationTitle("趋势图表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Design.Colors.forest) } }
        }
    }

    private func barColor(for yield: Float) -> Color {
        let ratio = yield / maxYield
        if ratio > 0.7 { return Design.Colors.forest }
        if ratio > 0.4 { return Design.Colors.harvest }
        return Design.Colors.info
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
                            .foregroundColor(Color(hex: "1C1C1E"))
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
    @Environment(\.dismiss) var dismiss
    @StateObject private var gps = GPSRecorder()
    @State private var treeID: String = "Q\((Int.random(in: 1000...9999)))"
    @State private var showScan = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回").font(.system(size: 16, weight: .medium))
                        }.foregroundColor(Design.Colors.forest)
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
                            Text("快速扫描").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "1C1C1E"))
                            Text("简化流程，快速采集").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
                        }
                        .padding(.top, 20)

                        InputCard(title: "树编号") {
                            TextField("自动生成", text: $treeID)
                                .font(.system(size: 17)).foregroundColor(Color(hex: "1C1C1E"))
                                .padding(16).background(Color(hex: "F2F2F7")).cornerRadius(12)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }

                Button {
                    showScan = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill").font(.system(size: 18))
                        Text("开始快速扫描").font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "1C1C1E"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(LinearGradient(colors: [Design.Colors.harvest, Design.Colors.harvestDark], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView(treeID: treeID, nVisual: nil, season: .mature, gps: gps)
        }
    }
}

// MARK: - Background Components

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    var body: some View {
        LinearGradient(
            colors: [
                Color.white,
                Color.white.opacity(0.95),
                Design.Colors.forestDark.opacity(0.3),
                Color.white
            ],
            startPoint: animateGradient ? .topLeading : .topTrailing,
            endPoint: animateGradient ? .bottomTrailing : .bottomLeading
        )
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) { animateGradient.toggle() } }
    }
}

struct GridPatternOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let spacing: CGFloat = 40
                let cols = Int(geometry.size.width / spacing) + 1
                let rows = Int(geometry.size.height / spacing) + 1
                for col in 0..<cols { path.move(to: CGPoint(x: CGFloat(col) * spacing, y: 0)); path.addLine(to: CGPoint(x: CGFloat(col) * spacing, y: geometry.size.height)) }
                for row in 0..<rows { path.move(to: CGPoint(x: 0, y: CGFloat(row) * spacing)); path.addLine(to: CGPoint(x: geometry.size.width, y: CGFloat(row) * spacing)) }
            }
            .stroke(Color(hex: "E5E5EA"), lineWidth: 1)
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
                    Circle().fill(Color.white).frame(width: 40, height: 40)
                    Image(systemName: "cube.fill").font(.system(size: 18)).foregroundStyle(LinearGradient(colors: [Design.Colors.forest, Design.Colors.forestLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FruitScanner").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "1C1C1E"))
                    Text("智能果树扫描").font(.system(size: 10, weight: .medium)).foregroundColor(Color(hex: "8E8E93"))
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onHistoryTap?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .medium)).foregroundColor(Color(hex: "1C1C1E"))
                        if historyCount > 0 {
                            Text("\(historyCount)").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "1C1C1E")).padding(.horizontal, 6).padding(.vertical, 2).background(Design.Colors.forest).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Color(hex: "F2F2F7")).clipShape(Capsule())
                }
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundColor(Color(hex: "1C1C1E")).frame(width: 40, height: 40).background(Color(hex: "F2F2F7")).clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Hero Section

struct HeroSection: View {
    @State private var pulseAnimation = false
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Design.Colors.forest.opacity(0.2)).frame(width: 140, height: 140).blur(radius: 20).scaleEffect(pulseAnimation ? 1.1 : 0.9).animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
                Circle().fill(LinearGradient(colors: [Design.Colors.forestDark, Design.Colors.forest.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 120, height: 120)
                Circle().strokeBorder(LinearGradient(colors: [Design.Colors.forest, Design.Colors.forestLight.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3).frame(width: 110, height: 110)
                Image(systemName: "cube.fill").font(.system(size: 48)).foregroundStyle(LinearGradient(colors: [Design.Colors.forest, Design.Colors.forestLight], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Text("果树三维扫描系统").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "1C1C1E"))
            Text("基于 LiDAR 的智能产量估算方案").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "8E8E93"))
        }
        .padding(.vertical, 40)
        .onAppear { pulseAnimation = true }
    }
}

// MARK: - Mode Selector

struct ModeSelector: View {
    @Binding var selectedMode: AppMode
    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                ModeButton(mode: mode, isSelected: selectedMode == mode) {
                    withAnimation(.spring(response: 0.3)) { selectedMode = mode }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)))
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
            .foregroundColor(isSelected ? Design.Colors.cream : Design.Colors.slate)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Design.Colors.forest.opacity(0.2) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Design.Colors.forest : Color.clear, lineWidth: 1))
        }
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
            Text("快捷操作").font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(quickActions(for: mode)) { action in QuickActionCard(action: action) { onAction?(action) } }
            }
        }
    }
    func quickActions(for mode: AppMode) -> [QuickAction] {
        switch mode {
        case .scan:
            return [QuickAction(title: "新建扫描", icon: "plus.circle.fill", color: Design.Colors.forest, description: "开始果树扫描"),
                    QuickAction(title: "快速扫描", icon: "bolt.fill", color: Design.Colors.harvest, description: "快速采集模式"),
                    QuickAction(title: "校准设备", icon: "gyroscope", color: Design.Colors.info, description: "LiDAR 校准"),
                    QuickAction(title: "数据导出", icon: "square.and.arrow.up", color: Design.Colors.earth, description: "导出 PLY/CSV")]
        case .history:
            return [QuickAction(title: "全部扫描", icon: "folder.fill", color: Design.Colors.forest, description: "查看所有记录"),
                    QuickAction(title: "点云预览", icon: "cube", color: Design.Colors.info, description: "3D 点云可视化"),
                    QuickAction(title: "标签管理", icon: "tag.fill", color: Design.Colors.harvest, description: "管理树木分组"),
                    QuickAction(title: "导出", icon: "square.and.arrow.up", color: Design.Colors.earth, description: "批量导出")]
        case .analytics:
            return [QuickAction(title: "产量报告", icon: "chart.pie.fill", color: Design.Colors.forest, description: "生成分析报告"),
                    QuickAction(title: "对比分析", icon: "arrow.left.arrow.right", color: Design.Colors.harvest, description: "多棵树对比"),
                    QuickAction(title: "趋势图表", icon: "chart.xyaxis.line", color: Design.Colors.info, description: "产量趋势"),
                    QuickAction(title: "地图视图", icon: "map.fill", color: Design.Colors.earth, description: "果园分布")]
        }
    }
}

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String, icon: String, color: Color, description: String
}

struct QuickActionCard: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil
    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(action.color.opacity(0.15)).frame(width: 48, height: 48)
                    Image(systemName: action.icon).font(.system(size: 22)).foregroundColor(action.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
                    Text(action.description).font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Recent Scans

struct RecentScansSection: View {
    var scans: [URL]
    var onViewAll: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近扫描").font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
                Spacer()
                Button("查看全部") { onViewAll?() }.font(.system(size: 13, weight: .medium)).foregroundColor(Design.Colors.forest)
            }
            if scans.isEmpty {
                VStack(spacing: 12) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32)).foregroundColor(Design.Colors.slate.opacity(0.3))
                    Text("暂无扫描记录").font(.system(size: 14)).foregroundColor(Color(hex: "8E8E93"))
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 12) { ForEach(scans.prefix(3), id: \.self) { url in RecentScanCard(url: url) } }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)))
    }
}

struct RecentScanCard: View {
    let url: URL
    private var fileName: String { url.deletingPathExtension().lastPathComponent }
    private var dateString: String {
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    private var fileSizeString: String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attr[.size] as? Int else { return "--" }
        return String(format: "%.1f MB", Double(size) / 1_048_576)
    }
    var body: some View {
        HStack(spacing: 16) {
            ZStack { Circle().fill(Design.Colors.forest.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(Design.Colors.forest)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "1C1C1E")).lineLimit(1)
                Text(dateString).font(.system(size: 12)).foregroundColor(Color(hex: "8E8E93"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fileSizeString).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(Design.Colors.forest)
                Text("已完成").font(.system(size: 11)).foregroundColor(Color(hex: "8E8E93"))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }
}

// MARK: - Stats Overview

struct StatsOverviewSection: View {
    var scansCount: Int = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今日概览").font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            HStack(spacing: 16) {
                StatCard(value: "\(scansCount)", label: "扫描数量", icon: "viewfinder", color: Design.Colors.forest)
                StatCard(value: "--", label: "总产量/kg", icon: "scalemass.fill", color: Design.Colors.harvest)
                StatCard(value: "--", label: "果园数", icon: "tree.fill", color: Design.Colors.info)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)))
    }
}

struct StatCard: View {
    let value: String, label: String, icon: String, color: Color
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "1C1C1E"))
            Text(label).font(.system(size: 11)).foregroundColor(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
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
                .foregroundColor(Color(hex: "8E8E93"))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
