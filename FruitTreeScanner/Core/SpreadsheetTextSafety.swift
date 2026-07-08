// SpreadsheetTextSafety.swift
// CSV and spreadsheet text neutralization helpers.

import Foundation

enum SpreadsheetTextSafety {
    static func neutralizingFormula(_ value: String) -> String {
        guard let first = value.unicodeScalars.first else { return value }
        if isDangerousFormulaPrefix(first) {
            return "'\(value)"
        }

        let firstNonWhitespace = value.unicodeScalars.first {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        if let firstNonWhitespace, isFormulaOperator(firstNonWhitespace) {
            return "'\(value)"
        }

        return value
    }

    private static func isDangerousFormulaPrefix(_ scalar: Unicode.Scalar) -> Bool {
        isFormulaOperator(scalar) || scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
    }

    private static func isFormulaOperator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3D, 0x2B, 0x2D, 0x40: // = + - @
            return true
        default:
            return false
        }
    }
}
