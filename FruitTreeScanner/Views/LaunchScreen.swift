import SwiftUI

struct LaunchScreen: View {
    @State private var artworkScale: CGFloat = 1.04
    @State private var artworkOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.07, blue: 0.035)
                .ignoresSafeArea()

            GeometryReader { proxy in
                Image("LaunchArtwork")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .scaleEffect(artworkScale)
                    .opacity(artworkOpacity)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.clear,
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .opacity(artworkOpacity)
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("FruitScanner")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                Text("果树 LiDAR 扫描")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Spacer()
            }
            .padding(.top, 86)
            .opacity(artworkOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                artworkScale = 1.0
                artworkOpacity = 1.0
            }
        }
    }
}

#Preview {
    LaunchScreen()
}
