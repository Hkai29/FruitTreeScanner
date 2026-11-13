// InstrumentComponents.swift
// 仪器组件库：果树三维测量专用的一套原生组件。
//
// 这些组件承载“证据 / 读数 / 空间”三类信息，不做装饰。
// 任何页面都可直接组合它们，以保持全应用语气一致。

import SwiftUI

// MARK: - 1. 分区标签

/// 仪器式分区标签：左侧小字标签，右侧可选操作。
struct InstrumentSectionLabel: View {
    let title: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .instrumentLabel()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 2. 仪表面板

/// 带标签条的面板。深色画布上的 HUD 也复用同一结构。
struct InstrumentPanel<Content: View>: View {
    var label: String? = nil
    var systemImage: String? = nil
    var trailing: AnyView? = nil
    var tone: Tone = .neutral
    var fill: Color = Design.Colors.Workspace.surface
    var borderColor: Color = Design.Colors.Workspace.line
    @ViewBuilder let content: () -> Content

    enum Tone { case neutral, accent, attention, failure, reliable }

    private var labelTint: Color {
        switch tone {
        case .neutral: return Design.Colors.Workspace.secondary
        case .accent: return Design.Colors.Workspace.accent
        case .attention: return Design.Colors.Workspace.attention
        case .failure: return Design.Colors.Workspace.failure
        case .reliable: return Design.Colors.Workspace.reliable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if label != nil || trailing != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(labelTint)
                    }
                    if let label {
                        Text(label)
                            .instrumentLabel()
                            .foregroundColor(labelTint)
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(toneBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(borderColor).frame(height: 0.5)
                }
            }
            content()
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder private var toneBackground: some View {
        switch tone {
        case .neutral:
            Design.Colors.Workspace.inset.opacity(0.55)
        case .accent:
            Design.Colors.Workspace.accentSoft
        case .attention:
            Design.Colors.Workspace.attentionSoft
        case .failure:
            Design.Colors.Workspace.failureSoft
        case .reliable:
            Design.Colors.Workspace.reliableSoft
        }
    }
}

// MARK: - 3. 读数

/// 一个测量读数：标签 + 数字 + 单位。数字使用等宽字形以便纵向对齐。
struct InstrumentDatum: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = Design.Colors.Workspace.ink
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .instrumentLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                if let unit {
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
    }
}

/// 紧凑读数：用于密集列表中的数值。
struct InstrumentInlineDatum: View {
    let label: String
    let value: String
    var tint: Color = Design.Colors.Workspace.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(tint)
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - 4. 分段电平表

/// 分段电平表。用于覆盖度、置信度、证据质量等 0–1 读数。
/// 分段而不是连续进度条，读数更接近仪器的电平显示。
struct InstrumentMeter: View {
    let value: Double
    var segments: Int = 16
    var tint: Color = Design.Colors.Workspace.accent
    var trackColor: Color = Design.Colors.Workspace.line
    var height: CGFloat = 6
    var cornerRadius: CGFloat = 1.5

    private var filledSegments: Int {
        guard value.isFinite else { return 0 }
        return max(0, min(segments, Int((value * Double(segments)).rounded(.up))))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(index < filledSegments ? tint : trackColor)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 带标签的电平表。
struct InstrumentMeterRow: View {
    let label: String
    let value: Double
    var displayValue: String? = nil
    var tint: Color = Design.Colors.Workspace.accent
    var segments: Int = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .instrumentLabel()
                Spacer(minLength: 8)
                Text(displayValue ?? String(format: "%.0f%%", (value * 100).clamped(to: 0...1) * 100))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.secondary)
            }
            InstrumentMeter(value: value, segments: segments, tint: tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(displayValue ?? "\(Int((value * 100).clamped(to: 0...1) * 100))%")
    }
}

// MARK: - 5. 标识符

/// 等宽标识符：树号、地块代码、时间戳。
struct InstrumentIdentifier: View {
    let text: String
    var tint: Color = Design.Colors.Workspace.ink
    var background: Color = Design.Colors.Workspace.inset

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
    }
}

// MARK: - 6. 证据等级标记

/// 证据等级的**结构性**编码：靠线的样式区分可靠度，而不是只靠颜色。
///
/// 可靠 = 实线；待复核 = 虚线；不可靠 = 点线；无可靠估产 = 空心。
/// 颜色只做强化，因此色觉差异用户也能分辨等级。
struct InstrumentTierMark: View {
    enum Style: Equatable {
        case solid, dashed, dotted, hollow
    }

