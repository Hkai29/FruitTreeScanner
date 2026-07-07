import SwiftUI

struct LaunchScreen: View {
    @State private var contentScale: CGFloat = 1.04
    @State private var contentOpacity: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                launchBackground(size: proxy.size)
                launchFruitTreeBranches(size: proxy.size)
                launchContent(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                contentScale = 1
                contentOpacity = 1
            }
        }
    }

    private func launchBackground(size: CGSize) -> some View {
        let launchBase = Color(hex: "101A10")

        return ZStack {
            launchBase
                .ignoresSafeArea()

            launchEdgeBands(size: size)

            RadialGradient(
                colors: [
                    Design.Colors.forest.opacity(0.28),
                    launchBase.opacity(0.96)
                ],
                center: .center,
                startRadius: 20,
                endRadius: max(size.width, size.height) * 0.72
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Design.Colors.forest.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func launchEdgeBands(size: CGSize) -> some View {
        let bandHeight = min(max(min(size.width, size.height) * 0.105, 52), 88)
        let bandColor = Color(hex: "0B2510")

        return VStack(spacing: 0) {
            bandColor
                .frame(height: bandHeight)

            Spacer(minLength: 0)

            bandColor
                .frame(height: bandHeight)
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func launchFruitTreeBranches(size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let horizontalBleed = min(size.width * 0.085, isLandscape ? 110 : 78)
        let verticalBleed = min(size.height * 0.045, isLandscape ? 42 : 54)
        let cornerWidth = min(
            size.width * (isLandscape ? 0.48 : 0.72),
            isLandscape ? 660 : 560
        )
        let topHeight = min(
            size.height * (isLandscape ? 0.64 : 0.46),
            isLandscape ? 520 : 620
        )
        let bottomHeight = min(
            size.height * (isLandscape ? 0.72 : 0.50),
            isLandscape ? 560 : 660
        )

        return ZStack {
            launchFruitBranch(
                "LaunchFruitTopLeft",
                width: cornerWidth,
                height: topHeight,
                alignment: .topLeading,
                offset: CGSize(width: -horizontalBleed, height: -verticalBleed)
            )
            launchFruitBranch(
                "LaunchFruitTopRight",
                width: cornerWidth,
                height: topHeight,
                alignment: .topTrailing,
                offset: CGSize(width: horizontalBleed, height: -verticalBleed)
            )
            launchFruitBranch(
                "LaunchFruitBottomLeft",
                width: cornerWidth,
                height: bottomHeight,
                alignment: .bottomLeading,
                offset: CGSize(width: -horizontalBleed, height: verticalBleed)
            )
            launchFruitBranch(
                "LaunchFruitBottomRight",
                width: cornerWidth,
                height: bottomHeight,
                alignment: .bottomTrailing,
                offset: CGSize(width: horizontalBleed, height: verticalBleed)
            )
        }
        .frame(width: size.width, height: size.height)
        .saturation(0.96)
        .contrast(1.06)
        .opacity(0.9)
        .allowsHitTesting(false)
    }

    private func launchFruitBranch(
        _ imageName: String,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment,
        offset: CGSize
    ) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height, alignment: alignment)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func launchContent(size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let shortSide = min(size.width, size.height)
        let iconSize = min(
            max(shortSide * (isLandscape ? 0.23 : 0.27), 104),
            isLandscape ? 150 : 156
        )
        let titleSize = min(
            max(shortSide * (isLandscape ? 0.052 : 0.084), 34),
            isLandscape ? 50 : 54
        )

        return VStack(spacing: isLandscape ? 16 : 18) {
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.215, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

            Text(Design.Brand.productName)
                .font(.custom("AvenirNext-DemiBoldItalic", size: titleSize))
                .tracking(isLandscape ? 1.4 : 1.8)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Design.Colors.harvestLight,
                            Design.Colors.Dark.textPrimary,
                            Design.Colors.harvest
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .shadow(color: Design.Colors.harvest.opacity(0.26), radius: 11, y: 1)
                .shadow(color: .black.opacity(0.36), radius: 8, y: 4)
                .accessibilityLabel(Design.Brand.productName)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: isLandscape ? 0 : -10)
        .opacity(contentOpacity)
        .scaleEffect(contentScale)
    }
}

#Preview("Portrait") {
    LaunchScreen()
}

#Preview("Landscape") {
    LaunchScreen()
        .frame(width: 812, height: 375)
}
