// DashboardView.swift
// 全新主界面 - 自然有机风格

import SwiftUI

private enum DashboardDestination: Identifiable, Equatable {
    case settings
    case startScan
    case quickScan
    case calibration
    case scanHistory
    case pointCloud(URL?)
    case tagManagement
    case yieldReport
    case compare
    case trends
    case map
    case importFile
    case batchExport

    var id: String {
        switch self {
        case .settings: return "settings"
        case .startScan: return "startScan"
        case .quickScan: return "quickScan"
        case .calibration: return "calibration"
        case .scanHistory: return "scanHistory"
        case .pointCloud(let url): return "pointCloud:\(url?.absoluteString ?? "latest")"
        case .tagManagement: return "tagManagement"
        case .yieldReport: return "yieldReport"
        case .compare: return "compare"
        case .trends: return "trends"
        case .map: return "map"
        case .importFile: return "importFile"
        case .batchExport: return "batchExport"
        }
    }

    var isFullScreen: Bool {
        self == .startScan || self == .quickScan
    }
}

struct DashboardView: View {
    @State private var destination: DashboardDestination?
    @State private var pendingScanRequest: ScanLaunchRequest?
    @State private var activeScanRequest: ScanLaunchRequest?
    @ObservedObject private var historyStore = ScanHistoryStore.shared

    private var recentScans: [ScanFileRecord] {
        Array(historyStore.scanFiles.prefix(3))
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopNavigationBar(
                    onSettingsTap: { destination = .settings },
                    onHistoryTap: { destination = .scanHistory },
                    historyCount: historyStore.scanFiles.count
                )
                .background(Design.Colors.Dark.bgSurface)

                ScrollView {
                    VStack(spacing: 18) {
                        DashboardHeroPanel(
                            records: historyStore.scanFiles,
                            onStartScan: { destination = .startScan },
                            onQuickScan: { destination = .quickScan }
                        )
                        QuickActionsGrid(onAction: handleQuickAction)
                        RecentScansSection(
                            scans: recentScans,
                            onViewAll: { destination = .scanHistory },
                            onScanTap: openPointCloud,
                            onStartScan: { destination = .startScan }
                        )
                        StatsOverviewSection(records: historyStore.scanFiles)
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
        }
        .sheet(item: sheetDestination) { destination in
            sheetView(for: destination)
        }
        .fullScreenCover(item: fullScreenDestination, onDismiss: presentPendingScanIfNeeded) { destination in
            fullScreenView(for: destination)
        }
        .fullScreenCover(item: $activeScanRequest, onDismiss: refreshScanHistory) { request in
            ScanView(
                treeID: request.treeID,
                gps: request.gps
            )
        }
        .onAppear {
            historyStore.loadRecords()
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.kind {
        case .startScan: destination = .startScan
        case .quickScan: destination = .quickScan
        case .calibration: destination = .calibration
        case .scanHistory: destination = .scanHistory
        case .pointCloud: destination = .pointCloud(nil)
        case .tagManagement: destination = .tagManagement
        case .yieldReport: destination = .yieldReport
        case .compare: destination = .compare
        case .trends: destination = .trends
        case .map: destination = .map
        case .importFile: destination = .importFile
        case .batchExport: destination = .batchExport
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
        destination = .pointCloud(record.fileURL)
    }

    private var sheetDestination: Binding<DashboardDestination?> {
        Binding(
            get: {
                guard let destination, !destination.isFullScreen else { return nil }
                return destination
            },
            set: { destination = $0 }
        )
    }

    private var fullScreenDestination: Binding<DashboardDestination?> {
        Binding(
            get: {
                guard let destination, destination.isFullScreen else { return nil }
                return destination
            },
            set: { destination = $0 }
        )
    }

    @ViewBuilder
    private func fullScreenView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .startScan:
            StartView { request in
                pendingScanRequest = request
                self.destination = nil
            }
        case .quickScan:
            QuickScanView { request in
                pendingScanRequest = request
                self.destination = nil
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sheetView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .calibration:
            CalibrationView()
        case .scanHistory:
            HistorySheetView(
                onStartScan: { self.destination = .startScan },
                onImportFile: { self.destination = .importFile }
            )
        case .pointCloud(let initialFileURL):
            PointCloudSheet(
                initialFileURL: initialFileURL,
                onStartScan: { self.destination = .startScan },
                onImportFile: { self.destination = .importFile }
            )
        case .tagManagement:
            TagManagementView(onStartScan: { self.destination = .startScan })
        case .yieldReport:
            YieldReportSheet(onStartScan: { self.destination = .startScan })
        case .compare:
            HistoricalCompareView(onStartScan: { self.destination = .startScan })
        case .trends:
            TrendsSheet(onStartScan: { self.destination = .startScan })
        case .map:
            if #available(iOS 17, *) {
                MapSheet(onStartScan: { self.destination = .startScan })
            } else {
                Text("地图功能需要 iOS 17")
            }
        case .importFile:
            ImportFileView()
        case .batchExport:
            BatchExportView(
                onStartScan: { self.destination = .startScan },
                onImportFile: { self.destination = .importFile }
            )
        case .startScan, .quickScan:
            EmptyView()
        }
    }
}
