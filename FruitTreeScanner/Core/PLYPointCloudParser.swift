// PLYPointCloudParser.swift
// ASCII and binary PLY point-cloud readers.

import Foundation
import SceneKit

extension PLYParserHelper {
    static func parsePointCloudHeader(_ lines: [String]) -> (vertexCount: Int, isBinary: Bool, isBigEndian: Bool, hasColor: Bool) {
        var vertexCount = 0
        var isBinary = false
        var isBigEndian = false
        var hasColor = false

        for line in lines {
            if line.hasPrefix("element vertex") {
                let parts = line.split { $0.isWhitespace }
                if parts.count >= 3, let count = Int(parts[2]) {
                    vertexCount = count
                }
            } else if line.hasPrefix("format ascii") {
                isBinary = false
            } else if line.hasPrefix("format binary_little_endian") {
                isBinary = true
                isBigEndian = false
            } else if line.hasPrefix("format binary_big_endian") {
                isBinary = true
                isBigEndian = true
            } else if line.hasPrefix("property uchar red") || line.hasPrefix("property uchar r") {
                hasColor = true
            }
        }

        return (vertexCount, isBinary, isBigEndian, hasColor)
    }

    static func parseASCIIPointCloud(data: Data, bodyStart: Int, vertexCount: Int, sourceURL: URL) -> PointCloudData? {
        guard let content = String(data: data[bodyStart...], encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)

        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        vertices.reserveCapacity(min(vertexCount, 500_000))
        colors.reserveCapacity(min(vertexCount, 500_000))

        for line in lines {
            let values = line.split { $0.isWhitespace }
            guard values.count >= 6,
                  let x = Float(values[0]),
                  let y = Float(values[1]),
                  let z = Float(values[2]),
                  let r = UInt8(values[3]),
                  let g = UInt8(values[4]),
                  let b = UInt8(values[5]) else {
                continue
            }
            vertices.append(SCNVector3(x, y, z))
            colors.append(PointCloudColor(
                r: Float(r) / 255.0,
                g: Float(g) / 255.0,
                b: Float(b) / 255.0,
                a: 1.0
            ))
            if vertices.count >= vertexCount { break }
        }

        guard !vertices.isEmpty else { return nil }
        return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
    }

    static func parseBinaryPointCloud(
        data: Data,
        bodyStart: Int,
        vertexCount: Int,
        bigEndian: Bool,
        hasColor: Bool,
        sourceURL: URL
    ) -> PointCloudData? {
        let pointStride = hasColor ? 15 : 12
        let expectedSize = bodyStart + vertexCount * pointStride
        guard data.count >= expectedSize else { return nil }

        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        let maxPoints = min(vertexCount, 500_000)
        vertices.reserveCapacity(maxPoints)
        colors.reserveCapacity(maxPoints)

        data.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress else { return }
            let bodyPtr = basePtr.advanced(by: bodyStart)

            for index in 0..<vertexCount {
                if vertices.count >= maxPoints { break }
                let offset = index * pointStride
                let pointPtr = bodyPtr.advanced(by: offset)

                let rawX = pointPtr.assumingMemoryBound(to: UInt32.self).pointee
                let rawY = pointPtr.advanced(by: 4).assumingMemoryBound(to: UInt32.self).pointee
                let rawZ = pointPtr.advanced(by: 8).assumingMemoryBound(to: UInt32.self).pointee

                let x = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawX) : UInt32(littleEndian: rawX))
                let y = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawY) : UInt32(littleEndian: rawY))
                let z = Float(bitPattern: bigEndian ? UInt32(bigEndian: rawZ) : UInt32(littleEndian: rawZ))
                vertices.append(SCNVector3(x, y, z))

                if hasColor {
                    let r = pointPtr.advanced(by: 12).assumingMemoryBound(to: UInt8.self).pointee
                    let g = pointPtr.advanced(by: 13).assumingMemoryBound(to: UInt8.self).pointee
                    let b = pointPtr.advanced(by: 14).assumingMemoryBound(to: UInt8.self).pointee
                    colors.append(PointCloudColor(
                        r: Float(r) / 255.0,
                        g: Float(g) / 255.0,
                        b: Float(b) / 255.0,
                        a: 1.0
                    ))
                } else {
                    colors.append(PointCloudColor(r: 0.5, g: 0.5, b: 0.5, a: 1.0))
                }
            }
        }

        guard !vertices.isEmpty else { return nil }
        return PointCloudData(id: sourceURL.path, vertices: vertices, colors: colors)
    }
}
