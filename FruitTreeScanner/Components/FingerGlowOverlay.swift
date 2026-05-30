// FingerGlowOverlay.swift
// 手指光效跟随组件 - 不拦截其他手势的触摸追踪

import SwiftUI
import UIKit

struct FingerGlowOverlay: View {
    @State private var touchLocation: CGPoint = .zero
    @State private var isActive: Bool = false
    @State private var glowOpacity: Double = 0

    var body: some View {
        GlowTouchView(
            touchLocation: $touchLocation,
            isActive: $isActive,
            glowOpacity: $glowOpacity
        )
        .allowsHitTesting(false)  // 关键：不拦截触摸！
        .ignoresSafeArea()
    }
}

// MARK: - Glow Effect
struct GlowEffect: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Design.Colors.harvest.opacity(0.15),
                    Design.Colors.harvest.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 100
            )

            RadialGradient(
                colors: [
                    Design.Colors.harvest.opacity(0.3),
                    Design.Colors.harvest.opacity(0.1),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 50
            )

            RadialGradient(
                colors: [
                    Design.Colors.harvest.opacity(0.5),
                    Design.Colors.harvest.opacity(0.2),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 20
            )
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - UIKit Touch Tracking View
struct GlowTouchView: UIViewRepresentable {
    @Binding var touchLocation: CGPoint
    @Binding var isActive: Bool
    @Binding var glowOpacity: Double

    func makeUIView(context: Context) -> TouchTrackingWindow {
        let window = TouchTrackingWindow()
        window.touchHandler = { location, isActive in
            DispatchQueue.main.async {
                self.touchLocation = location
                self.isActive = isActive
                withAnimation(.easeOut(duration: 0.05)) {
                    self.glowOpacity = isActive ? 1 : 0
                }
            }
        }
        return window
    }

    func updateUIView(_ uiView: TouchTrackingWindow, context: Context) {}
}

// MARK: - Touch Tracking Window (窗口级别追踪)
class TouchTrackingWindow: UIView {
    var touchHandler: ((CGPoint, Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    // 关键：不拦截触摸 - 返回 nil 让触摸传递到下层视图
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 返回 nil 不处理触摸，让下层控件接收
        // 但同时通过 touchesBegan/Moved/Ended 回调追踪位置
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let location = touch.location(in: self)
            touchHandler?(location, true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let location = touch.location(in: self)
            touchHandler?(location, true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchHandler?(CGPoint.zero, false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchHandler?(CGPoint.zero, false)
    }
}

// MARK: - SwiftUI Overlay with Glow Effect
struct GlowOverlaySwiftUI: View {
    let touchLocation: CGPoint
    let isActive: Bool
    let glowOpacity: Double

    var body: some View {
        if isActive || glowOpacity > 0 {
            GlowEffect()
                .frame(width: 200, height: 200)
                .position(touchLocation)
                .opacity(glowOpacity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Ambient Glow (静态背景光效)
struct AmbientGlow: View {
    let position: UnitPoint

    var body: some View {
        RadialGradient(
            colors: [
                Design.Colors.harvest.opacity(0.1),
                Design.Colors.harvest.opacity(0.03),
                .clear
            ],
            center: position,
            startRadius: 0,
            endRadius: 300
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Touch Ripple Effect
struct TouchRipple: View {
    let location: CGPoint
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(Design.Colors.harvest.opacity(opacity), lineWidth: 2)
            .frame(width: 40 * scale, height: 40 * scale)
            .position(location)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    scale = 3
                    opacity = 0
                }
            }
    }
}

#Preview {
    ZStack {
        Design.Colors.Dark.bgDeep.ignoresSafeArea()

        Text("触摸屏幕任意位置")
            .font(.title)
            .foregroundColor(.white)

        FingerGlowOverlay()
    }
}
