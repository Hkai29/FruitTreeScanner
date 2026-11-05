// StartSeasonSelectionStep.swift
// 第 3 步：估算阶段。
//
// 只列出 Season 的真实取值；未完成实测标定的阶段保持不可选，
// 与既有业务门一致。

import SwiftUI

struct Step3_SeasonSelection: View {
    @Binding var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstrumentSectionLabel(title: L10n.StartSetup.text(.seasonTitle))

            optionList

            StartNoteRow(
                icon: "info.circle",
                text: L10n.StartSetup.text(.seasonNote),
                tone: .neutral
            )
        }
    }

    private var optionList: some View {
        InstrumentRowGroup {
            SeasonOptionRow(
                icon: "sun.max",
                title: L10n.StartSetup.text(.seasonMatureTitle),
                subtitle: L10n.StartSetup.text(.seasonMatureSubtitle),
                isSelected: season == .mature,
                color: Design.Colors.Workspace.accent
            ) {
                season = .mature
            }

            DividerLine(inset: 0)

            SeasonOptionRow(
                icon: "leaf.fill",
                title: L10n.StartSetup.text(.seasonOffTitle),
                subtitle: L10n.StartSetup.text(.seasonOffSubtitle),
                isSelected: season == .off,
                color: Design.Colors.Workspace.accent,
                isEnabled: false
            ) {
                // 冠层回归完成实测标定后再开放。
            }
        }
    }
}

struct SeasonOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        StartSelectionRow(
            title: title,
            subtitle: subtitle,
            systemImage: icon,
            iconTint: color,
            isSelected: isSelected,
            action: action
        ) {
            if !isEnabled {
                Text(L10n.StartSetup.text(.seasonCalibrationPending))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}
