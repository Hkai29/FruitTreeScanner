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

    static func optionalNonNegativeDouble(
        _ value: String,
        locale: Locale = .current
    ) -> Double? {
        let normalized = normalizedDecimalText(value, locale: locale)
        guard !normalized.isEmpty else { return nil }
        guard let parsed = Double(normalized),
              parsed.isFinite,
              parsed >= 0
        else { return nil }
        return parsed
    }

    static func estimatedYieldKgOrZero(
        _ value: String,
        locale: Locale = .current
    ) -> Double? {
        let normalized = normalizedNumberText(value)
        guard !normalized.isEmpty else { return 0 }
        guard let parsed = optionalNonNegativeDouble(normalized, locale: locale) else { return nil }
        return parsed
    }

    static func isOptionalNonNegativeIntValid(_ value: String) -> Bool {
        let normalized = normalizedNumberText(value)
        return normalized.isEmpty || optionalNonNegativeInt(normalized) != nil
    }

    static func isOptionalNonNegativeDoubleValid(
        _ value: String,
        locale: Locale = .current
    ) -> Bool {
        let normalized = normalizedNumberText(value)
        return normalized.isEmpty
            || optionalNonNegativeDouble(normalized, locale: locale) != nil
    }

    private static func normalizedNumberText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedDecimalText(_ value: String, locale: Locale) -> String {
        let normalized = normalizedNumberText(value)
        guard let decimalSeparator = locale.decimalSeparator,
              decimalSeparator != "."
        else {
            return normalized
        }
        return normalized.replacingOccurrences(of: decimalSeparator, with: ".")
    }
}
