// Utils.swift
// 原始来源：ios-depth-point-cloud (MIT License)

import CoreGraphics
import Foundation
import UIKit
import VideoToolbox

// MARK: - 文件命名

/// 生成带树木编号 + GPS 的规范文件名
/// 格式：T001_20260714_103020_lat22.5678_lon114.1234.ply
func makeTreeFileName(treeID: String, lat: Double, lon: Double) -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd_HHmmss"
    let timeStr = df.string(from: Date())
    let latStr = String(format: "lat%.4f", lat)
    let lonStr = String(format: "lon%.4f", lon)
    return "\(treeID)_\(timeStr)_\(latStr)_\(lonStr).ply"
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
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.string(from: Date())
}

/// 保存二进制数据到 Documents 目录
func saveFile(data: Data, filename: String, folder: String) async throws {
    let url = getDocumentsDirectory()
        .appendingPathComponent(folder, isDirectory: true)
        .appendingPathComponent(filename)
    try data.write(to: url, options: .atomic)
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
