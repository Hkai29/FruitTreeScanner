import simd

struct ColoredPoint: Sendable {
    let pos: SIMD3<Float>
    let r: Float
    let g: Float
    let b: Float
}
