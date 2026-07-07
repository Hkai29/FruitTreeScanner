// Utils.swift
// Legacy shared helpers that do not belong to a narrower Core module yet.

import Foundation

enum StableDataFormatting {
    static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func dateFormatter(
        dateFormat: String,
        timeZone: TimeZone = .current
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = posixLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func decimal(_ value: Float, precision: Int) -> String {
        decimal(Double(value), precision: precision)
    }

    static func decimal(_ value: Double, precision: Int) -> String {
        String(format: "%.\(precision)f", locale: posixLocale, value)
    }
}

/// 当前时间字符串（用于 PLY header 注释）
func getTimeStr() -> String {
    StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss").string(from: Date())
}
