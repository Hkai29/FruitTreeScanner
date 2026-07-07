// SIMDCompatibility.swift
// SIMD aliases and Codable adapters used by point cloud metadata.

import CoreGraphics
import Foundation
import simd

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
