// InstrumentForms.swift
// 表单、筛选与进度组件。
//
// 列表用原生 List 承载行为（选择、删除、编辑），
// 外观由本文件统一，避免每个页面各画一套。

import SwiftUI

// MARK: - 列表样式

extension View {
    /// 统一的原生列表外观：纸面底、无默认分组背景、整行可点。
    func instrumentListStyle() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.Workspace.background)
            .foregroundColor(Design.Colors.Workspace.ink)
            .tint(Design.Colors.Workspace.accent)
    }

    /// 分组段：带小标签的标题条 + 内容。
    func instrumentSectionHeader(_ title: String) -> some View {
        self
            .font(.system(.caption2, design: .default).weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundColor(Design.Colors.Workspace.muted)
            .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - 表单字段

/// 表单字段：左标签 + 右控件，中间以发丝线分隔。
struct InstrumentFormRow<Content: View>: View {
    let label: String
    var subtitle: String? = nil
    @ViewBuilder let control: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(minHeight: Design.Touch.minimumHeight)
    }
}

/// 带标签的输入框。
struct InstrumentTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isMonospaced: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .font(isMonospaced
                  ? .system(.subheadline, design: .monospaced)
                  : .system(.subheadline, design: .default))
            .foregroundColor(Design.Colors.Workspace.ink)
            .multilineTextAlignment(.trailing)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(minHeight: Design.Touch.minimumHeight)
            .background(Design.Colors.Workspace.inset, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
    }
}

// MARK: - 筛选片

/// 筛选片：可选中的小标签。选中时用信号青实底，未选中用描边。
struct InstrumentChip: View {
    let title: String
    let isSelected: Bool
    var count: Int? = nil
    /// 可选的无障碍标识。缺省时用 `chip.<标题>`，便于自动化核验触达区域。
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                if let count {
                    Text("\(count)")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : Design.Colors.Workspace.muted)
                }
            }
            .foregroundColor(isSelected ? .white : Design.Colors.Workspace.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(isSelected ? Design.Colors.Workspace.accent : Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Design.Colors.Workspace.line,
                        lineWidth: 1
                    )
            )
            // 视觉高度 32pt，实际触达区域 44pt：野外戴手套操作必须够得着。
            .frame(minHeight: Design.Touch.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "chip.\(title)")
    }
}

// MARK: - 进度

/// 分段进度条。用于导入、导出等有确定进度的任务。
struct InstrumentProgress: View {
    let progress: Double
    var tint: Color = Design.Colors.Workspace.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Design.Colors.Workspace.inset)
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(progress.clamped(to: 0...1)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - 面板标题栏

/// 面板内的标题条（工具页/表单页顶部）。
struct InstrumentSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
    }
}

// MARK: - 状态提示条

/// 状态提示条：一条消息 + 可选操作。
struct InstrumentNotice<Accessory: View>: View {
    enum Tone { case neutral, accent, attention, failure, reliable }

    let message: String
    var tone: Tone = .neutral
    var systemImage: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    init(
        message: String,
        tone: Tone = .neutral,
        systemImage: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.message = message
        self.tone = tone
        self.systemImage = systemImage
        self.accessory = accessory
    }

    private var tint: Color {
        switch tone {
        case .neutral: return Design.Colors.Workspace.secondary
        case .accent: return Design.Colors.Workspace.accent
        case .attention: return Design.Colors.Workspace.attention
        case .failure: return Design.Colors.Workspace.failure
        case .reliable: return Design.Colors.Workspace.reliable
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Design.Colors.Workspace.inset.opacity(0.6)
        case .accent: return Design.Colors.Workspace.accentSoft
        case .attention: return Design.Colors.Workspace.attentionSoft
        case .failure: return Design.Colors.Workspace.failureSoft
        case .reliable: return Design.Colors.Workspace.reliableSoft
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.footnote)
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
    }
}
