// DashboardHomeSections.swift
// 首页模式状态定义

import Foundation

enum AppMode: String, CaseIterable {
    case scan
    case history
    case analytics

    var title: String {
        switch self {
        case .scan: return "扫描"
        case .history: return "历史"
        case .analytics: return "分析"
        }
    }

    var icon: String {
        switch self {
        case .scan: return "viewfinder"
        case .history: return "clock.arrow.circlepath"
        case .analytics: return "chart.bar.xaxis"
        }
    }
}
