// DetectionDebugOverlayView.swift
// DEBUG-only detection boxes over the scanner preview.

import SwiftUI

#if DEBUG
struct DetectionDebugOverlayView: View {
    let state: DetectionDebugState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(state.rawPredictions.enumerated()), id: \.offset) { _, prediction in
                    detectionBox(
                        prediction: prediction,
                        size: proxy.size,
                        color: .orange,
                        opacity: 0.38,
                        lineWidth: 1,
                        dash: [5, 4]
                    )
                }

                ForEach(Array(state.filteredPredictions.enumerated()), id: \.offset) { _, prediction in
                    detectionBox(
                        prediction: prediction,
                        size: proxy.size,
                        color: .green,
                        opacity: 0.9,
                        lineWidth: 2,
                        dash: []
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func detectionBox(
        prediction: DetectionPredictionDebug,
        size: CGSize,
        color: Color,
        opacity: Double,
        lineWidth: CGFloat,
        dash: [CGFloat]
    ) -> some View {
        let rect = screenRect(for: prediction.boundingBox, in: size)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(
                    color.opacity(opacity),
                    style: StrokeStyle(lineWidth: lineWidth, dash: dash)
                )
                .frame(width: rect.width, height: rect.height)

            Text("\(prediction.label) \(Int(prediction.confidence * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.8))
                .offset(y: -16)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private func screenRect(for boundingBox: CGRect, in size: CGSize) -> CGRect {
        // TODO: Recheck orientation and aspect-fill transforms if supported screen orientation changes.
        let x = boundingBox.minX * size.width
        let y = (1 - boundingBox.maxY) * size.height
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
#endif
