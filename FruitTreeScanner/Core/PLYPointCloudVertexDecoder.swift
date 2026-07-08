// PLYPointCloudVertexDecoder.swift
// Converts property-driven PLY vertex values into renderer-ready points.

import SceneKit

enum PLYPointCloudVertexDecoder {
    private static let defaultPointColor = PointCloudColor(r: 0.5, g: 0.5, b: 0.5, a: 1)

    static func asciiPosition(
        scalars: [Double],
        schema: PLYPointCloudSchema
    ) -> SCNVector3? {
        position(
            x: scalars[schema.xIndex],
            y: scalars[schema.yIndex],
            z: scalars[schema.zIndex]
        )
    }

    static func asciiColor(
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

    static func asciiScalars(
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

    static func binaryPosition(
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

    static func binaryColor(
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
