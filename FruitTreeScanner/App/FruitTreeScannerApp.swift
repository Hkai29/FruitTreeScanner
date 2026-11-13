// FruitTreeScannerApp.swift
// 果树 LiDAR 采集 App 入口
// 基于 ios-depth-point-cloud (MIT License) 改造

import SwiftUI

enum AppScreen {
    case launch
    case main
}

@main
struct FruitTreeScannerApp: App {
    @State private var currentScreen: AppScreen = .launch
    @StateObject private var navigationRouter = NavigationRouter()
    @StateObject private var appDependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            rootContent
                .background(Color(hex: "0E1214").ignoresSafeArea())
                .animation(.easeInOut(duration: 0.5), value: currentScreen)
                .environmentObject(appDependencies)
                .task {
                    await appDependencies.prepareForScanning()
                }
                .onOpenURL { url in
                    guard let navigation = AppNavigation(url: url) else { return }
                    navigationRouter.handle(navigation)
                }
        }
    }

    /// 根内容。仅 DEBUG 下允许用 `-designReviewHUD` 直接进入采集 HUD 预览，
    /// 用于在没有 ARKit/LiDAR 的模拟器上评审采集界面的排版。
    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-designReviewHUD") {
            DesignReviewHUDPreview()
        } else if ProcessInfo.processInfo.arguments.contains("-designReviewResult") {
            DesignReviewResultPreview()
        } else {
            appContent
        }
        #else
        appContent
        #endif
    }

    @ViewBuilder
    private var appContent: some View {
        switch currentScreen {
        case .launch:
            LaunchScreen()
                .ignoresSafeArea()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation {
                            currentScreen = .main
                        }
                    }
                }
        case .main:
            DashboardView(router: navigationRouter, historyStore: appDependencies.historyStore)
                .transition(.opacity)
        }
    }
}

@MainActor
final class AppDependencies: ObservableObject {
    let settings: SettingsStore
    let parametersStore: FruitParametersStore
    let tagStore: TagStore
    let scanPlanFactory: ScanPlanFactory
    let scanRepository: ScanRepository
    let historyStore: ScanHistoryStore

    init(settings: SettingsStore = .shared, scanRepository: ScanRepository = .shared,
         tagStore: TagStore = .shared, parametersStore: FruitParametersStore? = nil) {
        self.settings = settings
        self.parametersStore = parametersStore ?? .shared
        self.tagStore = tagStore
        self.scanRepository = scanRepository
        self.historyStore = ScanHistoryStore(repository: scanRepository)
        self.scanPlanFactory = ScanPlanFactory(settings: settings, parametersStore: self.parametersStore)
    }

    func prepareForScanning() async {
        await scanPlanFactory.prepareModelIdentity()
    }

    func finalizationOperations(coordinator: ScanCoordinator) -> ScanFinalizationOperations {
        .production(
            coordinator: coordinator,
            repository: scanRepository,
            refreshHistory: { [historyStore] in historyStore.notifyRecordsUpdated() }
        )
    }

    func importOperations() -> ScanImportOperations {
        .production(repository: scanRepository, historyStore: historyStore)
    }

    func batchExportOperations() -> BatchExportOperations {
        .production
    }

    func calibrationScanSource() -> CalibrationScanSource {
        .production(repository: scanRepository, historyStore: historyStore)
    }

    /// Accept selections and freeze their names in the same main-actor action.
    func activateScanRequest(_ request: ScanLaunchRequest) -> ScanLaunchRequest {
        let existing = tagStore.getAssignment(treeId: request.treeID)
        tagStore.createOrUpdateAssignment(
            treeId: request.treeID, plotId: request.plotId, tagIds: request.tagIds,
            status: existing?.status ?? .notScanned
        )
        let accepted = tagStore.getAssignment(treeId: request.treeID)
        let plot = accepted?.plotId.flatMap { id in
            tagStore.plots.first { $0.id == id }.map {
                ScanClassificationSnapshot.Item(id: $0.id, name: $0.name)
            }
        }
        let tags = (accepted?.tagIds ?? []).compactMap { id in
            tagStore.tags.first { $0.id == id }.map {
                ScanClassificationSnapshot.Item(id: $0.id, name: $0.name)
            }
        }
        let classification = ScanClassificationSnapshot(plot: plot, tags: tags)
        return ScanLaunchRequest(
            treeID: request.treeID, selectedFruitCategory: request.selectedFruitCategory,
            season: request.season, gps: request.gps,
            plotId: plot?.id, tagIds: tags.map(\.id),
            classification: classification, id: request.id
        )
    }

    func rescanRequest(treeID: String) -> ScanLaunchRequest? {
        let treeID = TreeIdentifierPolicy.normalized(treeID)
        guard TreeIdentifierPolicy.isValid(treeID) else { return nil }
        let existing = tagStore.getAssignment(treeId: treeID)
        return ScanLaunchRequest(
            treeID: treeID,
            selectedFruitCategory: FruitCategory.scanCategory(for: settings.fruitType),
            season: .mature,
            gps: GPSRecorder(),
            plotId: existing?.plotId,
            tagIds: existing?.tagIds ?? []
        )
    }
}
