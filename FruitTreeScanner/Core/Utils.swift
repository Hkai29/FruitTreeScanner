// Utils.swift
// 原始来源：ios-depth-point-cloud (MIT License)
// 改动：新增 makeTreeFileName()，其余保持原样

import Foundation
import UIKit
import VideoToolbox

// MARK: - 文件命名（新增）

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

// MARK: - 原始工具函数（不改动）

/// 当前时间字符串（用于 PLY header 注释）
func getTimeStr() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.string(from: Date())
}

/// 保存文本文件到 Documents 目录
func saveFile(content: String, filename: String, folder: String) async throws {
    #if DEBUG
    print("Saving: \(folder)/\(filename)")
    #endif
    let url = getDocumentsDirectory()
        .appendingPathComponent(folder, isDirectory: true)
        .appendingPathComponent(filename)
    try content.write(to: url, atomically: true, encoding: .utf8)
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
    let bpr = CVPixelBufferGetBytesPerRow(input)
    let fmt = CVPixelBufferGetPixelFormatType(input)
    _ = CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt,
                            CVBufferCopyAttachments(input, .shouldPropagate)!, &copyOut)
    let output = copyOut!
    CVPixelBufferLockBaseAddress(input, .readOnly)
    CVPixelBufferLockBaseAddress(output, [])
    memcpy(CVPixelBufferGetBaseAddress(output),
           CVPixelBufferGetBaseAddress(input), h * bpr)
    CVPixelBufferUnlockBaseAddress(input, .readOnly)
    CVPixelBufferUnlockBaseAddress(output, [])
    return output
}

/// 任务委托协议（通知 UI 任务开始/完成）
protocol TaskDelegate: AnyObject {
    func didStartTask()
    func didFinishTask()
}

// MARK: - Codable 扩展（用于 JSON 序列化，原始不变）
extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        try self.init(c.decode([SIMD4<Float>].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode([columns.0, columns.1, columns.2, columns.3])
    }
}

extension simd_float3x3: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        try self.init(c.decode([SIMD3<Float>].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode([columns.0, columns.1, columns.2])
    }
}
