// InstrumentEvidence.swift
// 证据等级：把“这条结论能不能用”编码成界面语言。
//
// 重要边界：
//   * 结果页等级来自 `ResultReliabilityPresentation`，那里有真实的 .fused 诊断。
//   * 档案记录只有 confidence 字符串，没有 .fused 诊断，因此记录等级**不声称**
//     “可靠融合”，只说明记录是否完整、是否需要复核。
//   * 复核判定一律复用既有的 `ResultReviewPolicy`，不另立标准。
//   * 本文件只描述显示，不参与任何统计、估产或准入判定。

import SwiftUI

// MARK: - 结果页证据等级

/// 结果页的证据等级。只在拿到真实融合诊断时使用。
enum InstrumentEvidenceTier: Equatable {
    /// 存在 .fused 证据且无异常原因。
    case reliable
    /// 有 .fused 证据，但置信度偏低、来源可靠性不足或存在未映射标签。
    case review
    /// 有 .fused 证据但伴随零产原因等异常。
    case unreliable
    /// 没有任何 .fused 证据，不能给出可靠估产。
    case noEstimate

    /// 线型：可靠=实线，复核=虚线，不可靠=点线，无估产=空心。
    /// 结构与颜色双重编码，色觉差异用户也能分辨等级。
    var markStyle: InstrumentTierMark.Style {
        switch self {
        case .reliable: return .solid
        case .review: return .dashed
        case .unreliable: return .dotted
        case .noEstimate: return .hollow
        }
    }

    var tint: Color {
        switch self {
        case .reliable: return Design.Colors.Workspace.reliable
        case .review: return Design.Colors.Workspace.attention
        case .unreliable: return Design.Colors.Workspace.failure
        case .noEstimate: return Design.Colors.Workspace.failure
        }
    }

    var softTint: Color {
        switch self {
        case .reliable: return Design.Colors.Workspace.reliableSoft
        case .review: return Design.Colors.Workspace.attentionSoft
        case .unreliable: return Design.Colors.Workspace.failureSoft
        case .noEstimate: return Design.Colors.Workspace.failureSoft
        }
    }

    var systemImage: String {
        switch self {
        case .reliable: return "checkmark.seal.fill"
        case .review: return "exclamationmark.circle.fill"
        case .unreliable: return "arrow.triangle.2.circlepath"
        case .noEstimate: return "xmark.octagon.fill"
        }
    }
}

extension ResultReliabilityPresentation {
    /// 与结果页诊断等级保持一致的结构化表达。
    var tier: InstrumentEvidenceTier {
        switch level {
        case .reliable: return .reliable
        case .review: return .review
        case .unreliable: return .unreliable
        case .noReliableEstimate: return .noEstimate
        }
    }
}

// MARK: - 档案记录等级

/// 档案记录等级。
///
/// `ScanFileRecord` 只保存 confidence 与落盘状态，不含 .fused 诊断，
/// 因此这里**不判断**证据是否可靠，只回答“这份记录能不能直接用”。
enum InstrumentRecordTier: Equatable {
    /// 结果已完整保存，且按既有策略无需复核。
    case complete
    /// 结果完整，但按既有策略需要人工复核。
    case review
    /// 结果缺失或损坏，需要恢复。
    case damaged

    var markStyle: InstrumentTierMark.Style {
        switch self {
        case .complete: return .solid
        case .review: return .dashed
        case .damaged: return .dotted
        }
    }

    var tint: Color {
        switch self {
        case .complete: return Design.Colors.Workspace.secondary
        case .review: return Design.Colors.Workspace.attention
        case .damaged: return Design.Colors.Workspace.failure
        }
    }
}

enum InstrumentRecord {
    /// 记录等级。完整性来自 `ScanHistoryRecordPresentation`，
    /// 复核判定来自既有的 `ResultReviewPolicy`，不另立标准。
    static func tier(for record: ScanFileRecord) -> InstrumentRecordTier {
        let integrity = ScanHistoryRecordPresentation(record: record).integrity
        switch integrity {
        case .complete:
            return ResultReviewPolicy.needsReview(record.confidence) ? .review : .complete
        case .incomplete, .invalid:
            return .damaged
        }
    }

    /// 等级对应的文字标签，沿用既有文案。
    static func title(for record: ScanFileRecord) -> String {
        let presentation = ScanHistoryRecordPresentation(record: record)
        switch tier(for: record) {
        case .complete:
            return presentation.statusTitle
        case .review:
            return WorkspaceText.review
        case .damaged:
            return presentation.statusTitle
        }
    }
}
