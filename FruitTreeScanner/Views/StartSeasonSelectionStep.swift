import SwiftUI

struct Step3_SeasonSelection: View {
    @Binding var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 3,
                totalSteps: 5,
                title: L10n.StartSetup.text(.seasonTitle),
                subtitle: L10n.StartSetup.text(.seasonSubtitle)
            )

            optionList

            StartNoteRow(
                icon: "info.circle",
                text: L10n.StartSetup.text(.seasonNote)
            )
        }
    }

    private var optionList: some View {
        VStack(spacing: 0) {
            SeasonOptionRow(
                icon: "apple.logo",
                title: L10n.StartSetup.text(.seasonMatureTitle),
                subtitle: L10n.StartSetup.text(.seasonMatureSubtitle),
                isSelected: season == .mature,
                color: Design.Colors.forest
            ) {
                season = .mature
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            SeasonOptionRow(
                icon: "leaf.fill",
                title: L10n.StartSetup.text(.seasonOffTitle),
                subtitle: L10n.StartSetup.text(.seasonOffSubtitle),
                isSelected: season == .off,
                color: Design.Colors.harvest,
                isEnabled: false
            ) {
                // 冠层回归完成实测标定后再开放。
            }
        }
        .startSurface(cornerRadius: 10)
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
            icon: icon,
            tint: color,
            isSelected: isSelected,
            action: action
        ) {
            if !isEnabled {
                Text(L10n.StartSetup.text(.seasonCalibrationPending))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
}
