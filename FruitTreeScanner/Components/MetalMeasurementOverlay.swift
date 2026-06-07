import SwiftUI

final class MetalMeasurementController: ObservableObject, @unchecked Sendable {
    @Published var isActive = false
    @Published var measuredDistance: Float?
    @Published var point1Screen: CGPoint?
    @Published var point2Screen: CGPoint?
    @Published var instruction: String = "点击第1个点"

    private var point1World: SIMD3<Float>?
    private var point2World: SIMD3<Float>?
    weak var renderer: Renderer?

    init() {}

    func handleTap(at viewPoint: CGPoint, in viewSize: CGSize) {
        guard isActive, let renderer = renderer else { return }
        guard let matrices = renderer.getCameraMatrices() else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        guard renderer.currentPointCountPublic > 0 else {
            instruction = "请先录制点云"
            return
        }

        let viewportSize = matrices.viewportSize
        let renderPoint = CGPoint(
            x: viewPoint.x * viewportSize.width / viewSize.width,
            y: viewPoint.y * viewportSize.height / viewSize.height
        )

        guard let hit = renderer.hitTest(
            viewPoint: renderPoint,
            viewportSize: viewportSize,
            viewMatrix: matrices.viewMatrix
        ) else {
            instruction = "未选中点云，请点果树表面"
            return
        }
        let hitPos = hit.worldPosition

        if point1World == nil {
            point1World = hitPos
            point1Screen = viewPoint
            instruction = "点击第2个点"
        } else if point2World == nil {
            point2World = hitPos
            point2Screen = viewPoint
            if let p1 = point1World {
                measuredDistance = simd_distance(p1, hitPos)
            }
            instruction = "测量完成，点击重置"
        } else {
            clearMeasurements()
            point1World = hitPos
            point1Screen = viewPoint
            instruction = "点击第2个点"
        }
    }

    func clearMeasurements() {
        point1World = nil
        point2World = nil
        point1Screen = nil
        point2Screen = nil
        measuredDistance = nil
        instruction = "点击第1个点"
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        clearMeasurements()
    }

    func deactivate() {
        guard isActive || measuredDistance != nil || point1Screen != nil || point2Screen != nil else { return }
        isActive = false
        clearMeasurements()
    }
}

struct MetalMeasurementOverlay: View {
    @ObservedObject var controller: MetalMeasurementController
    @Binding var measuredDistance: Float?
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                instructionBanner(in: geo)

                if let p1 = controller.point1Screen {
                    Circle()
                        .fill(Design.Colors.apple)
                        .frame(width: 16, height: 16)
                        .position(p1)
                        .shadow(color: Design.Colors.apple.opacity(0.5), radius: 4)
                }

                if let p1 = controller.point1Screen, let p2 = controller.point2Screen {
                    MeasurementLine(from: p1, to: p2)

                    Circle()
                        .fill(Design.Colors.earth)
                        .frame(width: 16, height: 16)
                        .position(p2)
                        .shadow(color: Design.Colors.earth.opacity(0.5), radius: 4)

                    distanceLabel(at: midPoint(p1, p2), distance: controller.measuredDistance)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                controller.handleTap(at: location, in: geo.size)
                measuredDistance = controller.measuredDistance
            }
        }
        .padding(.bottom, 118)
        .onChange(of: controller.measuredDistance) { newValue in
            measuredDistance = newValue
        }
    }

    private func midPoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }

    private func instructionBanner(in geo: GeometryProxy) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Design.Colors.apple)
                                    .frame(width: 10, height: 10)
                                Text("起点")
                                    .font(.system(size: 11))
                            }
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Design.Colors.earth)
                                    .frame(width: 10, height: 10)
                                Text("终点")
                                    .font(.system(size: 11))
                            }
                        }

                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(controller.instruction)
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray)
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Design.Colors.Dark.hudBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                .cornerRadius(10)
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    private func distanceLabel(at point: CGPoint, distance: Float?) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    if let dist = distance {
                        Text(String(format: "%.2f m", dist))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundColor(Design.Colors.harvest)
                    } else {
                        Text("计算中...")
                            .font(.system(size: 14))
                            .foregroundColor(Color.gray)
                    }
                    Text("测量距离")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(16)
                .background(Design.Colors.Dark.hudBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                .cornerRadius(10)
                .padding(16)
            }
        }
    }
}

struct MeasurementLine: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.white), lineWidth: 2)

            let angle = atan2(to.y - from.y, to.x - from.x)
            let arrowLength: CGFloat = 10

            var arrowPath = Path()
            arrowPath.move(to: to)
            arrowPath.addLine(to: CGPoint(
                x: to.x - arrowLength * cos(angle - .pi / 6),
                y: to.y - arrowLength * sin(angle - .pi / 6)
            ))
            arrowPath.move(to: to)
            arrowPath.addLine(to: CGPoint(
                x: to.x - arrowLength * cos(angle + .pi / 6),
                y: to.y - arrowLength * sin(angle + .pi / 6)
            ))
            context.stroke(arrowPath, with: .color(.white), lineWidth: 2)
        }
    }
}
