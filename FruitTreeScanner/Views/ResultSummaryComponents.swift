// ResultSummaryComponents.swift
// 结果页头部：证据等级 + 估产读数 + 关键计数。
//
// 可靠性等级来自 ResultReliabilityPresentation（真实 .fused 诊断），
// 以竖栏的线型（实线/虚线/点线/空心）结构化表达，颜色只作强化。

import SwiftUI

struct ResultSummaryLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let headerArrangement: Arrangement
    let primaryMetricArrangement: Arrangement
    let summaryColumnCount: Int
    let allowsPillValueWrapping: Bool

    init(isAccessibilitySize: Bool) {
        headerArrangement = isAccessibilitySize ? .vertical : .horizontal
        primaryMetricArrangement = isAccessibilitySize ? .vertical : .horizontal
        summaryColumnCount = isAccessibilitySize ? 1 : 3
        allowsPillValueWrapping = isAccessibilitySize
    }
}

struct ResultSummaryHeader: View {
    let treeID: String
    let result: YieldResult

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var treeIDFontSize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 52

    private var confidencePresentation: ResultConfidencePresentation {
        ResultConfidencePresentation(result.confidence)
    }

    private var reliabilityPresentation: ResultReliabilityPresentation {
        ResultReliabilityPresentation(result: result)
    }

    private var layoutPolicy: ResultSummaryLayoutPolicy {
        ResultSummaryLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var fusedEvidenceCount: Int {
        max(
            result.diagnostics.fusedValidationCount,
            result.validatedFruits.filter { $0.source == ValidationSource.fused.rawValue }.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerContent

            // 可靠性先于产量：先回答"这条结论能不能用"，再回答"是多少"。
            ResultReliabilityPanel(presentation: reliabilityPresentation)

            ResultPrimaryMetric(
                title: L10n.Result.yieldTitle,
                value: ResultValueFormatter.finalYieldKg(result.yieldFinalKg),
                unit: "kg",
                color: Design.Colors.Workspace.ink,
                arrangement: layoutPolicy.primaryMetricArrangement,
                valueFontSize: valueFontSize
            )

            InstrumentStatStrip {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 14),
                        count: layoutPolicy.summaryColumnCount
                    ),
                    spacing: 14
                ) {
                    ResultSummaryPill(
                        label: NSLocalizedString("workspace.corrected_count", value: "校正果数", comment: ""),
                        value: "\(result.nLidar)",
                        allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                    )
                    ResultSummaryPill(
                        label: L10n.Result.pointCloud,
                        value: result.pointCloudSize > 0 ? result.pointCloudSize.formatted() : "--",
                        allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                    )
                    ResultSummaryPill(
                        label: NSLocalizedString("workspace.fused_evidence", value: "融合证据", comment: ""),
                        value: "\(fusedEvidenceCount)",
                        allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                    )
                }
            }

            if !result.note.isEmpty {
                Text(result.note)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        switch layoutPolicy.headerArrangement {
        case .horizontal:
            HStack(alignment: .center, spacing: 12) {
                titleContent
                Spacer()
                confidenceBadge
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 10) {
                titleContent
                confidenceBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.Result.scanResult)
                .instrumentLabel()
            Text(treeID)
                .font(.system(size: treeIDFontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidenceBadge: some View {
        ConfidenceBadge(
            label: confidencePresentation.label,
            color: confidencePresentation.color
        )
    }
}

// MARK: - 可靠性面板

/// 可靠性面板：以竖栏线型表达证据等级，附建议动作与诊断提示。
struct ResultReliabilityPanel: View {
    let presentation: ResultReliabilityPresentation

    private var tier: InstrumentEvidenceTier { presentation.tier }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InstrumentTierRail(style: tier.markStyle, tint: tier.tint)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Label(presentation.recommendedAction, systemImage: "arrow.turn.down.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(tier.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.summary)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let diagnosticHint = presentation.diagnosticHint {
                    Text(diagnosticHint)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(tier.softTint, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 主读数

struct ResultPrimaryMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let arrangement: ResultSummaryLayoutPolicy.Arrangement
    var valueFontSize: CGFloat = 52

    @ViewBuilder
    var body: some View {
        switch arrangement {
        case .horizontal:
            VStack(alignment: .leading, spacing: 6) {
                titleText
                valueContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .vertical:
            VStack(alignment: .leading, spacing: 4) {
                titleText
                verticalValueContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(title)
            .instrumentLabel()
    }

    private var valueContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            valueText
            unitText
        }
        .accessibilityElement(children: .combine)
    }

    private var verticalValueContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            valueText
            unitText
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: valueFontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unitText: some View {
        Text(unit)
            .font(.title3.weight(.medium))
            .foregroundColor(Design.Colors.Workspace.secondary)
    }
}
