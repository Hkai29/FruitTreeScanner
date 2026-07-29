// DashboardHomeSections.swift
// 首页模式状态定义

import Foundation

enum AppMode: String, CaseIterable {
    case scan
    case history
    case analytics

    var title: String {
        switch self {
        case .scan: return L10n.Dashboard.scanMode
        case .history: return L10n.Dashboard.historyMode
        case .analytics: return L10n.Dashboard.analyticsMode
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
