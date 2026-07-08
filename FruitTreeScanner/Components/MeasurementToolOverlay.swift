import SwiftUI
import SceneKit

struct MeasurementToolOverlay: View {
    @ObservedObject var controller: PointCloudMeasurementController
    @Binding var measuredDistance: Float?
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                instructionBanner(in: geo)

                if let distance = controller.measuredDistance {
                    distanceDisplay(distance: distance)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                controller.handleTap(at: location)
                measuredDistance = controller.measuredDistance
            }
        }
        .onAppear {
            measuredDistance = controller.measuredDistance
        }
        .onChange(of: controller.measuredDistance) { newValue in
            measuredDistance = newValue
        }
    }

    private func instructionBanner(in geo: GeometryProxy) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
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

                    Text("点击点云表面测量")
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

    private func distanceDisplay(distance: Float) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text(String(format: "%.2f m", distance))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(Design.Colors.harvest)

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
