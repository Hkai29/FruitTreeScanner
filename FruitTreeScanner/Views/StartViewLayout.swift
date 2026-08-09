import SwiftUI

struct StartFlowToolHeaderContent {
    let imageName: String
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
}

struct StartViewLayout<StepContent: View>: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let canGoNext: Bool
    let isLaunchingScan: Bool
    let header: StartFlowToolHeaderContent
    let onCancel: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder let stepContent: () -> StepContent

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && proxy.size.width >= 760

            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                if isLandscape {
                    landscapeContent(width: proxy.size.width)
                } else {
                    portraitContent
                }
            }
        }
    }

    private var portraitContent: some View {
        VStack(spacing: 0) {
            topNavigation

            StepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, Design.Space.xs)

            ScrollView {
                VStack(spacing: Design.Space.lg) {
                    stepToolHeader

                    stepContent()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Design.Space.lg)
                .padding(.top, Design.Space.lg)
                .padding(.bottom, Design.Space.xl)
            }
            .id(currentStep)
            .scrollDismissesKeyboard(.interactively)

            bottomNavigation
        }
    }

    private func landscapeContent(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            topNavigation

            HStack(alignment: .top, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: Design.Space.lg) {
                    stepToolHeader

                    StepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.horizontal, -Design.Space.lg)

                    Spacer(minLength: Design.Space.sm)
                }
                .frame(width: min(330, width * 0.34), alignment: .topLeading)

                ScrollView {
                    stepContent()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, Design.Space.xl)
                }
                .id(currentStep)
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.top, Design.Space.md)

            bottomNavigation
        }
    }

    private var stepToolHeader: some View {
        DashboardToolHeader(
            imageName: header.imageName,
            title: header.title,
            subtitle: header.subtitle,
            icon: header.icon,
            accent: header.accent
        )
    }

    private var bottomNavigation: some View {
        StepNavigationBar(
            currentStep: currentStep,
            totalSteps: totalSteps,
            canGoBack: canGoBack,
            canGoNext: canGoNext,
            isLaunching: isLaunchingScan,
            onBack: onBack,
            onNext: onNext
        )
        .padding(.horizontal, Design.Space.lg)
        .padding(.bottom, Design.Space.lg)
    }

    private var topNavigation: some View {
        HStack {
            Button("取消", action: onCancel)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.Colors.harvest)
                .accessibilityIdentifier("start.cancel")

            Spacer()

            Text("新建扫描")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            Text("取消")
                .font(.system(size: 16, weight: .medium))
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
    }
}
