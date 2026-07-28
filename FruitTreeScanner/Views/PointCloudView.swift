// PointCloudView.swift
// 3D Point Cloud Visualization using SceneKit

import SwiftUI
import SceneKit

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

    @State private var pointCount: Int = 0
    @State private var colorMode: PointCloudColorMode = .height
    @State private var viewMode: PointCloudViewMode = .orbit
    @State private var showExportSheet = false
    @State private var isLoading = true
    @State private var pointCloudData: PointCloudData?
    @State private var loadErrorMessage: String?
    @StateObject private var cameraCoordinator = SceneKitPointCloudViewCoordinator()
    @StateObject private var measurementController = PointCloudMeasurementController()
    @State private var showMeasurement = false
    @State private var measuredDistance: Float?
    @Environment(\.dismiss) var dismiss

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
            VStack {
                // Top Bar
                PointCloudTopBar(
                    pointCount: pointCount,
                    bounds: pointCloudData?.bounds,
                    viewMode: viewMode,
                    canExport: canExportCurrentFile,
                    onClose: { dismiss() },
                    onExport: { showExportSheet = true }
                )

                Spacer()

                // Bottom Controls
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
                    onToggleMeasurement: toggleMeasurement
                )
            }
            .padding(Design.Space.lg)
        }
        .navigationBarHidden(true)
        .task(id: plyFileURL) {
            stopMeasurement()
            await loadPointCloud()
        }
        .sheet(isPresented: $showExportSheet) {
            if let plyFileURL {
                ShareSheet(items: [plyFileURL])
            }
        }
    }

    private var canExportCurrentFile: Bool {
        plyFileURL != nil && canUsePointCloud
    }

    private var canUsePointCloud: Bool {
        !isLoading && pointCloudData != nil && pointCount > 0
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isLoading {
            PointCloudStatusPanel(
                icon: "arrow.triangle.2.circlepath",
                title: "正在读取点云",
                message: "解析 PLY 点和颜色数据...",
                showsProgress: true
            )
        } else if let loadErrorMessage {
            PointCloudStatusPanel(
                icon: "exclamationmark.triangle.fill",
                title: "无法打开点云",
                message: loadErrorMessage,
                tint: Design.Colors.apple
            )
        } else if plyFileURL == nil {
            PointCloudStatusPanel(
                icon: "cube",
                title: "暂无点云文件",
                message: "完成扫描或导入 PLY 后，可在这里旋转、测量和分享点云。"
            )
        } else if pointCloudData == nil || pointCount == 0 {
            PointCloudStatusPanel(
                icon: "cube.transparent",
                title: "没有可显示的点",
                message: "该文件未解析到有效点云，请检查 PLY 内容。"
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
        loadErrorMessage = loadedData == nil ? "无法读取点云文件" : nil
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

private struct PointCloudStatusPanel: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Design.Colors.harvest
    var showsProgress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                if showsProgress {
                    ProgressView()
                        .tint(tint)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.hudBackground)
    }
}
