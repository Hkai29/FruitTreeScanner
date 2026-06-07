// DetectionDebugView.swift
// DEBUG-only diagnostics for the camera fruit detection pipeline.

import SwiftUI

struct DetectionDebugView: View {
    @Environment(\.dismiss) private var dismiss
    let state: DetectionDebugState

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        modelSection
                        pipelineSection
                        hintSection
                        predictionsSection
                        errorSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("Detection Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var modelSection: some View {
        DetectionDebugCard(title: "Model") {
            DetectionDebugRow(label: "Model Loaded", value: state.modelLoaded ? "true" : "false")
            DetectionDebugRow(label: "Model Name", value: state.modelName)
            DetectionDebugRow(label: "Model URL Found", value: state.modelURLFound ? "true" : "false")
            VStack(alignment: .leading, spacing: 6) {
                Text("Supported Classes")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Text(supportedClassesText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pipelineSection: some View {
        DetectionDebugCard(title: "Pipeline") {
            DetectionDebugRow(label: "Frame Received", value: state.frameReceived ? "true" : "false")
            DetectionDebugRow(label: "Inference Requested", value: state.inferenceRequested ? "true" : "false")
            DetectionDebugRow(label: "Inference Running", value: state.inferenceRunning ? "true" : "false")
            DetectionDebugRow(label: "Raw Detections", value: "\(state.rawObservationCount)")
            DetectionDebugRow(label: "Filtered Detections", value: "\(state.filteredObservationCount)")
            DetectionDebugRow(label: "Threshold", value: String(format: "%.2f", state.currentThreshold))
            DetectionDebugRow(label: "Last Inference Time", value: String(format: "%.1f ms", state.lastInferenceTimeMs))
            DetectionDebugRow(label: "Frame Size", value: format(size: state.lastFrameSize))
            DetectionDebugRow(label: "Pixel Buffer Size", value: format(size: state.lastPixelBufferSize))
        }
    }

    private var hintSection: some View {
        Group {
            if let hint = state.diagnosticHint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(Design.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
            }
        }
    }

    private var predictionsSection: some View {
        DetectionDebugCard(title: "Top Predictions") {
            if state.topPredictions.isEmpty {
                Text("No predictions")
                    .font(.system(size: 13))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            } else {
                ForEach(Array(state.topPredictions.enumerated()), id: \.offset) { _, prediction in
                    DetectionPredictionDebugRow(prediction: prediction)
                }
            }
        }
    }

    private var errorSection: some View {
        DetectionDebugCard(title: "Last Error Message") {
            Text(state.lastErrorMessage ?? "None")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(state.lastErrorMessage == nil ? Design.Colors.Dark.textSecondary : Design.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var supportedClassesText: String {
        if state.supportedClasses.isEmpty {
            return "None exposed by model metadata. TODO: read labels file when bundled."
        }
        return state.supportedClasses.joined(separator: ", ")
    }

    private func format(size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

private struct DetectionDebugCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            content
        }
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private struct DetectionDebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DetectionPredictionDebugRow: View {
    let prediction: DetectionPredictionDebug

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(prediction.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Text(String(format: "%.1f%%", prediction.confidence * 100))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.harvest)
            }

            Text(format(box: prediction.boundingBox))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func format(box: CGRect) -> String {
        String(
            format: "box x=%.3f y=%.3f w=%.3f h=%.3f",
            box.origin.x,
            box.origin.y,
            box.width,
            box.height
        )
    }
}

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
