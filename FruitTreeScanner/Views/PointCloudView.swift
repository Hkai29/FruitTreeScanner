// PointCloudView.swift
// 3D 点云浏览（SceneKit）。
//
// 视口是本产品最重要的画面，因此：
//   * 画布保持深色仪器底；
//   * 顶部读数条给出真实点数、树高、冠幅；
//   * 明确标注点云来源（设备实采 / 导入 / 外部文件），绝不把样例说成实扫；
//   * 左下角给出按真实树高/冠幅比例绘制的冠层剪影。

import SwiftUI
import SceneKit

/// 点云来源标注。
///
/// 只陈述可证实的事实：这份点云是否在 App 的扫描档案里、是否带有已保存的结果文件。
/// **不推断采集设备**——`requiresSourceValidation` 是导出前重新校验用的标记，
/// 与采集来源无关，不能作为来源证据。
enum PointCloudProvenance: Equatable {
    /// 扫描档案中的点云，且结果文件已保存。
    case archivedScan
    /// 扫描档案中的点云，但没有可核验的结果文件（果数与产量不可用）。
    case archivedWithoutResult
    /// 不在扫描档案中的 PLY 文件。
    case externalFile

    var label: String {
        switch self {
        case .archivedScan:
            return NSLocalizedString("pointcloud.provenance.archived", value: "已存档点云", comment: "Point cloud stored in the local scan archive")
        case .archivedWithoutResult:
            return NSLocalizedString("pointcloud.provenance.archived_no_result", value: "已存档点云 · 无结果文件", comment: "Archived point cloud without a saved result file")
        case .externalFile:
            return NSLocalizedString("pointcloud.provenance.external", value: "外部 PLY 文件", comment: "Point cloud opened from outside the scan archive")
        }
    }

    var systemImage: String {
        switch self {
        case .archivedScan: return "archivebox"
        case .archivedWithoutResult: return "exclamationmark.triangle"
        case .externalFile: return "doc"
        }
    }

    /// 由真实档案记录推导可证实的来源状态。
    static func resolve(record: ScanFileRecord?) -> PointCloudProvenance {
        guard let record else { return .externalFile }
        return record.persistenceState == .complete ? .archivedScan : .archivedWithoutResult
    }
}

enum PointCloudLoadOperation {
    static func load(
        at url: URL,
        parser: @escaping @Sendable (URL) -> PointCloudData? = {
            PLYParserHelper.parsePointCloudData(at: $0)
        }
    ) async -> PointCloudData? {
        guard !Task.isCancelled else { return nil }

        let worker = Task.detached(priority: .userInitiated) {
            parser(url)
        }
        return await withTaskCancellationHandler {
            let loadedData = await worker.value
            guard !Task.isCancelled else { return nil }
            return loadedData
        } onCancel: {
            worker.cancel()
        }
    }
}

// MARK: - PointCloudView
struct PointCloudView: View {
    let plyFileURL: URL?
    var onClose: (() -> Void)? = nil
    var treeID: String? = nil
    var provenance: PointCloudProvenance = .externalFile
    var onChooseArchive: (() -> Void)? = nil

    @State private var pointCount: Int = 0
    @State private var colorMode: PointCloudColorMode = .height
    @State private var viewMode: PointCloudViewMode = .orbit
    @State private var showExportSheet = false
    @State private var showShareError = false
    @State private var showsTools = false
    @State private var isLoading = true
    @State private var pointCloudData: PointCloudData?
    @State private var loadErrorMessage: String?
    @StateObject private var cameraCoordinator = SceneKitPointCloudViewCoordinator()
    @StateObject private var measurementController = PointCloudMeasurementController()
    @State private var showMeasurement = false
    @State private var measuredDistance: Float?
    /// HUD 压住视口的上/下高度：点云取景必须收进没被遮住的那一段。
    @State private var hudTopInset: CGFloat = 0
    @State private var hudBottomInset: CGFloat = 0
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// HUD 遮挡范围变化后交给相机重新取景。
    private func updateHUDSafeInsets() {
        cameraCoordinator.hudSafeInsetsDidChange(
            UIEdgeInsets(top: hudTopInset, left: 0, bottom: hudBottomInset, right: 0)
        )
    }

