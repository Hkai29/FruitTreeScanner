// LaunchScreen.swift
// 冷启动页 — 简洁专业版

import SwiftUI

struct LaunchScreen: View {
    @State private var treeScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.98, green: 0.973, blue: 0.961)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Tree icon with entrance animation
                TreeIconView()
                    .frame(width: 120, height: 140)
                    .scaleEffect(treeScale)
                    .opacity(contentOpacity)

                // App name
                VStack(spacing: 6) {
                    Text("FruitScanner")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(red: 0.24, green: 0.42, blue: 0.36))

                    Text("果树 LiDAR 产量估算")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.54, green: 0.53, blue: 0.52))
                }
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                treeScale = 1.0
                contentOpacity = 1.0
            }
        }
    }
}

// MARK: - Tree Icon View
struct TreeIconView: View {
    var body: some View {
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color(red: 0.24, green: 0.42, blue: 0.36).opacity(0.12))
                .frame(width: 80, height: 14)
                .offset(y: 60)

            // Tree body
            VStack(spacing: 0) {
                // Canopy (layered circles)
                ZStack {
                    // Bottom layer (darkest)
                    Circle()
                        .fill(Color(red: 0.18, green: 0.32, blue: 0.27))
                        .frame(width: 90, height: 90)
                        .offset(y: 6)

                    // Middle layer
                    Circle()
                        .fill(Color(red: 0.24, green: 0.42, blue: 0.36))
                        .frame(width: 80, height: 80)

                    // Top layer (lightest)
                    Circle()
                        .fill(Color(red: 0.32, green: 0.47, blue: 0.44))
                        .frame(width: 65, height: 65)
                        .offset(y: -6)

                    // Highlight
                    Circle()
                        .fill(Color(red: 0.52, green: 0.66, blue: 0.55).opacity(0.5))
                        .frame(width: 28, height: 28)
                        .offset(x: -15, y: -22)
                }

                // Trunk
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.55, green: 0.41, blue: 0.08), Color(red: 0.18, green: 0.32, blue: 0.27)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 14, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Root branches
                    HStack(spacing: 18) {
                        Rectangle()
                            .fill(Color(red: 0.18, green: 0.32, blue: 0.27))
                            .frame(width: 18, height: 5)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .rotationEffect(.degrees(-15))

                        Rectangle()
                            .fill(Color(red: 0.18, green: 0.32, blue: 0.27))
                            .frame(width: 18, height: 5)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .rotationEffect(.degrees(15))
                    }
                    .offset(y: -2)
                }
                .offset(y: -6)
            }

            // Fruits
            FruitDotView(color: Color(red: 0.88, green: 0.32, blue: 0.25))
                .offset(x: 22, y: -28)
            FruitDotView(color: Color(red: 0.90, green: 0.22, blue: 0.21))
                .offset(x: -20, y: -22)
            FruitDotView(color: Color(red: 1.0, green: 0.44, blue: 0.27))
                .offset(x: 8, y: -38)
            FruitDotView(color: Color(red: 0.90, green: 0.22, blue: 0.21))
                .offset(x: -30, y: -2)
            FruitDotView(color: Color(red: 1.0, green: 0.65, blue: 0.15))
                .offset(x: 30, y: 3)
            FruitDotView(color: Color(red: 1.0, green: 0.44, blue: 0.27))
                .offset(x: -6, y: -10)
            FruitDotView(color: Color(red: 0.88, green: 0.32, blue: 0.25))
                .offset(x: 16, y: 8)
            FruitDotView(color: Color(red: 1.0, green: 0.65, blue: 0.15))
                .offset(x: -14, y: 14)

            // Leaf accents
            Ellipse()
                .fill(Color(red: 0.52, green: 0.66, blue: 0.55))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(-30))
                .offset(x: -34, y: -18)

            Ellipse()
                .fill(Color(red: 0.52, green: 0.66, blue: 0.55))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(-30))
                .offset(x: 32, y: 2)

            Ellipse()
                .fill(Color(red: 0.52, green: 0.66, blue: 0.55))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(-30))
                .offset(x: -28, y: 22)
        }
    }
}

// MARK: - Fruit Dot View
struct FruitDotView: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)

            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
                .offset(x: -3, y: -3)
        }
    }
}

#Preview {
    LaunchScreen()
}
