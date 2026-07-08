// PLYPointCloudSchema.swift
// PLY point-cloud header types and schema parsing.

import Foundation

enum PLYPointCloudFormat {
    case ascii
    case binaryLittleEndian
    case binaryBigEndian

    var isBigEndian: Bool {
        self == .binaryBigEndian
    }
}

enum PLYScalarType {
    case int8
    case uint8
    case int16
    case uint16
    case int32
    case uint32
    case float32
    case float64

    init?(token: String) {
        switch token.lowercased() {
        case "char", "int8": self = .int8
        case "uchar", "uint8": self = .uint8
        case "short", "int16": self = .int16
        case "ushort", "uint16": self = .uint16
        case "int", "int32": self = .int32
        case "uint", "uint32": self = .uint32
        case "float", "float32": self = .float32
        case "double", "float64": self = .float64
        default: return nil
        }
    }

    var byteWidth: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float32: return 4
        case .float64: return 8
        }
    }

    var isFloatingPoint: Bool {
        self == .float32 || self == .float64
    }

    var integerColorMaximum: Double? {
        switch self {
        case .int8: return Double(Int8.max)
        case .uint8: return Double(UInt8.max)
        case .int16: return Double(Int16.max)
        case .uint16: return Double(UInt16.max)
        case .int32: return Double(Int32.max)
        case .uint32: return Double(UInt32.max)
        case .float32, .float64: return nil
        }
    }

    func parseASCII(_ token: Substring) -> Double? {
        switch self {
        case .int8:
            guard let value = Int64(token), value >= Int64(Int8.min), value <= Int64(Int8.max) else { return nil }
            return Double(value)
        case .uint8:
            guard let value = UInt64(token), value <= UInt64(UInt8.max) else { return nil }
            return Double(value)
        case .int16:
            guard let value = Int64(token), value >= Int64(Int16.min), value <= Int64(Int16.max) else { return nil }
            return Double(value)
        case .uint16:
            guard let value = UInt64(token), value <= UInt64(UInt16.max) else { return nil }
            return Double(value)
        case .int32:
            guard let value = Int64(token), value >= Int64(Int32.min), value <= Int64(Int32.max) else { return nil }
            return Double(value)
        case .uint32:
            guard let value = UInt64(token), value <= UInt64(UInt32.max) else { return nil }
            return Double(value)
        case .float32:
            guard let value = Float(token), value.isFinite else { return nil }
            return Double(value)
        case .float64:
            guard let value = Double(token), value.isFinite else { return nil }
            return value
        }
    }
}

struct PLYVertexProperty {
    let name: String
    let scalarType: PLYScalarType
    let byteOffset: Int
}

struct PLYPointCloudSchema {
    let vertexCount: Int
    let format: PLYPointCloudFormat
    let properties: [PLYVertexProperty]
    let vertexStride: Int
    let xIndex: Int
    let yIndex: Int
    let zIndex: Int
    let redIndex: Int?
    let greenIndex: Int?
    let blueIndex: Int?

    var colorIndices: (Int, Int, Int)? {
        guard let redIndex, let greenIndex, let blueIndex else { return nil }
        return (redIndex, greenIndex, blueIndex)
    }
}

extension PLYParserHelper {
    private static let maximumSupportedVertexCount = 10_000_000

    static func parsePointCloudHeader(_ lines: [String]) -> PLYPointCloudSchema? {
        guard lines.first == "ply" else { return nil }
        var format: PLYPointCloudFormat?
        var vertexCount: Int?
        var currentElement: String?
        var declaredProperties: [(name: String, scalarType: PLYScalarType)] = []

        for line in lines where !line.isEmpty {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard let keyword = parts.first?.lowercased() else { continue }

            switch keyword {
            case "format":
                guard format == nil, parts.count == 3, parts[2] == "1.0" else { return nil }
                switch parts[1].lowercased() {
                case "ascii": format = .ascii
                case "binary_little_endian": format = .binaryLittleEndian
                case "binary_big_endian": format = .binaryBigEndian
                default: return nil
                }

            case "element":
                guard parts.count == 3, let count = Int(parts[2]), count >= 0 else { return nil }
                currentElement = parts[1].lowercased()
                if currentElement == "vertex" {
                    guard vertexCount == nil else { return nil }
                    vertexCount = count
                }

            case "property" where currentElement == "vertex":
                guard parts.count == 3,
                      parts[1].lowercased() != "list",
                      let scalarType = PLYScalarType(token: String(parts[1]))
                else { return nil }
                declaredProperties.append((parts[2].lowercased(), scalarType))

            default:
                continue
            }
        }

        guard let format,
              let vertexCount,
              vertexCount > 0,
              vertexCount <= maximumSupportedVertexCount,
              !declaredProperties.isEmpty
        else { return nil }

        return makePointCloudSchema(
            vertexCount: vertexCount,
            format: format,
            declaredProperties: declaredProperties
        )
    }

    private static func makePointCloudSchema(
        vertexCount: Int,
        format: PLYPointCloudFormat,
        declaredProperties: [(name: String, scalarType: PLYScalarType)]
    ) -> PLYPointCloudSchema? {
        var properties: [PLYVertexProperty] = []
        properties.reserveCapacity(declaredProperties.count)
        var byteOffset = 0
        var propertyIndexByName: [String: Int] = [:]

        for declared in declaredProperties {
            guard propertyIndexByName[declared.name] == nil,
                  byteOffset <= Int.max - declared.scalarType.byteWidth
            else { return nil }
            propertyIndexByName[declared.name] = properties.count
            properties.append(PLYVertexProperty(
                name: declared.name,
                scalarType: declared.scalarType,
                byteOffset: byteOffset
            ))
            byteOffset += declared.scalarType.byteWidth
        }

        guard let xIndex = propertyIndexByName["x"],
              let yIndex = propertyIndexByName["y"],
              let zIndex = propertyIndexByName["z"]
        else { return nil }

        let redIndex = propertyIndexByName["red"] ?? propertyIndexByName["r"]
        let greenIndex = propertyIndexByName["green"] ?? propertyIndexByName["g"]
        let blueIndex = propertyIndexByName["blue"] ?? propertyIndexByName["b"]

        return PLYPointCloudSchema(
            vertexCount: vertexCount,
            format: format,
            properties: properties,
            vertexStride: byteOffset,
            xIndex: xIndex,
            yIndex: yIndex,
            zIndex: zIndex,
            redIndex: redIndex,
            greenIndex: greenIndex,
            blueIndex: blueIndex
        )
    }
}
