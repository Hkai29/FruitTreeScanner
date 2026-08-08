import SwiftUI

struct Step3_SeasonSelection: View {
    @Binding var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 3,
                totalSteps: 5,
                title: "估算阶段",
                subtitle: "当前仅开放已具备可靠输入的成熟期估算。"
            )

            optionList

            StartNoteRow(
                icon: "info.circle",
                text: "非成熟期冠层路线需先用真实称重数据完成模型标定，避免输出缺乏依据的产量。"
            )
        }
    }

    private var optionList: some View {
        VStack(spacing: 0) {
            SeasonOptionRow(
                icon: "apple.logo",
                title: "成熟期",
                subtitle: "RGB + LiDAR 果实融合估算",
                isSelected: season == .mature,
                color: Design.Colors.forest
            ) {
                season = .mature
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            SeasonOptionRow(
                icon: "leaf.fill",
                title: "非成熟期（待标定）",
                subtitle: "冠层回归尚缺实测系数，暂不可选择",
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
                Text("待标定")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
}
