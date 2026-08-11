import SwiftUI

struct ConfidenceBadge: View {
    let label: String
    let color: Color

    @ScaledMetric(relativeTo: .caption) private var labelFontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .cornerRadius(7)
    }
}

struct ResultSummaryPill: View {
    let label: String
    let value: String
    var allowsValueWrapping = false

    @ScaledMetric(relativeTo: .caption2) private var labelFontSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var valueFontSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: labelFontSize, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(allowsValueWrapping ? nil : 1)
                .minimumScaleFactor(allowsValueWrapping ? 1 : 0.7)
                .fixedSize(horizontal: false, vertical: allowsValueWrapping)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Design.Colors.Dark.bgElevated.opacity(0.7))
        .cornerRadius(7)
    }
}
