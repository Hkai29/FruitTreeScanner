import SwiftUI

struct DashboardHomeLayoutView: View {
    let records: [ScanFileRecord]
    let recentScans: [ScanFileRecord]
    let onSettingsTap: () -> Void
    let onHistoryTap: () -> Void
    let onStartScan: () -> Void
    let onQuickScan: () -> Void
    let onQuickAction: (QuickAction) -> Void
    let onScanTap: (ScanFileRecord) -> Void

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && proxy.size.width >= 760

            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    TopNavigationBar(
                        onSettingsTap: onSettingsTap,
                        onHistoryTap: onHistoryTap,
                        historyCount: records.count
                    )
                    .background(Design.Colors.Dark.bgSurface)

                    if isLandscape {
                        landscapeScrollArea
                    } else {
                        portraitScrollArea(width: proxy.size.width)
                    }
                }
                .frame(width: proxy.size.width)
            }
        }
    }

    private func portraitScrollArea(width: CGFloat) -> some View {
        ScrollView {
            portraitDashboard
                .frame(width: max(0, width - 36))
                .padding(.horizontal, 18)
                .padding(.top, 14)
        }
    }

    private var portraitDashboard: some View {
        VStack(spacing: 18) {
            DashboardHeroPanel(
                records: records,
                onStartScan: onStartScan,
                onQuickScan: onQuickScan
            )
            QuickActionsGrid(onAction: onQuickAction)
            RecentScansSection(
                scans: recentScans,
                onViewAll: onHistoryTap,
                onScanTap: onScanTap,
                onStartScan: onStartScan
            )
            StatsOverviewSection(records: records)
            Spacer(minLength: 100)
        }
    }

    private var landscapeScrollArea: some View {
        GeometryReader { contentProxy in
            ScrollView(showsIndicators: false) {
                landscapeDashboard(
                    width: contentProxy.size.width,
                    height: max(contentProxy.size.height, 492)
                )
                .padding(18)
            }
        }
    }

    private func landscapeDashboard(width: CGFloat, height: CGFloat) -> some View {
        let contentWidth = min(width - 36, 1180)
        let contentHeight = max(0, height - 36)
        let columnWidth = (contentWidth - 14) / 2
        let rowHeight = max(220, (contentHeight - 16) / 2)

        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DashboardHeroPanel(
                    records: records,
                    onStartScan: onStartScan,
                    onQuickScan: onQuickScan,
                    compactLandscape: true
                )
                .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)

                QuickActionsGrid(compactLandscape: true, onAction: onQuickAction)
                    .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)
            }
            .frame(height: rowHeight)

            HStack(alignment: .top, spacing: 14) {
                RecentScansSection(
                    scans: recentScans,
                    onViewAll: onHistoryTap,
                    onScanTap: onScanTap,
                    onStartScan: onStartScan,
                    compactLandscape: true
                )
                .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)

                StatsOverviewSection(records: records, compactLandscape: true)
                    .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)
            }
            .frame(height: rowHeight)
        }
        .frame(width: contentWidth)
        .frame(height: contentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
