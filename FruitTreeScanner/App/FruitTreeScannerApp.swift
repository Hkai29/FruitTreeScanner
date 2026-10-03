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
            Group {
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
            .background(Color(hex: "101A10").ignoresSafeArea())
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
}

@MainActor
final class AppDependencies: ObservableObject {
    let settings: SettingsStore
    let tagStore: TagStore
    let scanPlanFactory: ScanPlanFactory
    let scanRepository: ScanRepository
    let historyStore: ScanHistoryStore

    init(settings: SettingsStore = .shared, scanRepository: ScanRepository = .shared, tagStore: TagStore = .shared) {
        self.settings = settings
        self.tagStore = tagStore
        self.scanRepository = scanRepository
        self.historyStore = ScanHistoryStore(repository: scanRepository)
        self.scanPlanFactory = ScanPlanFactory(settings: settings)
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

    func calibrationScanSource() -> CalibrationScanSource {
        .production(repository: scanRepository, historyStore: historyStore)
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