    let style: Style
    var tint: Color = Design.Colors.Workspace.secondary
    var height: CGFloat = 26
    var width: CGFloat = 3

    var body: some View {
        Group {
            switch style {
            case .solid:
                Capsule().fill(tint)
            case .dashed:
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(tint)
                    }
                }
            case .dotted:
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(tint)
                            .frame(height: width)
                    }
                }
            case .hollow:
                Capsule().stroke(tint, lineWidth: 1.5)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// 证据等级徽标：结构标记 + 文字，颜色只作强化。
struct InstrumentTierBadge: View {
    let title: String
    let style: InstrumentTierMark.Style
    var tint: Color = Design.Colors.Workspace.secondary

    var body: some View {
        HStack(spacing: 6) {
            InstrumentTierMark(style: style, tint: tint, height: 12, width: 3)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// 证据等级竖栏：随内容高度伸展的等级线。
/// 与 `InstrumentTierMark` 使用同一套线型编码，只是可以拉满高度。
struct InstrumentTierRail: View {
    let style: InstrumentTierMark.Style
    var tint: Color = Design.Colors.Workspace.secondary
    var width: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let x = (size.width - width) / 2
            switch style {
            case .solid:
                context.fill(
                    Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                    with: .color(tint)
                )
            case .dashed:
                let gap: CGFloat = 5
                let segment = max(2, (size.height - gap * 2) / 3)
                for index in 0..<3 {
                    let y = CGFloat(index) * (segment + gap)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: width, height: min(segment, size.height - y))),
                        with: .color(tint)
                    )
                }
            case .dotted:
                let gap: CGFloat = 4
                let segment = max(2, (size.height - gap * 4) / 5)
                for index in 0..<5 {
                    let y = CGFloat(index) * (segment + gap)
                    guard y < size.height else { break }
                    context.fill(
                        Path(CGRect(x: x, y: y, width: width, height: min(segment, size.height - y))),
                        with: .color(tint)
                    )
                }
            case .hollow:
                context.stroke(
                    Path(CGRect(x: x + 0.75, y: 0.75, width: max(0, width - 1.5), height: max(0, size.height - 1.5))),
                    with: .color(tint),
                    lineWidth: 1.5
                )
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

// MARK: - 7. 行

/// 列表行：标签 + 值 + 可选箭头。行间以发丝线分隔。
struct InstrumentRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
            accessory()
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// 行尾箭头。
struct InstrumentChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Design.Colors.Workspace.faint)
            .accessibilityHidden(true)
    }
}

/// 分隔的列表容器：白底 + 内部发丝线。
struct InstrumentRowGroup<Content: View>: View {
    var inset: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, inset)
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

// MARK: - 8. 空状态

/// 统一空状态：方框图标 + 标题 + 说明 + 可选操作。
struct InstrumentEmptyState<Accessory: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    init(
        systemImage: String,
        title: String,
        message: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Design.Colors.Workspace.accent)
                .frame(width: 40, height: 40)
                .background(Design.Colors.Workspace.accentSoft, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

// MARK: - 9. 统计条

/// 横向读数条：多个读数等宽排列，以竖线分隔。
struct InstrumentStatStrip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
    }
}

// MARK: - 10. 工具按钮

