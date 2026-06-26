// Utils.swift
// 原始来源：ios-depth-point-cloud (MIT License)

import CoreGraphics
import Foundation
import UIKit
import VideoToolbox

// MARK: - 文件命名

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

enum LocalFileStorage {
    static func isSafeLeafFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty, filename != ".", filename != ".." else { return false }
        guard filename == (filename as NSString).lastPathComponent else { return false }
        let forbidden = CharacterSet(charactersIn: "/\\:")
        return !filename.unicodeScalars.contains { scalar in
            forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

enum LocalFileStorageError: LocalizedError {
    case invalidFilename

    var errorDescription: String? {
        "文件名包含不安全的路径字符"
    }
}

enum SpreadsheetTextSafety {
    static func neutralizingFormula(_ value: String) -> String {
        guard let first = value.unicodeScalars.first else { return value }
        if isDangerousFormulaPrefix(first) {
            return "'\(value)"
        }

        let firstNonSpace = value.unicodeScalars.first { $0.value != 0x20 }
        if let firstNonSpace, isFormulaOperator(firstNonSpace) {
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

/// 生成带树木编号 + GPS 的规范文件名
/// 格式：T001-a1b2c3d4e5f6_20260714_103020_lat22.5678_lon114.1234.ply
func makeTreeFileName(
    treeID: String,
    lat: Double,
    lon: Double,
    date: Date = Date(),
    uniqueSuffix: String = UUID().uuidString
) -> String {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current
    df.dateFormat = "yyyyMMdd_HHmmss"
    let timeStr = df.string(from: date)
    let latStr = String(format: "lat%.4f", lat)
    let lonStr = String(format: "lon%.4f", lon)
    let safeTreeID = TreeIdentifierPolicy.safeFileComponent(from: treeID)
    let suffix = TreeIdentifierPolicy.safeFileComponent(from: uniqueSuffix)
        .prefix(12)
        .lowercased()
    return "\(safeTreeID)-\(suffix)_\(timeStr)_\(latStr)_\(lonStr).ply"
}

typealias Float2 = SIMD2<Float>
typealias Float3 = SIMD3<Float>

extension Float {
    static let degreesToRadian = Float.pi / 180
}

extension matrix_float3x3 {
    mutating func copy(from affine: CGAffineTransform) {
        columns.0 = Float3(Float(affine.a), Float(affine.c), Float(affine.tx))
        columns.1 = Float3(Float(affine.b), Float(affine.d), Float(affine.ty))
        columns.2 = Float3(0, 0, 1)
    }
}

// MARK: - 工具函数

/// 当前时间字符串（用于 PLY header 注释）
func getTimeStr() -> String {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.string(from: Date())
}

/// 保存二进制数据到 Documents 目录
func saveFile(data: Data, filename: String, folder: String) async throws {
    guard LocalFileStorage.isSafeLeafFilename(filename) else {
        throw LocalFileStorageError.invalidFilename
    }
    let url = getDocumentsDirectory()
        .appendingPathComponent(folder, isDirectory: true)
        .appendingPathComponent(filename)
    try data.write(to: url, options: [.atomic, .withoutOverwriting])
}

/// Documents 目录
func getDocumentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

/// 创建目录
func createDirectory(folder: String) {
    let path = getDocumentsDirectory().appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
}

/// CVPixelBuffer 深拷贝（避免 ARFrame 内存池耗尽）
func duplicatePixelBuffer(input: CVPixelBuffer) -> CVPixelBuffer {
    var copyOut: CVPixelBuffer?
    let w = CVPixelBufferGetWidth(input)
    let h = CVPixelBufferGetHeight(input)
    let fmt = CVPixelBufferGetPixelFormatType(input)
    let attachments = CVBufferCopyAttachments(input, .shouldPropagate)
    _ = CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt,
                            attachments, &copyOut)
    guard let output = copyOut else {
        return input
    }

    CVPixelBufferLockBaseAddress(input, .readOnly)
    CVPixelBufferLockBaseAddress(output, [])
    defer {
        CVPixelBufferUnlockBaseAddress(input, .readOnly)
        CVPixelBufferUnlockBaseAddress(output, [])
    }

    let planeCount = CVPixelBufferGetPlaneCount(input)
    if planeCount > 0 {
        for plane in 0..<planeCount {
            guard let src = CVPixelBufferGetBaseAddressOfPlane(input, plane),
                  let dst = CVPixelBufferGetBaseAddressOfPlane(output, plane)
            else { continue }

            let rows = CVPixelBufferGetHeightOfPlane(input, plane)
            let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(input, plane)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(output, plane)
            let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)

            for row in 0..<rows {
                memcpy(
                    dst.advanced(by: row * dstBytesPerRow),
                    src.advanced(by: row * srcBytesPerRow),
                    bytesPerRow
                )
            }
        }
    } else if let src = CVPixelBufferGetBaseAddress(input),
              let dst = CVPixelBufferGetBaseAddress(output) {
        let rows = CVPixelBufferGetHeight(input)
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(input)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)

        for row in 0..<rows {
            memcpy(
                dst.advanced(by: row * dstBytesPerRow),
                src.advanced(by: row * srcBytesPerRow),
                bytesPerRow
            )
        }
    }

    return output
}

// MARK: - Codable 扩展（用于 JSON 序列化，原始不变）
extension simd_float4x4: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        try self.init(c.decode([SIMD4<Float>].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode([columns.0, columns.1, columns.2, columns.3])
    }
}

extension simd_float3x3: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        try self.init(c.decode([SIMD3<Float>].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode([columns.0, columns.1, columns.2])
    }
}
