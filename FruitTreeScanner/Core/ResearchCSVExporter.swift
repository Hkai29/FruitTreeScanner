// ResearchCSVExporter.swift
// Per-fruit CSV export for calibration and error analysis.

import Foundation

struct FruitMassEstimateGroundTruth: Sendable, Equatable {
    var trueWeightG: Float?
    var trueVolumeCm3: Float?
}

enum ResearchCSVExporter {
    static let headerFields = [
        "id",
        "fruitCategory",
        "lengthCm",
        "widthCm",
        "heightCm",
        "equivalentDiameterCm",
        "sphereVolumeCm3",
        "ellipsoidVolumeCm3",
        "selectedVolumeCm3",
        "densityGPerCm3",
        "estimatedWeightG",
        "confidenceScore",
        "pointCount",
        "highConfidenceRatio",
        "validDepthRatio",
        "shapeModelUsed",
        "warningFlags",
        "createdAt",
        "trueWeightG",
        "trueVolumeCm3",
    ]

    static func makeCSV(
        estimates: [FruitMassEstimate],
        groundTruthByID: [UUID: FruitMassEstimateGroundTruth] = [:]
    ) -> String {
        var rows = [csvLine(headerFields)]
        rows += estimates.map { estimate in
            csvLine(fields(for: estimate, groundTruth: groundTruthByID[estimate.id]))
        }
        return rows.joined()
    }

    private static func fields(
        for estimate: FruitMassEstimate,
        groundTruth: FruitMassEstimateGroundTruth?
    ) -> [String] {
        [
            estimate.id.uuidString,
            SpreadsheetTextSafety.neutralizingFormula(estimate.fruitCategory),
            format(estimate.lengthCm),
            format(estimate.widthCm),
            format(estimate.heightCm),
            format(estimate.equivalentDiameterCm),
            format(estimate.sphereVolumeCm3),
            format(estimate.ellipsoidVolumeCm3),
            format(estimate.selectedVolumeCm3),
            format(estimate.densityGPerCm3),
            format(estimate.estimatedWeightG),
            format(estimate.confidenceScore),
            "\(estimate.pointCount)",
            format(estimate.highConfidenceRatio),
            format(estimate.validDepthRatio),
            SpreadsheetTextSafety.neutralizingFormula(estimate.shapeModelUsed.rawValue),
            SpreadsheetTextSafety.neutralizingFormula(estimate.warningFlags.map(\.rawValue).joined(separator: ";")),
            ISO8601DateFormatter().string(from: estimate.createdAt),
            groundTruth?.trueWeightG.map(formatGroundTruth) ?? "",
            groundTruth?.trueVolumeCm3.map(formatGroundTruth) ?? "",
        ]
    }

    private static func csvLine(_ fields: [String]) -> String {
        fields.map(escapeCSV).joined(separator: ",") + "\n"
    }

    private static func escapeCSV(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains(";") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func format(_ value: Float) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.4f", value)
    }

    private static func formatGroundTruth(_ value: Float) -> String {
        guard value.isFinite, value >= 0 else { return "" }
        return String(format: "%.4f", value)
    }
}
