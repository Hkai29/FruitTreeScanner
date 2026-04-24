// CloudScanSyncView.swift
// Cloud Sync — Upload progress, status, and history

import SwiftUI

// MARK: - Sync Status
enum SyncStatus: Equatable {
    case idle
    case syncing(progress: Double)
    case completed(lastSync: Date)
    case failed(error: String)

    var icon: String {
        switch self {
        case .idle: return "cloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    var color: Color {
        switch self {
        case .idle: return Design.Colors.slate
        case .syncing: return Design.Colors.forest
        case .completed: return Design.Colors.success
        case .failed: return Design.Colors.error
        }
    }
}

// MARK: - Sync History Item
struct SyncHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let syncDate: Date
    let status: SyncStatus
    let fileSize: Int64

    var fileSizeFormatted: String {
        let mb = Double(fileSize) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: syncDate)
    }
}

// MARK: - CloudScanSyncView
struct CloudScanSyncView: View {
    @State private var syncStatus: SyncStatus = .completed(lastSync: Date())
    @State private var syncHistory: [SyncHistoryItem] = []
    @State private var isRetrying = false

    // TODO: Connect to backend sync service
    private let mockHistory: [SyncHistoryItem] = [
        SyncHistoryItem(fileName: "T0042_2026-04-17.ply", syncDate: Date(), status: .completed(lastSync: Date()), fileSize: 2_450_000),
        SyncHistoryItem(fileName: "T0078_2026-04-16.ply", syncDate: Date().addingTimeInterval(-86400), status: .completed(lastSync: Date()), fileSize: 2_180_000),
        SyncHistoryItem(fileName: "T0055_2026-04-15.ply", syncDate: Date().addingTimeInterval(-172800), status: .completed(lastSync: Date()), fileSize: 1_980_000),
        SyncHistoryItem(fileName: "T0031_2026-04-14.ply", syncDate: Date().addingTimeInterval(-259200), status: .failed(error: "Network timeout"), fileSize: 2_120_000),
    ]

    var body: some View {
        ZStack {
            Design.Colors.bgBase
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Design.Space.lg) {
                    // Hero Sync Status Card
                    syncStatusCard
                        .padding(.top, Design.Space.md)

                    // Sync History Section
                    syncHistorySection

                    Spacer(minLength: Design.Space.xxl)
                }
                .padding(.horizontal, Design.Space.lg)
            }
        }
        .navigationTitle("云端同步")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Design.Colors.bgBase, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            syncHistory = mockHistory
        }
    }

    // MARK: - Sync Status Card
    private var syncStatusCard: some View {
        VStack(spacing: Design.Space.lg) {
            // Animated Sync Ring
            ZStack {
                Circle()
                    .stroke(Design.Colors.stone, lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: syncProgress)
                    .stroke(syncStatus.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: syncProgress)

                Image(systemName: syncStatus.icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(syncStatus.color)
            }

            // Status Text
            VStack(spacing: Design.Space.xs) {
                Text(statusTitle)
                    .font(Design.Typography.title2)
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text(statusSubtitle)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.slate)
            }

            // Retry Button (shown on failure)
            if case .failed = syncStatus {
                Button {
                    retrySync()
                } label: {
                    HStack(spacing: Design.Space.sm) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))

                        Text("重试")
                            .font(Design.Typography.subheadlineMedium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Design.Space.lg)
                    .padding(.vertical, Design.Space.sm)
                    .background(
                        Capsule()
                            .fill(Design.Colors.forest)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.xl)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.xl)
        .shadow(color: Design.Shadow.small.color, radius: Design.Shadow.small.radius, y: Design.Shadow.small.y)
    }

    private var syncProgress: Double {
        switch syncStatus {
        case .idle: return 0
        case .syncing(let progress): return progress
        case .completed: return 1.0
        case .failed: return 0
        }
    }

    private var statusTitle: String {
        switch syncStatus {
        case .idle: return "等待同步"
        case .syncing(let progress): return "同步中... \(Int(progress * 100))%"
        case .completed(let date): return "同步完成"
        case .failed(let error): return "同步失败"
        }
    }

    private var statusSubtitle: String {
        switch syncStatus {
        case .idle: return "暂无待同步文件"
        case .syncing: return "正在上传扫描数据"
        case .completed(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "最近同步: \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .failed(let error): return error
        }
    }

    // MARK: - Sync History Section
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Text("同步历史")
                .font(Design.Typography.headline)
                .foregroundColor(Color(hex: "1C1C1E"))
                .padding(.leading, Design.Space.xs)

            if syncHistory.isEmpty {
                emptyHistoryView
            } else {
                LazyVStack(spacing: Design.Space.md) {
                    ForEach(syncHistory) { item in
                        SyncHistoryRow(item: item) {
                            // Retry action
                        }
                    }
                }
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color(hex: "C7C7CC"))

            Text("暂无同步记录")
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.slate)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.xl)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    // MARK: - Actions
    private func retrySync() {
        isRetrying = true
        syncStatus = .syncing(progress: 0)

        // Simulate sync progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if case .syncing(let progress) = syncStatus {
                let newProgress = min(progress + 0.05, 1.0)
                if newProgress >= 1.0 {
                    timer.invalidate()
                    syncStatus = .completed(lastSync: Date())
                    isRetrying = false
                } else {
                    syncStatus = .syncing(progress: newProgress)
                }
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Sync History Row
struct SyncHistoryRow: View {
    let item: SyncHistoryItem
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            // File Icon
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(iconBackgroundColor.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "doc.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconBackgroundColor)
            }

            // File Info
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(item.fileName)
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Color(hex: "1C1C1E"))
                    .lineLimit(1)

                HStack(spacing: Design.Space.md) {
                    Text(item.dateFormatted)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.slate)

                    Text(item.fileSizeFormatted)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.slate)
                }
            }

            Spacer()

            // Status Icon
            switch item.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Design.Colors.success)

            case .failed:
                Button(action: onRetry) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Design.Colors.error)
                }

            case .syncing:
                ProgressView()
                    .tint(Design.Colors.forest)

            case .idle:
                Image(systemName: "clock")
                    .font(.system(size: 22))
                    .foregroundColor(Design.Colors.slate)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
        .shadow(color: Design.Shadow.subtle.color, radius: Design.Shadow.subtle.radius, y: Design.Shadow.subtle.y)
    }

    private var iconBackgroundColor: Color {
        switch item.status {
        case .completed: return Design.Colors.forest
        case .failed: return Design.Colors.error
        case .syncing: return Design.Colors.forest
        case .idle: return Design.Colors.slate
        }
    }
}

#Preview {
    NavigationView {
        CloudScanSyncView()
    }
}
