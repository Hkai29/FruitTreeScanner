import SwiftUI

struct LaunchScreen: View {
    @State private var artworkScale: CGFloat = 1.04
    @State private var artworkOpacity: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Color(red: 0.02, green: 0.07, blue: 0.035)
                    .ignoresSafeArea()

                launchArtwork(proxy: proxy, isLandscape: isLandscape)

                LinearGradient(
                    colors: [
                        Color.black.opacity(isLandscape ? 0.58 : 0.10),
                        Color.clear,
                        Color.black.opacity(isLandscape ? 0.10 : 0.12)
                    ],
                    startPoint: isLandscape ? .leading : .top,
                    endPoint: isLandscape ? .trailing : .bottom
                )
                .ignoresSafeArea()
                .opacity(artworkOpacity)

                launchTitle(isLandscape: isLandscape)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: isLandscape ? .leading : .top
                    )
                    .padding(.top, isLandscape ? 0 : 86)
                    .padding(.leading, isLandscape ? max(40, proxy.safeAreaInsets.leading + 48) : 0)
                    .padding(.trailing, isLandscape ? proxy.size.width * 0.60 : 0)
                    .opacity(artworkOpacity)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                artworkScale = 1.0
                artworkOpacity = 1.0
            }
        }
    }

    @ViewBuilder
    private func launchArtwork(proxy: GeometryProxy, isLandscape: Bool) -> some View {
        if isLandscape {
            Image("LaunchArtwork")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .scaleEffect(1.08)
                .blur(radius: 12)
                .opacity(artworkOpacity * 0.26)
                .ignoresSafeArea()

            Image("LaunchArtwork")
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth: proxy.size.width * 0.64,
                    maxHeight: proxy.size.height - max(34, proxy.safeAreaInsets.bottom + 22)
                )
                .scaleEffect(artworkScale)
                .opacity(artworkOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, max(28, proxy.safeAreaInsets.trailing + 18))
                .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 10))
        } else {
            Image("LaunchArtwork")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .scaleEffect(artworkScale)
                .opacity(artworkOpacity)
                .ignoresSafeArea()
        }
    }

    private func launchTitle(isLandscape: Bool) -> some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: 8) {
            Text("FruitScanner")
                .font(.system(size: isLandscape ? 34 : 32, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            Text("果树 LiDAR 扫描")
                .font(.system(size: isLandscape ? 16 : 15, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
    }
}

#Preview {
    LaunchScreen()
}