    var body: some View {
        ZStack {
            // SceneKit Point Cloud
            SceneKitPointCloudView(
                plyFileURL: plyFileURL,
                pointCloudData: pointCloudData,
                colorMode: colorMode,
                viewMode: viewMode,
                pointCount: $pointCount,
                isLoading: $isLoading,
                cameraCoordinator: cameraCoordinator,
                measurementController: measurementController
            )
            .ignoresSafeArea()

            statusOverlay

            // Measurement Tool Overlay
            if showMeasurement {
                MeasurementToolOverlay(
                    controller: measurementController,
                    measuredDistance: $measuredDistance,
                    onClose: stopMeasurement
                )
            }

            // Overlay UI
            if !showMeasurement {
                VStack {
                    PointCloudTopBar(
                        pointCount: pointCount,
                        bounds: pointCloudData?.bounds,
                        viewMode: viewMode,
                        canExport: canExportCurrentFile,
                        onClose: closePreview,
                        onExport: { showExportSheet = true },
                        title: treeID,
                        provenance: provenance,
                        onChooseArchive: onChooseArchive
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PointCloudHUDTopInsetKey.self,
                                value: proxy.size.height
                            )
                        }
                    )

                    Spacer()

                    VStack(alignment: .leading, spacing: Design.Space.sm) {
                        profileOverlay

                        PointCloudToolsEntry(viewMode: viewMode, colorMode: colorMode) {
                            showsTools = true
                        }
                        .frame(maxWidth: 420)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PointCloudHUDBottomInsetKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationBarHidden(true)
        .onPreferenceChange(PointCloudHUDTopInsetKey.self) { value in
            hudTopInset = value
        }
        .onPreferenceChange(PointCloudHUDBottomInsetKey.self) { value in
            hudBottomInset = value
        }
        .onChange(of: hudTopInset) { _ in updateHUDSafeInsets() }
        .onChange(of: hudBottomInset) { _ in updateHUDSafeInsets() }
        .task(id: plyFileURL) {
            stopMeasurement()
            await loadPointCloud()
        }
        .sheet(isPresented: $showExportSheet) {
            if let plyFileURL {
                // 分享点云必须接上完成回调：失败要说出来，不能让用户以为已经分享成功。
                ShareSheet(items: [plyFileURL]) { result in handleShareCompletion(result) }
            }
        }
        .alert(L10n.PointCloud.shareFailureTitle, isPresented: $showShareError) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.PointCloud.shareFailureMessage)
        }
        .sheet(isPresented: $showsTools) {
            NavigationStack {
                ScrollView {
                    PointCloudBottomControls(
                        pointCount: pointCount,
                        canInteract: canUsePointCloud,
                        bounds: pointCloudData?.bounds,
                        colorMode: $colorMode,
                        viewMode: $viewMode,
                        isMeasurementActive: showMeasurement,
                        onResetCamera: { cameraCoordinator.resetCamera() },
                        onZoomIn: { cameraCoordinator.zoomIn() },
                        onZoomOut: { cameraCoordinator.zoomOut() },
                        onToggleMeasurement: {
                            showsTools = false
                            toggleMeasurement()
                        }
                    )
                    .padding(20)
                }
                .background(Design.Colors.Dark.bgDeep)
                .navigationTitle(L10n.PointCloud.toolsTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) { showsTools = false }
                    }
                }
            }
            .dynamicTypeSize(dynamicTypeSize)
            .preferredColorScheme(.dark)
            .tint(Design.Colors.Dark.glow)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: 冠层比例剪影

    /// 按真实树高与冠幅绘制的冠层剪影，附真实尺寸读数。
    @ViewBuilder
    private var profileOverlay: some View {
        if let bounds = pointCloudData?.bounds, pointCount > 0 {
            HStack {
                Spacer(minLength: 0)
                PointCloudProfileCard(bounds: bounds)
            }
        }
    }

    private func closePreview() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var canExportCurrentFile: Bool {
        plyFileURL != nil && canUsePointCloud
    }

