// ResultCardRows.swift
// 结果页的分段与行。以小标签 + 发丝线分段，不用白色卡片套白色卡片。

import SwiftUI

struct ResultDetailRowLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let arrangement: Arrangement

    init(isAccessibilitySize: Bool) {
        arrangement = isAccessibilitySize ? .vertical : .horizontal
    }
}

/// 结果页的一个分段：小标签标题 + 发丝线 + 内容。
struct ResultSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .accessibilityHidden(true)
                Text(title)
                    .instrumentLabel()
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
            }
            .padding(.bottom, 2)

            content()
        }
    }
}

struct ResultInfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layoutPolicy: ResultDetailRowLayoutPolicy {
        ResultDetailRowLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    @ViewBuilder
    var body: some View {
        switch layoutPolicy.arrangement {
        case .horizontal:
            HStack(alignment: .firstTextBaseline) {
                labelText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 4) {
                labelText
                valueText
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(highlight ? .semibold : .regular))
            .monospacedDigit()
            .foregroundColor(Design.Colors.Workspace.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ResultParameterRow: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = Design.Colors.Workspace.ink

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layoutPolicy: ResultDetailRowLayoutPolicy {
        ResultDetailRowLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            parameterHeading

            Text(detail)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var parameterHeading: some View {
        switch layoutPolicy.arrangement {
        case .horizontal:
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 3) {
                titleText
                valueText
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DiagnosticRecommendationRow: View {
    let recommendation: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(recommendation)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension View {
    func resultSurface(cornerRadius: CGFloat) -> some View {
        workspaceSurface(cornerRadius: cornerRadius)
    }
}
