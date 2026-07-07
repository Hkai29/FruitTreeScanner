// DetectionDebugContentView.swift
// Structured content for the detection diagnostics screen.

import SwiftUI

struct DetectionDebugContentView: View {
    let state: DetectionDebugState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetectionDebugModelSection(state: state)
                DetectionDebugPipelineSection(state: state)
                DetectionDebugHintSection(hint: state.diagnosticHint)
                DetectionDebugPredictionsSection(predictions: state.topPredictions)
                DetectionDebugErrorSection(message: state.lastErrorMessage)
            }
            .padding(Design.Space.lg)
        }
    }
}

private struct DetectionDebugModelSection: View {
    let state: DetectionDebugState

    private var supportedClassesText: String {
        if state.supportedClasses.isEmpty {
            return "None exposed by model metadata. TODO: read labels file when bundled."
        }
        return state.supportedClasses.joined(separator: ", ")
    }

    var body: some View {
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
}

private struct DetectionDebugPipelineSection: View {
    let state: DetectionDebugState

    var body: some View {
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

    private func format(size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

private struct DetectionDebugHintSection: View {
    let hint: String?

    var body: some View {
        Group {
            if let hint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(Design.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
            }
        }
    }
}

private struct DetectionDebugPredictionsSection: View {
    let predictions: [DetectionPredictionDebug]

    var body: some View {
        DetectionDebugCard(title: "Top Predictions") {
            if predictions.isEmpty {
                Text("No predictions")
                    .font(.system(size: 13))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            } else {
                ForEach(Array(predictions.enumerated()), id: \.offset) { _, prediction in
                    DetectionPredictionDebugRow(prediction: prediction)
                }
            }
        }
    }
}

private struct DetectionDebugErrorSection: View {
    let message: String?

    var body: some View {
        DetectionDebugCard(title: "Last Error Message") {
            Text(message ?? "None")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(message == nil ? Design.Colors.Dark.textSecondary : Design.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
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
