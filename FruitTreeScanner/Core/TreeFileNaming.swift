// TreeFileNaming.swift
// Tree identifier validation and deterministic scan filename generation.

import Foundation

enum TreeIdentifierPolicy {
    static let maximumCharacterCount = 64

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validationError(for value: String) -> String? {
        let normalizedValue = normalized(value)
        guard !normalizedValue.isEmpty else {
            return "请输入果树编号"
        }
        guard normalizedValue.count <= maximumCharacterCount else {
            return "编号最多 \(maximumCharacterCount) 个字符"
        }
        guard normalizedValue != ".", normalizedValue != ".." else {
            return "编号不能使用路径标记"
        }

        let forbidden = CharacterSet(charactersIn: "/\\:")
        let hasForbiddenScalar = normalizedValue.unicodeScalars.contains { scalar in
            forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
        guard !hasForbiddenScalar else {
            return "编号不能包含 /、\\、: 或换行"
        }
        return nil
    }

    static func isValid(_ value: String) -> Bool {
        validationError(for: value) == nil
    }

    static func safeFileComponent(from value: String) -> String {
        let source = normalized(value).precomposedStringWithCanonicalMapping
        var component = ""
        var needsSeparator = false

        for scalar in source.unicodeScalars {
            let isAlphaNumeric = CharacterSet.alphanumerics.contains(scalar)
            let isExplicitlyAllowed = scalar.value == 45 || scalar.value == 95 // - or _
            if isAlphaNumeric || isExplicitlyAllowed {
                if needsSeparator, !component.isEmpty, !component.hasSuffix("-") {
                    component.append("-")
                }
                component.append(contentsOf: String(scalar))
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }

        component = component.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        component = truncatingUTF8(component, maximumBytes: 80)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return component.isEmpty ? "Tree" : component
    }

    static func safePLYCommentValue(_ value: String) -> String {
        let withoutControls = normalized(value).unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let collapsed = withoutControls.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let bounded = String(collapsed.prefix(128))
        return bounded.isEmpty ? "Tree" : bounded
    }

    private static func truncatingUTF8(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let characterString = String(character)
            let nextByteCount = byteCount + characterString.utf8.count
            guard nextByteCount <= maximumBytes else { break }
            result.append(character)
            byteCount = nextByteCount
        }
        return result
    }
}

/// 生成带树木编号 + GPS 的规范文件名
/// 格式：T001-a1b2c3d4e5f6_20260714_103020_lat22.5678_lon114.1234.ply
func makeTreeFileName(
    treeID: String,
    lat: Double,
    lon: Double,
    date: Date = Date(),
    uniqueSuffix: String = UUID().uuidString
) -> String {
    let df = StableDataFormatting.dateFormatter(dateFormat: "yyyyMMdd_HHmmss")
    let timeStr = df.string(from: date)
    let latStr = "lat\(StableDataFormatting.decimal(lat, precision: 4))"
    let lonStr = "lon\(StableDataFormatting.decimal(lon, precision: 4))"
    let safeTreeID = TreeIdentifierPolicy.safeFileComponent(from: treeID)
    let suffix = TreeIdentifierPolicy.safeFileComponent(from: uniqueSuffix)
        .prefix(12)
        .lowercased()
    return "\(safeTreeID)-\(suffix)_\(timeStr)_\(latStr)_\(lonStr).ply"
}
