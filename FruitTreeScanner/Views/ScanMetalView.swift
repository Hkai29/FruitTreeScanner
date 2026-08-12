import ARKit
import MetalKit
import SwiftUI

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawRectResized(size: size)
    }

    func draw(in view: MTKView) {
        renderFrame()
    }
}

struct MetalView: UIViewRepresentable {
    let coordinator: ScanCoordinator

    func makeCoordinator() -> MetalViewCoordinator {
        MetalViewCoordinator(coordinator: coordinator)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView()
        }

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.backgroundColor = .black
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.preferredFramesPerSecond = 60

        let arSession = ARSession()
        let renderer = Renderer(
            session: arSession,
            metalDevice: device,
            renderDestination: mtkView
        )

        let viewSize = mtkView.drawableSize
        if viewSize.width > 0 && viewSize.height > 0 {
            renderer.drawRectResized(size: viewSize)
        }

        mtkView.delegate = renderer
        context.coordinator.coordinator?.bind(session: arSession, renderer: renderer, mtkView: mtkView)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if uiView.drawableSize.width > 0 && uiView.drawableSize.height > 0 {
            context.coordinator.coordinator?.renderer?.drawRectResized(size: uiView.drawableSize)
        }
    }

    static func dismantleUIView(
        _ uiView: MTKView,
        coordinator: MetalViewCoordinator
    ) {
        coordinator.coordinator?.teardownBinding(for: uiView)
    }
}

final class MetalViewCoordinator: NSObject {
    weak var coordinator: ScanCoordinator?

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
        super.init()
    }
}
