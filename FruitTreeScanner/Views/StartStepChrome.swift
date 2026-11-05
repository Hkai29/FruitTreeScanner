// StartStepChrome.swift
// 步骤页共用的小组件：标题、说明、空状态、选择行。
//
// 这些组件只负责呈现，交互与数据仍由各步骤页负责。

import SwiftUI

// MARK: - 步骤标题

/// 步骤页标题：图标 + 标题 + 说明。页面级标题区。
struct StartStepHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let step: Int
    let totalSteps: Int
    let title: String
    let subtitle: String
    var systemImage: String? = nil

    private var layoutPolicy: StartFlowChromeLayoutPolicy {
        StartFlowChromeLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        Group {
            if layoutPolicy.stacksVertically, let systemImage {
                VStack(alignment: .leading, spacing: 10) {
                    icon(systemImage)
                    copy
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let systemImage {
                        icon(systemImage)
                    }
                    copy
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .default).weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Design.Colors.Workspace.accent)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.accentSoft)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - 说明

/// 说明条的语气。
enum StartNoteTone {
    case neutral
    case accent
    case attention
    case failure
    case reliable
}

/// 说明条：一条提示 + 图标。
struct StartNoteRow: View {
    let icon: String
    let text: String
    var tone: StartNoteTone = .neutral

    var body: some View {
        switch tone {
        case .neutral:
            InstrumentNotice(message: text, tone: .neutral, systemImage: icon)
        case .accent:
            InstrumentNotice(message: text, tone: .accent, systemImage: icon)
        case .attention:
            InstrumentNotice(message: text, tone: .attention, systemImage: icon)
        case .failure:
            InstrumentNotice(message: text, tone: .failure, systemImage: icon)
        case .reliable:
            InstrumentNotice(message: text, tone: .reliable, systemImage: icon)
        }
    }
}

// MARK: - 空状态

/// 空状态 + 一个明确的创建动作。
struct StartEmptyAction: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    /// 地块空状态用测区空板（测绘网格），其余用通用空状态。
    var usesSurveyPlate: Bool = false
    let action: () -> Void

    var body: some View {
        if usesSurveyPlate {
            InstrumentSurveyPlate {
                VStack(alignment: .leading, spacing: 12) {
                    copy
                    StartCreateButton(title: buttonTitle, action: action)
                }
                .padding(16)
            }
        } else {
            InstrumentEmptyState(systemImage: icon, title: title, message: message) {
                StartCreateButton(title: buttonTitle, action: action)
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.headline, design: .default).weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 空状态里的创建动作：描边按钮，与工作台的次操作一致。
struct StartCreateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(Design.Colors.Workspace.accent)
            .frame(maxWidth: .infinity, minHeight: Design.Touch.minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - 布局策略

/// 步骤内容在辅助功能字号下改为竖排，避免挤压。
struct StartStepContentLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let arrangement: Arrangement
    let minimumControlHeight: CGFloat

    init(isAccessibilitySize: Bool) {
        arrangement = isAccessibilitySize ? .vertical : .horizontal
        minimumControlHeight = Design.Touch.minimumHeight
    }
}

// MARK: - 选择行

/// 可选择的行：标题 + 说明 + 尾部状态。
struct StartSelectionRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var iconTint: Color = Design.Colors.Workspace.secondary
    /// 标识符（树号、地块名）使用等宽字形。
    var isMonospacedTitle: Bool = false
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                switch layoutPolicy.arrangement {
                case .horizontal:
                    HStack(alignment: .center, spacing: 12) {
                        description
                        Spacer(minLength: 8)
                        trailing
                    }
                case .vertical:
                    VStack(alignment: .leading, spacing: 8) {
                        description
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            trailing
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(minHeight: layoutPolicy.minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var description: some View {
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(iconTint)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(isMonospacedTitle
                          ? .system(.subheadline, design: .monospaced).weight(.semibold)
                          : .system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 10) {
            accessory()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected
                                 ? Design.Colors.Workspace.accent
                                 : Design.Colors.Workspace.faint)
                .accessibilityHidden(true)
        }
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}

extension View {
    func startSurface(cornerRadius: CGFloat) -> some View {
        workspaceSurface(cornerRadius: cornerRadius)
    }
}
