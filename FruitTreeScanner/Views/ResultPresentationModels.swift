import SwiftUI

struct ResultConfidencePresentation {
    let rawValue: String
    private let bundle: Bundle

    init(_ rawValue: String, bundle: Bundle = .main) {
        self.rawValue = rawValue
        self.bundle = bundle
    }

    var label: String {
        L10n.Result.confidenceLabel(rawValue, in: bundle)
    }

    var color: Color {
        switch rawValue {
        case "high": return Design.Colors.forest
        case "medium": return Design.Colors.harvest
        case "manual_review": return Design.Colors.apple
        default: return Design.Colors.slate
        }
    }
}

enum ResultValueFormatter {
    static func finalYieldKg(_ value: Float) -> String {
        String(format: "%.1f", value)
    }

    static func correctionFactor(_ value: Float) -> String {
        String(format: "×%.2f", value)
    }

    static func kilograms(_ value: Float) -> String {
        String(format: "%.2f kg", value)
    }

    static func centimeters(_ value: Float) -> String {
        String(format: "%.1f cm", value)
    }

    static func cubicMeters(_ value: Float) -> String {
        String(format: "%.3f m³", value)
    }

    static func meters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    static func dbscanEps(_ value: Float) -> String {
        String(format: "%.3f m", value)
    }

