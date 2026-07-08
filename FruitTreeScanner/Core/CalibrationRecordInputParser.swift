import Foundation

enum CalibrationRecordInputParser {
    static func requiredNonNegativeInt(_ value: String) -> Int? {
        let normalized = normalizedNumberText(value)
        guard !normalized.isEmpty,
              let parsed = Int(normalized),
              parsed >= 0
        else { return nil }
        return parsed
    }

    static func optionalNonNegativeInt(_ value: String) -> Int? {
        let normalized = normalizedNumberText(value)
        guard !normalized.isEmpty else { return nil }
        guard let parsed = Int(normalized),
              parsed >= 0
        else { return nil }
        return parsed
    }

    static func optionalNonNegativeDouble(_ value: String) -> Double? {
        let normalized = normalizedNumberText(value)
        guard !normalized.isEmpty else { return nil }
        guard let parsed = Double(normalized),
              parsed.isFinite,
              parsed >= 0
        else { return nil }
        return parsed
    }

    static func estimatedYieldKgOrZero(_ value: String) -> Double? {
        let normalized = normalizedNumberText(value)
        guard !normalized.isEmpty else { return 0 }
        guard let parsed = optionalNonNegativeDouble(normalized) else { return nil }
        return parsed
    }

    static func isOptionalNonNegativeIntValid(_ value: String) -> Bool {
        let normalized = normalizedNumberText(value)
        return normalized.isEmpty || optionalNonNegativeInt(normalized) != nil
    }

    static func isOptionalNonNegativeDoubleValid(_ value: String) -> Bool {
        let normalized = normalizedNumberText(value)
        return normalized.isEmpty || optionalNonNegativeDouble(normalized) != nil
    }

    private static func normalizedNumberText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
