// FruitTreeScannerApp.swift
// 果树 LiDAR 采集 App 入口
// 基于 ios-depth-point-cloud (MIT License) 改造

import SwiftUI

enum AppScreen {
    case launch      // 启动页（树木动画）
    case transition  // 过渡页（生长动画）
    case main       // 主界面
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
                            // 启动页显示2.5秒后进入过渡页
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation {
                                    currentScreen = .transition
                                }
                            }
                        }
                case .transition:
                    TransitionPageWrapper(currentScreen: $currentScreen)
                        .transition(.opacity)
                case .main:
                    DashboardView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: currentScreen)
        }
    }
}

// TransitionPage 需要 Binding<Bool>，这里做转换
struct TransitionPageWrapper: View {
    @Binding var currentScreen: AppScreen

    var body: some View {
        TransitionPage(isFinished: Binding(
            get: { false },  // 不使用
            set: { if $0 { currentScreen = .main } }
        ))
    }
}
