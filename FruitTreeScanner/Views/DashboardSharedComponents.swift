import SwiftUI

struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardSurface(cornerRadius: 10)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}

struct DashboardSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvestLight)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct DashboardFeatureImage: View {
    let name: String
    var accent: Color = Design.Colors.harvest
    var cornerRadius: CGFloat = 9

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 26, height: 3)
                    .padding(8)
                    .opacity(0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct DashboardFeatureHeader: View {
    let imageName: String
    let title: String
    let subtitle: String
    var accent: Color = Design.Colors.harvest

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DashboardFeatureImage(name: imageName, accent: accent, cornerRadius: 10)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
    }
}

struct DashboardToolHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let imageName: String
    let title: String
    let subtitle: String
    var icon: String
    var accent: Color = Design.Colors.harvest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                DashboardFeatureImage(name: imageName, accent: accent)
                    .frame(width: 86, height: 66)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accent)
                        .padding(6)
                        .background(accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.headline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

// MARK: - Mini Icon Badge

struct DashboardMiniIcon: View {
    let icon: String
    var size: CGFloat = 40

    private var radius: CGFloat { size > 36 ? 10 : 8 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: radius)
                .fill(Design.Colors.Dark.bgElevated)

            RoundedRectangle(cornerRadius: radius)
                .stroke(Design.Colors.harvest.opacity(0.18), lineWidth: 1)

            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Design.Colors.harvest, Design.Colors.harvestLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Circle()
                .fill(Design.Colors.harvest.opacity(0.85))
                .frame(width: 5, height: 5)
                .padding(6)
        }
        .frame(width: size, height: size)
    }
}

struct DashboardSheetAction {
    let title: String
    let icon: String
    let action: () -> Void
}

extension View {
    func darkSurface(
        cornerRadius: CGFloat,
        fill: Color = Design.Colors.Dark.bgSurface.opacity(0.96)
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: Design.Shadow.glassShadow.color,
                radius: Design.Shadow.glassShadow.radius,
                y: Design.Shadow.glassShadow.y
            )
    }

    func dashboardSurface(cornerRadius: CGFloat) -> some View {
        darkSurface(cornerRadius: cornerRadius)
    }
}
