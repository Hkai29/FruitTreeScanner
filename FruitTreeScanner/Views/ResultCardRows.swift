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

struct ResultSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .headline) private var iconFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var titleFontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: iconFontSize))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            Divider()
                .background(Design.Colors.Dark.glassBorder)

            content()
        }
        .padding(15)
        .resultSurface(cornerRadius: 10)
        .padding(.horizontal, 18)
    }
}

struct ResultInfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var valueFontSize: CGFloat = 14

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
            .font(.system(size: labelFontSize))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: valueFontSize, weight: highlight ? .semibold : .medium, design: .monospaced))
            .foregroundColor(highlight ? Design.Colors.forest : Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ResultParameterRow: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = Design.Colors.Dark.textPrimary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var valueFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailFontSize: CGFloat = 12

    private var layoutPolicy: ResultDetailRowLayoutPolicy {
        ResultDetailRowLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            parameterHeading

            Text(detail)
                .font(.system(size: detailFontSize))
                .foregroundColor(Design.Colors.Dark.textMuted)
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
            .font(.system(size: titleFontSize, weight: .medium))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: valueFontSize, weight: .semibold))
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DiagnosticRecommendationRow: View {
    let recommendation: String

    @ScaledMetric(relativeTo: .caption) private var iconFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var recommendationFontSize: CGFloat = 13

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.top, 2)
            Text(recommendation)
                .font(.system(size: recommendationFontSize, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension View {
    func resultSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Design.Colors.Dark.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
    }
}
