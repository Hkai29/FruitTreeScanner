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
                    DashboardView(router: navigationRouter)
                        .transition(.opacity)
                }
            }
            .background(Color(hex: "101A10").ignoresSafeArea())
            .animation(.easeInOut(duration: 0.5), value: currentScreen)
            .onOpenURL { url in
                guard let navigation = AppNavigation(url: url) else { return }
                navigationRouter.handle(navigation)
            }
        }
    }
}
