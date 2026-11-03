// DesignReviewHUDPreview.swift
// 仅 DEBUG：采集 HUD 的设计评审预览。
//
// 模拟器没有 ARKit 位姿与 LiDAR 深度，因此无法进入真实采集界面。
// 这个预览用**真实的** ScanStatusBar / ScanBottomControlBar / CoverageMapView
// 组件，加上一份**合成的**读数快照，让 HUD 的排版在设备之外也能被原生评审。
//
// 它不是采集结果，不代表任何一次实机扫描；界面上有明确标注。

#if DEBUG
import ARKit
import SwiftUI

struct DesignReviewHUDPreview: View {
    @StateObject private var hudState = ScanHUDState()
    @StateObject private var qualityMonitor = ScanQualityMonitor()
    @StateObject private var measurementController = MetalMeasurementController()

    var body: some View {
        ZStack {
            cameraStandIn
            VStack(spacing: 12) {
                banner
                ScanStatusBar(
                    treeID: "A-02",
                    isRecording: true,
                    hudState: hudState,
                    qualityMonitor: qualityMonitor
                )
                Spacer(minLength: 0)
                ScanCoverageHintBar(hudState: hudState)
                ScanBottomControlBar(
                    isRecording: true,
                    isEstimating: false,
                    canFinish: false,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: {},
                    onToggleRecording: {},
                    onToggleMeasurement: {},
                    onCancel: {},
                    onFinish: {},
                    onDebug: {}
                )
            }
        }
        .task { seedSyntheticSnapshot() }
    }

    /// 采集画面的替身：没有真实相机画面时，用深色底 + 说明代替，
    /// 绝不伪装成一次实机取景。
    private var cameraStandIn: some View {
        ZStack {
            Design.Colors.Dark.bgDeep.ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack {
                Spacer()
                Text("模拟器无相机取景")
                    .font(.system(.caption, design: .default))
                    .foregroundColor(Design.Colors.Dark.textMuted)
                    .padding(.bottom, 12)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text("设计评审预览 · 合成读数，非实机采集")
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Design.Colors.Dark.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Design.Colors.Dark.bgSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// 一份稳定的合成快照，用于评审 HUD 排版。
    @MainActor
    private func seedSyntheticSnapshot() {
        var completion = ScanCompletion()
        completion.overall = 0.68
        completion.timeScore = 0.74
        completion.voxelScore = 0.61
        completion.angleCoverageScore = 0.57
        completion.angleUniformityScore = 0.66
        completion.oppositeSideScore = 0.8
        completion.verticalCoverageScore = 0.55
        completion.stabilityScore = 0.83
        completion.voxelCount = 18_420
        completion.scanDuration = 96
        completion.discoveryTrend = .increasing

        hudState.update(
            pointCount: 182_304,
            coveragePercent: 68,
            scanCompletion: completion,
            visionModelStatus: "CoreML",
            visionModelDetail: "YOLOv8n",
            depthRuntimeStatus: "LiDAR",
            exportablePointStatus: "Ready",
            processedImageFrames: 412,
            detectedFruitCount: 124,
            fusionStatus: "OK",
            cameraSpeed: 0.42,
            medianDepth: 1.85,
            guidanceHint: .goodPace
        )

        qualityMonitor.update(
            with: ScanQualitySample(
                pointDensity: 148,
                trackingState: .normal,
                scanAngle: 0.62,
                ambientIntensity: 0.7
            )
        )
    }
}
#endif
