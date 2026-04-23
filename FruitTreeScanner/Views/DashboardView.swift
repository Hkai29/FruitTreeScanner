// DashboardView.swift
// 全新主界面 - 大气科技感菜单

import SwiftUI

struct DashboardView: View {
    @State private var selectedMode: AppMode = .scan
    @State private var showSettings = false
    @State private var showStartView = false
    @State private var showQuickScan = false
    @State private var showCalibration = false
    @State private var showExport = false
    @State private var showScanHistory = false
    @State private var showRecentScans = false
    @State private var showFavorites = false
    @State private var showYieldReport = false
    @State private var showCompare = false
    @State private var showTrends = false
    @State private var showMapView = false
    @State private var recentScans: [URL] = []
    @StateObject private var historyStore = ScanHistoryStore.shared

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            GridPatternOverlay()

            VStack(spacing: 0) {
                TopNavigationBar(
                    showSettings: $showSettings,
                    onHistoryTap: { showScanHistory = true },
                    historyCount: historyStore.scanFiles.count
                )
                .background(Color.black.opacity(0.3))

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
            historyStore.loadRecords()
            loadRecentScans()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showStartView) { StartView() }
        .fullScreenCover(isPresented: $showQuickScan) { QuickScanView() }
        .sheet(isPresented: $showCalibration) { CalibrationView() }
        .sheet(isPresented: $showExport) { DataExportView() }
        .sheet(isPresented: $showScanHistory) { HistorySheetView() }
        .sheet(isPresented: $showRecentScans) { RecentScansSheet() }
        .sheet(isPresented: $showFavorites) { FavoritesSheet() }
        .sheet(isPresented: $showYieldReport) { YieldReportSheet() }
        .sheet(isPresented: $showCompare) { CompareSheet() }
        .sheet(isPresented: $showTrends) { TrendsSheet() }
        .sheet(isPresented: $showMapView) { MapSheet() }
        .onAppear { historyStore.loadRecords(); loadRecentScans() }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.title {
        case "新建扫描": showStartView = true
        case "快速扫描": showQuickScan = true
        case "校准设备": showCalibration = true
        case "数据导出": showExport = true
        case "全部扫描": showScanHistory = true
        case "最近": showRecentScans = true
        case "收藏": showFavorites = true
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
            ZStack { Color(hex: "0a1628").ignoresSafeArea(); ScanHistoryView(customTitle: "扫描历史") }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct RecentScansSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea(); ScanHistoryView(customTitle: "最近扫描") }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct FavoritesSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "star.fill").font(.system(size: 60)).foregroundColor(.white.opacity(0.2))
                    Text("暂无收藏").font(.system(size: 18, weight: .medium)).foregroundColor(.white.opacity(0.4))
                    Text("收藏的扫描会显示在这里").font(.system(size: 14)).foregroundColor(.white.opacity(0.3))
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct YieldReportSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie.fill").font(.system(size: 60)).foregroundColor(Color(hex: "4ADE80").opacity(0.3))
                    Text("产量报告").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text("扫描数据后自动生成").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                }
            }
            .navigationTitle("产量报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct CompareSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 60)).foregroundColor(Color(hex: "FBBF24").opacity(0.3))
                    Text("对比分析").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text("选择多棵树进行产量对比").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                }
            }
            .navigationTitle("对比分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct TrendsSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 60)).foregroundColor(Color(hex: "60A5FA").opacity(0.3))
                    Text("趋势图表").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text("查看产量随时间变化的趋势").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                }
            }
            .navigationTitle("趋势图表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct MapSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "map.fill").font(.system(size: 60)).foregroundColor(Color(hex: "A78BFA").opacity(0.3))
                    Text("果园地图").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text("查看果园分布和产量热力图").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                    Button("打开完整地图") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "4ADE80"))
                    .padding(.top, 20)
                }
            }
            .navigationTitle("地图视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
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
            Color(hex: "0a1628").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回").font(.system(size: 16, weight: .medium))
                        }.foregroundColor(Color(hex: "4ADE80"))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle().fill(Color(hex: "FBBF24").opacity(0.15)).frame(width: 100, height: 100)
                                Circle().strokeBorder(Color(hex: "FBBF24").opacity(0.5), lineWidth: 2).frame(width: 90, height: 90)
                                Image(systemName: "bolt.fill").font(.system(size: 40)).foregroundColor(Color(hex: "FBBF24"))
                            }
                            Text("快速扫描").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Text("简化流程，快速采集").font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 20)

                        InputCard(title: "树编号") {
                            TextField("自动生成", text: $treeID)
                                .font(.system(size: 17)).foregroundColor(.white)
                                .padding(16).background(Color.white.opacity(0.05)).cornerRadius(12)
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
                    .foregroundColor(Color(hex: "0a1628"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(LinearGradient(colors: [Color(hex: "FBBF24"), Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing))
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
        LinearGradient(colors: [Color(hex: "0a1628"), Color(hex: "1a2f4a"), Color(hex: "0d1f3c"), Color(hex: "081428")],
                       startPoint: animateGradient ? .topLeading : .topTrailing,
                       endPoint: animateGradient ? .bottomTrailing : .bottomLeading)
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
            .stroke(Color.white.opacity(0.03), lineWidth: 1)
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
                    Circle().fill(Color.white.opacity(0.1)).frame(width: 40, height: 40)
                    Image(systemName: "cube.fill").font(.system(size: 18)).foregroundStyle(LinearGradient(colors: [Color(hex: "4ADE80"), Color(hex: "22C55E")], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FruitScanner").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("智能果树扫描").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onHistoryTap?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                        if historyCount > 0 {
                            Text("\(historyCount)").font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "4ADE80")).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.1)).clipShape(Capsule())
                }
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundColor(.white).frame(width: 40, height: 40).background(Color.white.opacity(0.1)).clipShape(Circle())
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
                Circle().fill(Color(hex: "4ADE80").opacity(0.2)).frame(width: 140, height: 140).blur(radius: 20).scaleEffect(pulseAnimation ? 1.1 : 0.9).animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
                Circle().fill(LinearGradient(colors: [Color(hex: "1a3a2a"), Color(hex: "0d2818")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 120, height: 120)
                Circle().strokeBorder(LinearGradient(colors: [Color(hex: "4ADE80"), Color(hex: "22C55E").opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3).frame(width: 110, height: 110)
                Image(systemName: "cube.fill").font(.system(size: 48)).foregroundStyle(LinearGradient(colors: [Color(hex: "4ADE80"), Color(hex: "22C55E")], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Text("果树三维扫描系统").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text("基于 LiDAR 的智能产量估算方案").font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.6))
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1)))
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
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color(hex: "4ADE80").opacity(0.2) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color(hex: "4ADE80") : Color.clear, lineWidth: 1))
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
            Text("快捷操作").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(quickActions(for: mode)) { action in QuickActionCard(action: action) { onAction?(action) } }
            }
        }
    }
    func quickActions(for mode: AppMode) -> [QuickAction] {
        switch mode {
        case .scan:
            return [QuickAction(title: "新建扫描", icon: "plus.circle.fill", color: "4ADE80", description: "开始果树扫描"),
                    QuickAction(title: "快速扫描", icon: "bolt.fill", color: "FBBF24", description: "快速采集模式"),
                    QuickAction(title: "校准设备", icon: "gyroscope", color: "60A5FA", description: "LiDAR 校准"),
                    QuickAction(title: "数据导出", icon: "square.and.arrow.up", color: "A78BFA", description: "导出 PLY/CSV")]
        case .history:
            return [QuickAction(title: "全部扫描", icon: "folder.fill", color: "4ADE80", description: "查看所有记录"),
                    QuickAction(title: "最近", icon: "clock.fill", color: "FBBF24", description: "最近的扫描"),
                    QuickAction(title: "收藏", icon: "star.fill", color: "60A5FA", description: "标记的扫描"),
                    QuickAction(title: "导出", icon: "square.and.arrow.up", color: "A78BFA", description: "批量导出")]
        case .analytics:
            return [QuickAction(title: "产量报告", icon: "chart.pie.fill", color: "4ADE80", description: "生成分析报告"),
                    QuickAction(title: "对比分析", icon: "arrow.left.arrow.right", color: "FBBF24", description: "多棵树对比"),
                    QuickAction(title: "趋势图表", icon: "chart.xyaxis.line", color: "60A5FA", description: "产量趋势"),
                    QuickAction(title: "地图视图", icon: "map.fill", color: "A78BFA", description: "果园分布")]
        }
    }
}

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String, icon: String, color: String, description: String
}