    /// 分享点云失败要说出来。
    ///
    /// 之前这里用 `ShareSheet(items:)` 不带完成回调，UIKit 报的失败被直接丢掉：
    /// 分享面板关掉后什么也没发生，用户以为点云已经分享/保存成功。
    /// 用户自己取消不算失败，不打扰。
    private func handleShareCompletion(_ result: ShareActivityResult) {
        guard ScanShareFailurePolicy.isFailure(result) else { return }
        Log.export.error("Point cloud sharing failed: \(result.errorDescription ?? "Unknown activity error")")
        showShareError = true
    }

    private var canUsePointCloud: Bool {
        !isLoading && pointCloudData != nil && pointCount > 0
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isLoading {
            PointCloudStatusPanel(
                icon: "arrow.triangle.2.circlepath",
                title: L10n.PointCloud.loadingTitle,
                message: L10n.PointCloud.loadingMessage,
                showsProgress: true
            )
        } else if let loadErrorMessage {
            PointCloudStatusPanel(
                icon: "exclamationmark.triangle.fill",
                title: L10n.PointCloud.openErrorTitle,
                message: loadErrorMessage,
                tint: Design.Colors.Dark.error
            )
        } else if plyFileURL == nil {
            PointCloudStatusPanel(
                icon: "cube",
                title: L10n.PointCloud.noFileTitle,
                message: L10n.PointCloud.noFileMessage
            )
        } else if pointCloudData == nil || pointCount == 0 {
            PointCloudStatusPanel(
                icon: "cube.transparent",
                title: L10n.PointCloud.noPointsTitle,
                message: L10n.PointCloud.noPointsMessage
            )
        }
    }

    @MainActor
    private func loadPointCloud() async {
        guard let plyFileURL else {
            pointCloudData = nil
            pointCount = 0
            loadErrorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        loadErrorMessage = nil
        let loadedData = await PointCloudLoadOperation.load(at: plyFileURL)
        guard !Task.isCancelled else { return }
        pointCloudData = loadedData
        pointCount = loadedData?.pointCount ?? 0
        loadErrorMessage = loadedData == nil ? L10n.PointCloud.loadFailed : nil
        isLoading = false
    }

    private func toggleMeasurement() {
        guard canUsePointCloud else { return }
        if measurementController.isActive {
            stopMeasurement()
        } else {
            measurementController.activate()
            showMeasurement = true
            measuredDistance = nil
        }
    }

    private func stopMeasurement() {
        measurementController.deactivate()
        showMeasurement = false
        measuredDistance = nil
    }
}

// MARK: - 冠层比例卡

/// 点云范围卡：按统一比例画出的外接尺寸 + 比例尺。
///
/// 这里表达的是整份点云的**外接范围**（AABB），不是分割后的冠层尺寸，
/// 因此只陈述可证实的宽、高与统一比例尺。
struct PointCloudProfileCard: View {
    let bounds: PointCloudBounds

    var body: some View {
        HStack(spacing: 12) {
            InstrumentExtentDiagram(
                widthMeters: CGFloat(bounds.widthMeters),
                heightMeters: CGFloat(bounds.heightMeters),
                tint: Design.Colors.Dark.lidar
            )
            .frame(width: 48, height: 60)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("pointcloud.extent.label", value: "点云范围", comment: "Point cloud bounding extent label"))
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Design.Colors.Dark.textMuted)
                PointCloudMetricText(label: L10n.PointCloud.heightMetric, value: bounds.heightText)
                PointCloudMetricText(label: L10n.PointCloud.footprintMetric, value: bounds.footprintText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Design.Colors.Dark.hudBackground, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 状态面板

struct PointCloudStatusPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let title: String
    let message: String
    var tint: Color = Design.Colors.Dark.glow
    var showsProgress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.control)
                        .fill(tint.opacity(0.14))
                        .frame(width: 34, height: 34)
                    if showsProgress {
                        ProgressView()
                            .tint(tint)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(tint)
                    }
                }
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(14)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 280, alignment: .leading)
        .darkSurface(cornerRadius: Design.Radius.medium, fill: Design.Colors.Dark.hudBackground)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Design.Space.lg : 0)
        .accessibilityIdentifier("pointCloud.status")
    }
}

// MARK: - HUD 遮挡测量

/// 顶部读数条压住视口的高度。
struct PointCloudHUDTopInsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 底部比例尺与工具条压住视口的高度。
struct PointCloudHUDBottomInsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
