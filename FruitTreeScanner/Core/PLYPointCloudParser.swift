// PLYPointCloudParser.swift
// Property-driven ASCII and binary PLY point-cloud readers.

import Foundation
import SceneKit

extension PLYParserHelper {
    private static let maximumRenderedPointCount = 500_000

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
                  let scalars = PLYPointCloudVertexDecoder.asciiScalars(values: values, schema: schema),
                  let position = PLYPointCloudVertexDecoder.asciiPosition(scalars: scalars, schema: schema),
                  let color = PLYPointCloudVertexDecoder.asciiColor(scalars: scalars, schema: schema)
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
                guard let position = PLYPointCloudVertexDecoder.binaryPosition(
                    bytes: bytes,
                    vertexOffset: vertexOffset,
                    schema: schema
                ), let color = PLYPointCloudVertexDecoder.binaryColor(
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
}
