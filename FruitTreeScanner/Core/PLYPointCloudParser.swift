// PLYPointCloudParser.swift
// Property-driven ASCII and binary PLY point-cloud readers.

import Foundation
import SceneKit

extension PLYParserHelper {
    private static let maximumRenderedPointCount = 500_000
    private static let asciiReadChunkSize = 64 * 1_024
    private static let asciiLineFeed = UInt8(ascii: "\n")
    private static let asciiCarriageReturn = UInt8(ascii: "\r")

    static func parseASCIIPointCloud(
        data: Data,
        bodyStart: Int,
        schema: PLYPointCloudSchema,
        sourceURL: URL
    ) -> PointCloudData? {
        guard bodyStart >= 0,
              bodyStart <= data.count
        else { return nil }

        let targetCount = min(schema.vertexCount, maximumRenderedPointCount)
        var accumulator = makeASCIIAccumulator(
            targetCount: targetCount,
            sourceURL: sourceURL
        )
        var lineStart = bodyStart

        while accumulator.parsedVertexCount < schema.vertexCount, lineStart < data.endIndex {
            let newlineIndex = data[lineStart...].firstIndex(of: asciiLineFeed) ?? data.endIndex
            guard parseASCIIVertexLine(
                data[lineStart..<newlineIndex],
                schema: schema,
                targetCount: targetCount,
                accumulator: &accumulator
            ) else { return nil }

            guard newlineIndex < data.endIndex else { break }
            lineStart = data.index(after: newlineIndex)
        }

        return accumulator.makeResult(expectedVertexCount: schema.vertexCount)
    }

    static func parseStreamingASCIIPointCloud(
        at url: URL,
        bodyStart: Int,
        schema: PLYPointCloudSchema,
        sourceURL: URL
    ) -> PointCloudData? {
        guard bodyStart >= 0,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(bodyStart))
        } catch {
            return nil
        }

        let targetCount = min(schema.vertexCount, maximumRenderedPointCount)
        var accumulator = makeASCIIAccumulator(
            targetCount: targetCount,
            sourceURL: sourceURL
        )
        var pendingLine = Data()
        pendingLine.reserveCapacity(256)

        while accumulator.parsedVertexCount < schema.vertexCount {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: asciiReadChunkSize) ?? Data()
            } catch {
                return nil
            }
            if chunk.isEmpty { break }

            var lineStart = chunk.startIndex
            while accumulator.parsedVertexCount < schema.vertexCount,
                  let newlineIndex = chunk[lineStart...].firstIndex(of: asciiLineFeed) {
                if pendingLine.isEmpty {
                    guard parseASCIIVertexLine(
                        chunk[lineStart..<newlineIndex],
                        schema: schema,
                        targetCount: targetCount,
                        accumulator: &accumulator
                    ) else { return nil }
                } else {
                    pendingLine.append(chunk[lineStart..<newlineIndex])
                    guard parseASCIIVertexLine(
                        pendingLine,
                        schema: schema,
                        targetCount: targetCount,
                        accumulator: &accumulator
                    ) else { return nil }
                    pendingLine.removeAll(keepingCapacity: true)
                }
                lineStart = chunk.index(after: newlineIndex)
            }

            if accumulator.parsedVertexCount < schema.vertexCount, lineStart < chunk.endIndex {
                pendingLine.append(chunk[lineStart..<chunk.endIndex])
            }
        }

        if accumulator.parsedVertexCount < schema.vertexCount, !pendingLine.isEmpty {
            guard parseASCIIVertexLine(
                pendingLine,
                schema: schema,
                targetCount: targetCount,
                accumulator: &accumulator
            ) else { return nil }
        }

        return accumulator.makeResult(expectedVertexCount: schema.vertexCount)
    }

    private static func makeASCIIAccumulator(
        targetCount: Int,
        sourceURL: URL
    ) -> ASCIIPointCloudAccumulator {
        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        vertices.reserveCapacity(targetCount)
        colors.reserveCapacity(targetCount)
        return ASCIIPointCloudAccumulator(
            sourceID: sourceURL.path,
            targetCount: targetCount,
            vertices: vertices,
            colors: colors
        )
    }

    private struct ASCIIPointCloudAccumulator {
        let sourceID: String
        let targetCount: Int
        var vertices: [SCNVector3] = []
        var colors: [PointCloudColor] = []
        var parsedVertexCount = 0

        func makeResult(expectedVertexCount: Int) -> PointCloudData? {
            guard parsedVertexCount == expectedVertexCount,
                  vertices.count == targetCount
            else { return nil }
            return PointCloudData(id: sourceID, vertices: vertices, colors: colors)
        }
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

    private static func parseASCIIVertexLine(
        _ lineData: Data,
        schema: PLYPointCloudSchema,
        targetCount: Int,
        accumulator: inout ASCIIPointCloudAccumulator
    ) -> Bool {
        let trimmedLineData: Data
        if lineData.last == asciiCarriageReturn {
            trimmedLineData = lineData.dropLast()
        } else {
            trimmedLineData = lineData
        }

        guard let line = String(data: trimmedLineData, encoding: .utf8) else { return false }
        let values = line.split(whereSeparator: { $0.isWhitespace })
        if values.isEmpty { return true }
        guard values.count == schema.properties.count,
              let scalars = PLYPointCloudVertexDecoder.asciiScalars(values: values, schema: schema),
              let position = PLYPointCloudVertexDecoder.asciiPosition(scalars: scalars, schema: schema),
              let color = PLYPointCloudVertexDecoder.asciiColor(scalars: scalars, schema: schema)
        else { return false }
        if accumulator.parsedVertexCount < targetCount {
            accumulator.vertices.append(position)
            accumulator.colors.append(color)
        }
        accumulator.parsedVertexCount += 1
        if accumulator.parsedVertexCount.isMultiple(of: 4_096), Task.isCancelled {
            return false
        }
        return true
    }
}
