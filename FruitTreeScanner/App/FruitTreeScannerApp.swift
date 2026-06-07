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

    var body: some Scene {
        WindowGroup {
            Group {
                switch currentScreen {
                case .launch:
                    LaunchScreen()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                withAnimation {
                                    currentScreen = .main
                                }
                            }
                        }
                case .main:
                    DashboardView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: currentScreen)
        }
    }
}