/// 工具条上的方形图标按钮。
struct InstrumentToolButton: View {
    let systemImage: String
    let label: String
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? .white : Design.Colors.Workspace.ink)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(isActive ? Design.Colors.Workspace.accent : Design.Colors.Workspace.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .stroke(
                            isActive ? Color.clear : Design.Colors.Workspace.line,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - 11. 分段控件

/// 仪器式分段控件：方角、有边框、与页面同色系。
struct InstrumentSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(
                            selection == option.value
                                ? Design.Colors.Workspace.ink
                                : Design.Colors.Workspace.muted
                        )
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            selection == option.value
                                ? Design.Colors.Workspace.surface
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                if index < options.count - 1 {
                    Rectangle()
                        .fill(Design.Colors.Workspace.line)
                        .frame(width: 0.5)
                }
            }
        }
        .background(Design.Colors.Workspace.inset, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

// MARK: - 12. 尺度示意

/// 尺度示意图：按**统一比例**画出的范围矩形 + 比例尺。
///
/// 矩形的长宽比就是真实的宽高比，比例尺与矩形使用同一个比例，
/// 因此读数可以直接对照。它表达的是被测量的范围（外接尺寸），
/// 不是任何被假设的树形轮廓。
struct InstrumentExtentDiagram: View {
    let widthMeters: CGFloat
    let heightMeters: CGFloat
    var tint: Color = Design.Colors.Workspace.accent
    var showsScaleBar: Bool = true

    private var isValid: Bool {
        widthMeters > 0 && heightMeters > 0 && widthMeters.isFinite && heightMeters.isFinite
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if !isValid {
                EmptyView()
            } else {
                let inset: CGFloat = 4
                let available = CGSize(
                    width: max(1, size.width - inset * 2),
                    height: max(1, size.height - inset * 2)
                )
                // 统一比例：取宽、高两个方向中较紧的一边，二者共用同一比例。
                let scale = min(
                    available.width / widthMeters,
                    available.height / heightMeters
                )
                let boxWidth = widthMeters * scale
                let boxHeight = heightMeters * scale
                let originX = (size.width - boxWidth) / 2
                let originY = size.height - boxHeight

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(tint.opacity(0.10))
                    Rectangle()
                        .stroke(tint.opacity(0.65), lineWidth: 1)
                }
                .frame(width: boxWidth, height: boxHeight)
                .position(x: originX + boxWidth / 2, y: originY + boxHeight / 2)

                if showsScaleBar, let bar = Self.scaleBar(
                    meters: widthMeters,
                    pointsPerMeter: scale,
                    maxPoints: available.width
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        Rectangle()
                            .fill(tint.opacity(0.75))
                            .frame(width: bar.points, height: 1)
                        Text(bar.label)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(tint.opacity(0.85))
                    }
                    .position(x: originX, y: max(6, originY - 8))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 选取一个"整齐"的尺长（0.1/0.2/0.5/1/2/5…），在统一比例下绘制。
    private static func scaleBar(
        meters: CGFloat,
        pointsPerMeter: CGFloat,
        maxPoints: CGFloat
    ) -> (points: CGFloat, label: String)? {
        let candidates: [CGFloat] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]
        let usable = min(maxPoints, meters) * 0.6
        guard usable > 0 else { return nil }
        let chosen = candidates.last { $0 * pointsPerMeter <= usable } ?? candidates.first
        guard let chosen else { return nil }
        let points = chosen * pointsPerMeter
        guard points >= 6 else { return nil }
        let label = chosen < 1
            ? String(format: "%.1f m", chosen)
            : String(format: "%.0f m", chosen)
        return (points, label)
    }
}

// MARK: - 13. 页面标题

/// 页面标题区：标题 + 副标题 + 可选尾部操作。
struct InstrumentPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title2, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

// MARK: - 14. 暗色面板

/// 深色画布上的面板，与浅色 `InstrumentPanel` 结构一致。
struct InstrumentDarkPanel<Content: View>: View {
    var label: String? = nil
    var systemImage: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.glow)
                    }
                    Text(label)
                        .font(.system(.caption2, design: .default).weight(.semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Design.Colors.Dark.glassBorder).frame(height: 0.5)
                }
            }
            content().padding(12)
        }
        .background(Design.Colors.Dark.bgSurface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - 15. 小工具

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
