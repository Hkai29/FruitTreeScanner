// PLYPointCloudParser.swift
// Property-driven ASCII and binary PLY point-cloud readers.

import Foundation
import SceneKit

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
    private static let maximumRenderedPointCount = 500_000
    private static let maximumSupportedVertexCount = 10_000_000
    private static let defaultPointColor = PointCloudColor(r: 0.5, g: 0.5, b: 0.5, a: 1)

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

    static func parseASCIIPointCloud(
        data: Data,
        bodyStart: Int,
        schema: PLYPointCloudSchema,
        sourceURL: URL
    ) -> PointCloudData? {
        guard bodyStart >= 0,
              bodyStart <= data.count,
              let content = String(data: data[bodyStart...], encoding: .utf8)
        else { return nil }

        let targetCount = min(schema.vertexCount, maximumRenderedPointCount)
        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        vertices.reserveCapacity(targetCount)
        colors.reserveCapacity(targetCount)
        var parsedVertexCount = 0

        for line in content.components(separatedBy: .newlines) {
            if parsedVertexCount == schema.vertexCount { break }
            let values = line.split(whereSeparator: { $0.isWhitespace })
            if values.isEmpty { continue }
            guard values.count == schema.properties.count,
                  let scalars = asciiScalars(values: values, schema: schema),
                  let position = asciiPosition(scalars: scalars, schema: schema),
                  let color = asciiColor(scalars: scalars, schema: schema)
            else { return nil }
            if parsedVertexCount < targetCount {
                vertices.append(position)
                colors.append(color)
            }
            parsedVertexCount += 1
            if parsedVertexCount.isMultiple(of: 4_096), Task.isCancelled {
                return nil
            }
        }

        guard parsedVertexCount == schema.vertexCount,
              vertices.count == targetCount
        else { return nil }
        return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
    }

    static func parseBinaryPointCloud(
        data: Data,
        bodyStart: Int,
        schema: PLYPointCloudSchema,
        sourceURL: URL
    ) -> PointCloudData? {
        let stride = schema.vertexStride
        guard bodyStart >= 0,
              bodyStart <= data.count,
              stride > 0,
              schema.vertexCount <= (data.count - bodyStart) / stride
        else { return nil }

        let targetCount = min(schema.vertexCount, maximumRenderedPointCount)
        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        vertices.reserveCapacity(targetCount)
        colors.reserveCapacity(targetCount)
        var isValid = true

        data.withUnsafeBytes { bytes in
            for index in 0..<targetCount {
                if index.isMultiple(of: 4_096), Task.isCancelled {
                    isValid = false
                    break
                }
                let vertexOffset = bodyStart + index * stride
                guard let position = binaryPosition(
                    bytes: bytes,
                    vertexOffset: vertexOffset,
                    schema: schema
                ), let color = binaryColor(
                    bytes: bytes,
                    vertexOffset: vertexOffset,
                    schema: schema
                ) else {
                    isValid = false
                    break
                }
                vertices.append(position)
                colors.append(color)
            }
        }

        guard isValid, vertices.count == targetCount else { return nil }
        return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
    }

    private static func asciiPosition(
        scalars: [Double],
        schema: PLYPointCloudSchema
    ) -> SCNVector3? {
        position(
            x: scalars[schema.xIndex],
            y: scalars[schema.yIndex],
            z: scalars[schema.zIndex]
        )
    }

    private static func asciiColor(
        scalars: [Double],
        schema: PLYPointCloudSchema
    ) -> PointCloudColor? {
        guard let (redIndex, greenIndex, blueIndex) = schema.colorIndices else {
            return defaultPointColor
        }
        return pointColor(
            red: scalars[redIndex],
            green: scalars[greenIndex],
            blue: scalars[blueIndex],
            redType: schema.properties[redIndex].scalarType,
            greenType: schema.properties[greenIndex].scalarType,
            blueType: schema.properties[blueIndex].scalarType
        )
    }

    private static func asciiScalars(
        values: [Substring],
        schema: PLYPointCloudSchema
    ) -> [Double]? {
        var scalars: [Double] = []
        scalars.reserveCapacity(schema.properties.count)
        for (index, property) in schema.properties.enumerated() {
            guard let value = property.scalarType.parseASCII(values[index]) else { return nil }
            scalars.append(value)
        }
        return scalars
    }

    private static func binaryPosition(
        bytes: UnsafeRawBufferPointer,
        vertexOffset: Int,
        schema: PLYPointCloudSchema
    ) -> SCNVector3? {
        position(
            x: binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: schema.xIndex, schema: schema),
            y: binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: schema.yIndex, schema: schema),
            z: binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: schema.zIndex, schema: schema)
        )
    }

    private static func binaryColor(
        bytes: UnsafeRawBufferPointer,
        vertexOffset: Int,
        schema: PLYPointCloudSchema
    ) -> PointCloudColor? {
        guard let (redIndex, greenIndex, blueIndex) = schema.colorIndices else {
            return defaultPointColor
        }
        guard let red = binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: redIndex, schema: schema),
              let green = binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: greenIndex, schema: schema),
              let blue = binaryValue(bytes: bytes, vertexOffset: vertexOffset, propertyIndex: blueIndex, schema: schema)
        else { return nil }
        return pointColor(
            red: red,
            green: green,
            blue: blue,
            redType: schema.properties[redIndex].scalarType,
            greenType: schema.properties[greenIndex].scalarType,
            blueType: schema.properties[blueIndex].scalarType
        )
    }

    private static func binaryValue(
        bytes: UnsafeRawBufferPointer,
        vertexOffset: Int,
        propertyIndex: Int,
        schema: PLYPointCloudSchema
    ) -> Double? {
        guard propertyIndex >= 0, propertyIndex < schema.properties.count else { return nil }
        let property = schema.properties[propertyIndex]
        return scalarValue(
            bytes: bytes,
            offset: vertexOffset + property.byteOffset,
            type: property.scalarType,
            bigEndian: schema.format.isBigEndian
        )
    }

    private static func position(x: Double?, y: Double?, z: Double?) -> SCNVector3? {
        guard let x, let y, let z, x.isFinite, y.isFinite, z.isFinite else { return nil }
        let floatX = Float(x)
        let floatY = Float(y)
        let floatZ = Float(z)
        guard floatX.isFinite, floatY.isFinite, floatZ.isFinite else { return nil }
        return SCNVector3(floatX, floatY, floatZ)
    }

    private static func pointColor(
        red: Double,
        green: Double,
        blue: Double,
        redType: PLYScalarType,
        greenType: PLYScalarType,
        blueType: PLYScalarType
    ) -> PointCloudColor? {
        let floatingScale: Double = [
            redType.isFloatingPoint ? red : nil,
            greenType.isFloatingPoint ? green : nil,
            blueType.isFloatingPoint ? blue : nil,
        ].compactMap { $0 }.contains(where: { $0 > 1 }) ? 255 : 1
        guard let red = normalizedColorComponent(red, type: redType, floatingScale: floatingScale),
              let green = normalizedColorComponent(green, type: greenType, floatingScale: floatingScale),
              let blue = normalizedColorComponent(blue, type: blueType, floatingScale: floatingScale)
        else { return nil }
        return PointCloudColor(r: red, g: green, b: blue, a: 1)
    }

    private static func normalizedColorComponent(
        _ value: Double,
        type: PLYScalarType,
        floatingScale: Double
    ) -> Float? {
        guard value.isFinite else { return nil }
        let normalized: Double
        if type.isFloatingPoint {
            normalized = value / floatingScale
        } else if let maximum = type.integerColorMaximum, maximum > 0 {
            normalized = value / maximum
        } else {
            return nil
        }
        return Float(min(max(normalized, 0), 1))
    }

    private static func scalarValue(
        bytes: UnsafeRawBufferPointer,
        offset: Int,
        type: PLYScalarType,
        bigEndian: Bool
    ) -> Double? {
        guard offset >= 0, offset <= bytes.count - type.byteWidth else { return nil }

        switch type {
        case .int8:
            return Double(Int8(bitPattern: bytes[offset]))
        case .uint8:
            return Double(bytes[offset])
        case .int16:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            let value = bigEndian ? UInt16(bigEndian: raw) : UInt16(littleEndian: raw)
            return Double(Int16(bitPattern: value))
        case .uint16:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            return Double(bigEndian ? UInt16(bigEndian: raw) : UInt16(littleEndian: raw))
        case .int32:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let value = bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
            return Double(Int32(bitPattern: value))
        case .uint32:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            return Double(bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw))
        case .float32:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let value = bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
            let float = Float(bitPattern: value)
            return float.isFinite ? Double(float) : nil
        case .float64:
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            let value = bigEndian ? UInt64(bigEndian: raw) : UInt64(littleEndian: raw)
            let double = Double(bitPattern: value)
            return double.isFinite ? double : nil
        }
    }
}
