import SwiftUI

struct ResultSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

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

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: highlight ? .semibold : .medium, design: .monospaced))
                .foregroundColor(highlight ? Design.Colors.forest : Design.Colors.Dark.textPrimary)
        }
    }
}

struct ResultParameterRow: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = Design.Colors.Dark.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                    .multilineTextAlignment(.trailing)
            }

            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(Design.Colors.Dark.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiagnosticRecommendationRow: View {
    let recommendation: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.top, 2)
            Text(recommendation)
                .font(.system(size: 13, weight: .medium))
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