    static func occlusionK(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

enum ResultReviewPolicy {
    static func needsReview(_ confidence: String) -> Bool {
        switch confidence {
        case "high", "medium":
            return false
        default:
            return true
        }
    }
}

struct ResultReliabilityPresentation {
    enum Level: Equatable {
        case reliable
        case review
        case unreliable
        case noReliableEstimate
    }

    let level: Level
    let title: String
    let summary: String
    let recommendedAction: String
    let diagnosticHint: String?

    init(result: YieldResult, bundle: Bundle = .main) {
        let diagnostics = result.diagnostics
        let fusedCount = max(
            diagnostics.fusedValidationCount,
            result.validatedFruits.filter { $0.source == ValidationSource.fused.rawValue }.count
        )
        let nonFusedEvidenceCount = diagnostics.imageOnlyFruitCount
            + diagnostics.cloudOnlyFruitCount
            + diagnostics.trackedImageFruitCount
        let primaryZeroYieldReason = diagnostics.zeroYieldReasons.first
        let hasUnmappedLabels = !diagnostics.imageUnmappedLabels.isEmpty
        let hasSelectedFruitFiltering = diagnostics.filteredBySelectedFruitTypeCount > 0
        let hasWeakFusionEvidence = fusedCount == 0 && nonFusedEvidenceCount > 0
        let confidenceNeedsReview = ResultReviewPolicy.needsReview(result.confidence)
        let sourceReliability = diagnostics.validationSourceReliability
        let lowSourceReliability = sourceReliability > 0 && sourceReliability < 0.55

        let action = Self.recommendedAction(
            diagnostics: diagnostics,
            hasSelectedFruitFiltering: hasSelectedFruitFiltering,
            hasUnmappedLabels: hasUnmappedLabels,
            hasWeakFusionEvidence: hasWeakFusionEvidence,
            bundle: bundle
        )
        let hint = Self.diagnosticHint(
            primaryZeroYieldReason: primaryZeroYieldReason,
            hasUnmappedLabels: hasUnmappedLabels,
            hasSelectedFruitFiltering: hasSelectedFruitFiltering,
            hasWeakFusionEvidence: hasWeakFusionEvidence,
            bundle: bundle
        )

        if fusedCount == 0 {
            self.level = .noReliableEstimate
            self.title = L10n.Result.detail(.reliabilityNoEstimateTitle, in: bundle)
            self.summary = primaryZeroYieldReason.map {
                DiagnosticRecommendation.localizedReason($0, in: bundle)
            } ?? L10n.Result.detail(.reliabilityNoEstimateSummary, in: bundle)
            self.recommendedAction = action
            self.diagnosticHint = hint
            return
        }

        if let primaryZeroYieldReason {
            self.level = .unreliable
            self.title = L10n.Result.detail(.reliabilityUnreliableTitle, in: bundle)
            self.summary = DiagnosticRecommendation.localizedReason(primaryZeroYieldReason, in: bundle)
            self.recommendedAction = action
            self.diagnosticHint = hint
            return
        }

        if confidenceNeedsReview || lowSourceReliability || hasSelectedFruitFiltering || hasUnmappedLabels {
            self.level = .review
            self.title = L10n.Result.detail(.reliabilityReviewTitle, in: bundle)
            self.summary = L10n.Result.detail(.reliabilityReviewSummary, in: bundle)
            self.recommendedAction = action
            self.diagnosticHint = hint
            return
        }

        self.level = .reliable
        self.title = L10n.Result.detail(.reliabilityReliableTitle, in: bundle)
        self.summary = L10n.Result.detail(.reliabilityReliableSummary, in: bundle)
        self.recommendedAction = L10n.Result.detail(.actionSaveAndExport, in: bundle)
        self.diagnosticHint = nil
    }

    var iconName: String {
        switch level {
        case .reliable:
            return "checkmark.seal.fill"
        case .review:
            return "exclamationmark.circle.fill"
        case .unreliable:
            return "arrow.clockwise.circle.fill"
        case .noReliableEstimate:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch level {
        case .reliable:
            return Design.Colors.forest
        case .review:
            return Design.Colors.harvest
        case .unreliable, .noReliableEstimate:
            return Design.Colors.warning
        }
    }

    private static func recommendedAction(
        diagnostics: ScanYieldDiagnostics,
        hasSelectedFruitFiltering: Bool,
        hasUnmappedLabels: Bool,
        hasWeakFusionEvidence: Bool,
        bundle: Bundle = .main
    ) -> String {
        if hasSelectedFruitFiltering {
            return L10n.Result.detail(.actionConfirmFruit, in: bundle)
        }
        if hasUnmappedLabels {
            return L10n.Result.detail(.actionCheckMapping, in: bundle)
        }
        if hasWeakFusionEvidence {
            return L10n.Result.detail(.actionInsufficientFusion, in: bundle)
        }
        if !diagnostics.depthAvailable && diagnostics.pointCloudPointCount == 0 {
            return L10n.Result.detail(.actionRescanSlowly, in: bundle)
        }
        if diagnostics.scanAngleCoverage > 0 && diagnostics.scanAngleCoverage < 0.45 {
            return L10n.Result.detail(.actionScanCanopyBack, in: bundle)
        }
        if !diagnostics.zeroYieldReasons.isEmpty {
            return L10n.Result.detail(.actionRescanSlowly, in: bundle)
        }
        return L10n.Result.detail(.actionSaveAndExport, in: bundle)
    }

    private static func diagnosticHint(
        primaryZeroYieldReason: String?,
        hasUnmappedLabels: Bool,
        hasSelectedFruitFiltering: Bool,
        hasWeakFusionEvidence: Bool,
        bundle: Bundle
    ) -> String? {
        if let primaryZeroYieldReason {
            return L10n.Result.detailFormat(
                .hintPrimaryReasonFormat,
                arguments: [DiagnosticRecommendation.localizedReason(primaryZeroYieldReason, in: bundle)],
                in: bundle
            )
        }
        if hasSelectedFruitFiltering {
            return L10n.Result.detail(.hintFruitMismatch, in: bundle)
        }
        if hasUnmappedLabels {
            return L10n.Result.detail(.hintUnmappedLabels, in: bundle)
        }
        if hasWeakFusionEvidence {
            return L10n.Result.detail(.hintWeakFusion, in: bundle)
        }
        return nil
    }
}

enum DiagnosticRecommendation {
    private static let reasonToRecommendation: [String: [L10n.Result.DetailKey]] = [
        "模型未加载": [
            .recommendationModelRestart,
            .recommendationModelCheck
        ],
        "深度不可用": [
            .recommendationDepthDevice,
            .recommendationDepthRestart
        ],
        "点云数量不足": [
            .recommendationPointsSlow,
            .recommendationPointsClean
        ],
        "未处理图像检测帧": [
            .recommendationFramesStable,
            .recommendationFramesSlow
        ],
        "图像检测无结果": [
            .recommendationDetectionsLight,
            .recommendationDetectionsVisible
        ],
        "候选被置信度过滤": [
            .recommendationConfidenceExplanation,
            .recommendationConfidenceAdjust
        ],
        "模型标签未映射到水果类别": [
            .recommendationMappingCheck,
            .recommendationFruitCheck
        ],
        "点云聚类无候选": [
            .recommendationCandidatesDensity,
            .recommendationCandidatesCoverage
        ],
        "融合验证失败": [
            .recommendationFusionMismatch,
            .recommendationFusionStable
        ],
        "cloudOnly 保守模式未接受候选": [
            .recommendationCloudOnlyMode,
            .recommendationCloudOnlyLight
        ]
    ]

    private static let reasonLocalizationKeys: [String: L10n.Result.DetailKey] = [
        "模型未加载": .reasonModelNotLoaded,
        "深度不可用": .reasonDepthUnavailable,
        "点云数量不足": .reasonInsufficientPoints,
        "未处理图像检测帧": .reasonNoImageFrames,
        "图像检测无结果": .reasonNoDetections,
        "候选被置信度过滤": .reasonConfidenceFiltered,
        "模型标签未映射到水果类别": .reasonUnmappedLabels,
        "点云聚类无候选": .reasonNoCandidates,
        "融合验证失败": .reasonFusionFailed,
        "cloudOnly 保守模式未接受候选": .reasonCloudOnlyRejected,
        "非成熟期冠层回归模型尚未标定，本次未生成产量估算": .reasonCrownUntrained
    ]

    static func recommendations(for reasons: [String], bundle: Bundle = .main) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for reason in reasons {
            guard let keys = reasonToRecommendation[reason] else { continue }
            for key in keys {
                let rec = L10n.Result.detail(key, in: bundle)
                if seen.insert(rec).inserted {
                    result.append(rec)
                }
            }
        }
        if result.isEmpty {
            result.append(L10n.Result.detail(.recommendationFallback, in: bundle))
        }
        return result
    }

    static func localizedReason(_ reason: String, in bundle: Bundle = .main) -> String {
        guard let key = reasonLocalizationKeys[reason] else { return reason }
        return L10n.Result.detail(key, in: bundle)
    }
}

struct ResultPostScanWorkflowAdvice {
    let result: YieldResult
    private let bundle: Bundle

    init(result: YieldResult, bundle: Bundle = .main) {
        self.result = result
        self.bundle = bundle
    }

    var confidenceText: String {
        ResultConfidencePresentation(result.confidence, bundle: bundle).label
    }

    var nextStepText: String {
        L10n.Result.detail(
            ResultReviewPolicy.needsReview(result.confidence) ? .workflowNextReview : .workflowNextSave,
            in: bundle
        )
    }

    var primaryAdvice: String {
        switch result.confidence {
        case "high":
            return L10n.Result.detail(.workflowPrimaryHigh, in: bundle)
        case "medium":
            return L10n.Result.detail(.workflowPrimaryMedium, in: bundle)
        default:
            return L10n.Result.detail(.workflowPrimaryLow, in: bundle)
        }
    }

    var reviewFocus: String {
        if result.yieldFinalKg == 0 || ResultReviewPolicy.needsReview(result.confidence) {
            return L10n.Result.detail(.workflowReviewLow, in: bundle)
        }
        if result.nLidar == 0 {
            return L10n.Result.detail(.workflowReviewNoFruit, in: bundle)
        }
        return L10n.Result.detail(.workflowReviewNormal, in: bundle)
    }
}

struct ResultAlgorithmParametersPresentation {
    let result: YieldResult
    private let bundle: Bundle

    init(result: YieldResult, bundle: Bundle = .main) {
        self.result = result
        self.bundle = bundle
    }

    var clusterSensitivityLabel: String {
        switch result.clusterEps {
        case ..<0.018:
            return L10n.Result.detail(.algorithmClusterFine, in: bundle)
        case ..<0.05:
            return L10n.Result.detail(.algorithmClusterStandard, in: bundle)
        default:
            return L10n.Result.detail(.algorithmClusterRelaxed, in: bundle)
        }
    }

    var colorFilterDisplay: String {
        if result.colorFilterDesc == "N/A" {
            return L10n.Result.detail(.algorithmFilterDisabled, in: bundle)
        }
        return L10n.Result.detail(.algorithmFilterEnabled, in: bundle)
    }

    var colorFilterDetail: String {
        guard !result.colorFilterDesc.isEmpty, result.colorFilterDesc != "N/A" else {
            return L10n.Result.detail(.algorithmFilterDisabledDetail, in: bundle)
        }
        return L10n.Result.detailFormat(
            .algorithmFilterDetailFormat,
            arguments: [result.colorFilterDesc],
            in: bundle
        )
    }

    var occlusionDisplay: String {
        if result.occlusionK > 1.01 {
            return L10n.Result.detailFormat(
                .algorithmOcclusionFormat,
                arguments: [ResultValueFormatter.occlusionK(result.occlusionK)],
                in: bundle
            )
        }
        return L10n.Result.detail(.algorithmOcclusionNone, in: bundle)
    }

    var methodDisplayName: String {
        if result.methodUsed.hasSuffix("_coverage_review") {
            return L10n.Result.detail(.algorithmMethodCoverageReview, in: bundle)
        }
        if result.methodUsed.hasSuffix("_coverage_limited") {
            return L10n.Result.detail(.algorithmMethodCoverageLimited, in: bundle)
        }

        switch result.methodUsed {
        case "weighted_AB":
            return L10n.Result.detail(.algorithmMethodWeighted, in: bundle)
        case "average_AB":
            return L10n.Result.detail(.algorithmMethodAverage, in: bundle)
        case "A_only":
            return L10n.Result.detail(.algorithmMethodCrown, in: bundle)
        case "B_only":
            return L10n.Result.detail(.algorithmMethodFruitVolume, in: bundle)
        case "fusion_only", "fusion_visual_calibrated":
            return L10n.Result.detail(.algorithmMethodFusion, in: bundle)
        case "tracked_image_visual_calibrated":
            return L10n.Result.detail(.algorithmMethodTrackedImage, in: bundle)
        case "image_visual_calibrated":
            return L10n.Result.detail(.algorithmMethodImage, in: bundle)
        case "cloud_only_calibrated":
            return L10n.Result.detail(.algorithmMethodCloud, in: bundle)
        case "flagged":
            return L10n.Result.detail(.algorithmMethodManualReview, in: bundle)
        case "crown_untrained":
            return L10n.Result.detail(.algorithmMethodCrownUntrained, in: bundle)
        case "none", "":
            return L10n.Result.detail(.algorithmMethodNone, in: bundle)
        default:
            return result.methodUsed
        }
    }

    var methodDetail: String {
        if result.methodUsed.hasSuffix("_coverage_review") {
            return L10n.Result.detail(.algorithmDetailCoverageReview, in: bundle)
        }
        if result.methodUsed.hasSuffix("_coverage_limited") {
            return L10n.Result.detail(.algorithmDetailCoverageLimited, in: bundle)
        }

        switch result.methodUsed {
        case "weighted_AB", "average_AB":
            return L10n.Result.detail(.algorithmDetailCombined, in: bundle)
        case "A_only":
            return L10n.Result.detail(.algorithmDetailCrown, in: bundle)
        case "B_only":
            return L10n.Result.detail(.algorithmDetailFruitVolume, in: bundle)
        case "fusion_only", "fusion_visual_calibrated":
            return L10n.Result.detail(.algorithmDetailFusion, in: bundle)
        case "tracked_image_visual_calibrated":
            return L10n.Result.detail(.algorithmDetailTrackedImage, in: bundle)
        case "image_visual_calibrated":
            return L10n.Result.detail(.algorithmDetailImage, in: bundle)
        case "cloud_only_calibrated":
            return L10n.Result.detail(.algorithmDetailCloud, in: bundle)
        case "flagged":
            return L10n.Result.detail(.algorithmDetailManualReview, in: bundle)
        case "crown_untrained":
            return L10n.Result.detail(.algorithmDetailCrownUntrained, in: bundle)
        default:
            return L10n.Result.detail(.algorithmDetailDefault, in: bundle)
        }
    }
}
