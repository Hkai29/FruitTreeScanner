// DesignReviewResultPreview.swift
// 仅 DEBUG：结果页的设计评审预览。
//
// 模拟器无法完成一次真实采集（没有 ARKit 位姿与 LiDAR 深度），
// 因此结果页在设备之外没有可达路径。这个预览用**真实的** ResultView
// 加上一份**合成的** YieldResult，让结果页与诊断段的排版能被原生评审。
//
// 合成数据在界面上有明确标注，不代表任何一次实机扫描的结论。

#if DEBUG
import SwiftUI

struct DesignReviewResultPreview: View {
    /// 合成结果的形态：可靠 / 待复核 / 无可靠估产。
    ///
    /// 这里用**枚举**而不是字符串：字符串在 `rawValue` 不匹配时会静默退回 `.reliable`，
    /// 三种形态就会渲染成同一张图。类型安全的传参让这个错误无法发生。
    enum Scenario: String, CaseIterable, Sendable {
        case reliable
        case review
        case noEstimate

        var label: String {
            switch self {
            case .reliable: return "可靠"
            case .review: return "待复核"
            case .noEstimate: return "无可靠估产"
            }
        }
    }

    @State private var scenario: Scenario

    init(initialScenario: Scenario = .reliable) {
        _scenario = State(initialValue: initialScenario)
    }

    var body: some View {
        VStack(spacing: 0) {
            switcher
            ResultView(
                treeID: "A-02",
                result: result(for: scenario),
                persistenceState: scenario == .review ? .failed : .saved,
                onRetryPersistence: {},
                onDismiss: {},
                onDismissToHome: {},
                tagStore: TagStore.shared
            )
        }
    }

    private var switcher: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text("设计评审预览 · 合成结果，非实机采集")
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Picker("scenario", selection: $scenario) {
                ForEach(Scenario.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .foregroundColor(Design.Colors.Workspace.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Design.Colors.Workspace.inset)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
    }

    private func result(for scenario: Scenario) -> YieldResult {
        var result = YieldResult()
        result.nLidar = scenario == .noEstimate ? 0 : 124
        result.nVisual = scenario == .noEstimate ? 61 : 138
        result.correctionK = 1.04
        result.yieldBVisibleKg = scenario == .noEstimate ? 0 : 15.8
        result.yieldBCorrectedKg = scenario == .noEstimate ? 0 : 16.4
        result.meanDiameterCm = 7.8
        result.meanVolumeCm3 = 248
        result.yieldAKg = scenario == .noEstimate ? nil : 12.9
        result.yieldFinalKg = scenario == .noEstimate ? 0 : 16.4
        result.confidence = scenario == .reliable ? "high" : (scenario == .review ? "medium" : "low")
        result.methodUsed = "fusion_only"
        result.treeHeightM = 3.42
        result.crownVolM3 = 6.8
        result.clusterEps = 0.035
        result.clusterMinPoints = 30
        result.fruitCategory = "apple"
        result.occlusionK = 1.0
        result.pointCloudSize = 182_304
        result.note = scenario == .noEstimate
            ? "未获得 .fused 融合证据，本次不给出可靠估产。"
            : ""

        var diagnostics = ScanYieldDiagnostics()
        diagnostics.pointCloudPointCount = 182_304
        diagnostics.imageDetectionCount = 138
        diagnostics.deduplicatedImageDetectionCount = 131
        diagnostics.pointCloudColorFilteredCount = 176_220
        diagnostics.pointCloudDenoisedPointCount = 171_880
        diagnostics.pointCloudOutlierPointCount = 2_104
        diagnostics.pointCloudClusterCandidateCount = 96
        diagnostics.detectionDepthCandidateCount = 28
        diagnostics.fusedFruitCount = scenario == .noEstimate ? 0 : 124
        diagnostics.validatedFruitCount = scenario == .noEstimate ? 0 : 124
        diagnostics.fusedValidationCount = scenario == .noEstimate ? 0 : 96
        diagnostics.trackedImageFruitCount = scenario == .noEstimate ? 18 : 8
        diagnostics.imageOnlyFruitCount = scenario == .noEstimate ? 61 : 12
        diagnostics.cloudOnlyFruitCount = scenario == .noEstimate ? 34 : 4
        diagnostics.validationSourceReliability = scenario == .reliable ? 0.92 : (scenario == .review ? 0.48 : 0)
        diagnostics.pointCloudAngleCoverage = 0.68
        diagnostics.cameraAngleCoverage = 0.61
        if scenario == .noEstimate {
            diagnostics.depthAvailable = false
            diagnostics.zeroYieldReasons = ["深度不可用"]
        }
        result.diagnostics = diagnostics
        return result
    }
}
#endif