struct QuickActionCard: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil
    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(Color(hex: action.color).opacity(0.15)).frame(width: 48, height: 48)
                    Image(systemName: action.icon).font(.system(size: 22)).foregroundColor(Color(hex: action.color))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(action.description).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
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
                Text("最近扫描").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button("查看全部") { onViewAll?() }.font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "4ADE80"))
            }
            if scans.isEmpty {
                VStack(spacing: 12) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32)).foregroundColor(.white.opacity(0.2))
                    Text("暂无扫描记录").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 12) { ForEach(scans.prefix(3), id: \.self) { url in RecentScanCard(url: url) } }
            }
        }
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
            ZStack { Circle().fill(Color(hex: "4ADE80").opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(Color(hex: "4ADE80"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white).lineLimit(1)
                Text(dateString).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fileSizeString).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "4ADE80"))
                Text("已完成").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Stats Overview

struct StatsOverviewSection: View {
    var scansCount: Int = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今日概览").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            HStack(spacing: 16) {
                StatCard(value: "\(scansCount)", label: "扫描数量", icon: "viewfinder", color: "4ADE80")
                StatCard(value: "--", label: "总产量/kg", icon: "scalemass.fill", color: "FBBF24")
                StatCard(value: "--", label: "果园数", icon: "tree.fill", color: "60A5FA")
            }
        }
    }
}

struct StatCard: View {
    let value: String, label: String, icon: String, color: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color(hex: color))
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ZStack { Color(hex: "0a1628").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        SettingsSection(title: "设备") {
                            SettingsRow(icon: "gyroscope", title: "校准", subtitle: "LiDAR 传感器校准")
                            SettingsRow(icon: "camera.fill", title: "相机设置", subtitle: "分辨率和帧率")
                        }
                        SettingsSection(title: "扫描") {
                            SettingsRow(icon: "slider.horizontal.3", title: "质量预设", subtitle: "高/中/低")
                            SettingsRow(icon: "point.3.connectedtriangleright.dottedpath", title: "点云设置", subtitle: "最大点数和精度")
                        }
                        SettingsSection(title: "数据") {
                            SettingsRow(icon: "icloud.fill", title: "云同步", subtitle: "iCloud 同步设置")
                            SettingsRow(icon: "square.and.arrow.up", title: "导出格式", subtitle: "PLY / CSV / JSON")
                        }
                    }.padding()
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(Color(hex: "4ADE80")) } }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase)
            VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        }
    }
}

struct SettingsRow: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(Color(hex: "4ADE80")).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                Text(subtitle).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.3))
        }.padding(16)
    }
}

// MARK: - Input Card

struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }
}