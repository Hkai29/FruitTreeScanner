import SwiftUI

struct ResultConfidencePresentation {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var label: String {
        switch rawValue {
        case "high": return L10n.Result.confidenceHigh
        case "medium": return L10n.Result.confidenceMedium
        case "manual_review": return L10n.Result.confidenceManualReview
        default: return L10n.Result.confidenceLow
        }
    }

    var color: Color {
        switch rawValue {
        case "high": return Design.Colors.forest
        case "medium": return Design.Colors.harvest
        case "manual_review": return Design.Colors.apple
        default: return Design.Colors.slate
        }
    }
}

enum ResultValueFormatter {
    static func finalYieldKg(_ value: Float) -> String {
        String(format: "%.1f", value)
    }

    static func correctionFactor(_ value: Float) -> String {
        String(format: "×%.2f", value)
    }

    static func kilograms(_ value: Float) -> String {
        String(format: "%.2f kg", value)
    }

    static func centimeters(_ value: Float) -> String {
        String(format: "%.1f cm", value)
    }

    static func cubicMeters(_ value: Float) -> String {
        String(format: "%.3f m³", value)
    }

    static func meters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    static func dbscanEps(_ value: Float) -> String {
        String(format: "%.3f m", value)
    }

    static func occlusionK(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

struct ResultActionButtons: View {
    let onDismiss: () -> Void
    let onDismissToHome: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                Text(L10n.Result.continueNext)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Design.Colors.Dark.bgDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Design.Colors.harvest)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button(action: onDismissToHome) {
                HStack(spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(size: 14))
                    Text(L10n.Result.backToHome)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Design.Colors.Dark.bgElevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
    }
}

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

struct ConfidenceBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .cornerRadius(7)
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

struct ResultSummaryPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Design.Colors.Dark.bgElevated.opacity(0.7))
        .cornerRadius(7)
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
