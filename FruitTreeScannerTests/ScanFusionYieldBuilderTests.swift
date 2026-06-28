import XCTest
import CoreVideo
@testable import FruitTreeScanner

final class ScanFusionYieldBuilderTests: XCTestCase {

    // MARK: - Helpers

    private let identityTransform = matrix_identity_float4x4

    private func pinholeIntrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(fx, 0, 0),
            SIMD3<Float>(0, fy, 0),
            SIMD3<Float>(cx, cy, 1)
        )
    }

    private func makeDepthMap(width: Int, height: Int, fillValue: Float) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowFloats = bytesPerRow / MemoryLayout<Float>.size
            for y in 0 ..< height {
                for x in 0 ..< width {
                    floatBuffer[y * rowFloats + x] = fillValue
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func makeAppleSphere(center: SIMD3<Float>, radius: Float = 0.03) -> [ColoredPoint] {
        var points: [ColoredPoint] = []
        let n = 30
        let phi = Float.pi * (3.0 - sqrt(5.0))
        for i in 0 ..< n {
            let y = 1 - (Float(i) / Float(n - 1)) * 2
            let radiusAtY = sqrt(1 - y * y)
            let theta = phi * Float(i)
            let x = cos(theta) * radiusAtY
            let z = sin(theta) * radiusAtY
            let scale: Float = (i % 3 == 0) ? radius : radius * 0.55
            points.append(ColoredPoint(
                pos: SIMD3<Float>(center.x + x * scale, center.y + y * scale, center.z + z * scale),
                r: 0.7, g: 0.20, b: 0.15
            ))
        }
        return points
    }

    private func appleParams() -> FruitVarietyParams {
        FruitVarietyParams(category: .apple)
    }

    private func emptyImageDiagnostics() -> ImageDetectionDiagnostics {
        ImageDetectionDiagnostics()
    }

    // MARK: - A.1 Empty point cloud → 0kg, zeroYieldReasons

    func testBuildEmptyInputReturnsZeroKgWithReasons() async {
        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.yieldFinalKg, 0, "空点云应输出 0kg")
        XCTAssertFalse(yield.diagnostics.zeroYieldReasons.isEmpty, "空点云应产生零产量原因")
        XCTAssertTrue(
            yield.diagnostics.zeroYieldReasons.contains("点云数量不足"),
            "点数不足应被诊断"
        )
    }

    // MARK: - A.2 No detections → cloudOnlyConservativeMode

    func testBuildCloudOnlyConservativeModeSetsDiagnostics() async {
        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))

        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertTrue(
            yield.diagnostics.cloudOnlyConservativeMode,
            "无图像检测时应进入 cloudOnly 保守模式"
        )
        XCTAssertFalse(
            yield.diagnostics.depthAvailable,
            "没有带深度的检测帧应标记深度不可用"
        )
    }

    // MARK: - A.3 With aligned detection depth → populated diagnostics

    func testBuildWithAlignedDetectionDepthPopulatesDiagnostics() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)

        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )

        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [detection],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            ),
            fusionConfig: FruitScanConfig(
                imageDetectionInterval: 10,
                minConfidence: 0.5,
                sizeTolerance: 0.35,
                sphericityThreshold: 0.5
            ),
            colorFilter: nil
        )

        let (yield, countResult) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(
            yield.diagnostics.imageDetectionCount, 1,
            "imageDetectionCount 应反映输入检测数量"
        )
        XCTAssertGreaterThan(
            yield.diagnostics.pointCloudCandidateCount, 0,
            "点云应聚类出至少 1 个候选"
        )
        XCTAssertGreaterThan(
            yield.diagnostics.fusedFruitCount, 0,
            "检测与候选匹配时应产生融合果实"
        )
        XCTAssertTrue(
            yield.diagnostics.depthAvailable,
            "检测帧含对齐深度图时应标记 depthAvailable"
        )
        XCTAssertFalse(
            yield.diagnostics.cloudOnlyConservativeMode,
            "有对齐检测深度时不应进入保守模式"
        )
        XCTAssertGreaterThanOrEqual(countResult.totalCount, 1)
    }

    func testBuildMixedAlignedAndUnalignedDetectionsUsesOnlyAlignedOnes() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))

        let aligned = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )
        let unaligned = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.70, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.95
        )

        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [aligned, unaligned],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: ClusterConfig(
                minPoints: 3,
                minDiameter: 0.015,
                maxDiameter: 0.20,
                baseEps: 0.1,
                sphericityThreshold: 0.5
            ),
            fusionConfig: FruitScanConfig(
                imageDetectionInterval: 10,
                minConfidence: 0.5,
                sizeTolerance: 0.35,
                sphericityThreshold: 0.5
            ),
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 1)
        XCTAssertTrue(yield.diagnostics.depthAvailable)
        XCTAssertFalse(yield.diagnostics.cloudOnlyConservativeMode)
        XCTAssertGreaterThan(yield.diagnostics.fusedFruitCount, 0)
    }

    // MARK: - A.4 Unaligned detections → cloudOnlyConservativeMode, depth unavailable

    func testBuildDetectionsWithoutAlignedDepthEntersConservativeMode() async {
        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9
        )

        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [detection],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertTrue(
            yield.diagnostics.cloudOnlyConservativeMode,
            "未携带对齐深度的检测应进入保守模式"
        )
        XCTAssertFalse(
            yield.diagnostics.depthAvailable,
            "未携带对齐深度应标记深度不可用"
        )
        XCTAssertEqual(
            yield.diagnostics.imageDetectionCount, 1,
            "imageDetectionCount 仍应记录输入检测数量"
        )
        XCTAssertEqual(
            yield.diagnostics.deduplicatedImageDetectionCount, 0,
            "未携带深度的检测不会参与融合去重"
        )
        XCTAssertEqual(
            yield.yieldFinalKg, 0,
            "未携带深度的检测不应产生伪融合产量"
        )
        XCTAssertTrue(
            yield.diagnostics.zeroYieldReasons.contains("深度不可用"),
            "未携带对齐深度时应明确诊断深度不可用"
        )
    }

    // MARK: - A.5 fruitCategory / fruitType in result

    func testBuildWritesFruitCategoryToResult() async {
        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.fruitCategory, "苹果", "零产量结果应写入 fruitCategory displayName")
    }

    func testBuildWritesFruitTypeWhenCategoryIsNil() async {
        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "自定义果",
            fruitCategory: nil,
            paramsSnapshot: [:],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.fruitCategory, "自定义果", "nil category 时应 fallback 到 fruitType")
    }

    func testBuildWritesColorDescription() async {
        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertFalse(yield.colorFilterDesc.isEmpty, "colorFilterDesc 不应为空")
    }

    func testBuildOffSeasonSkipsFruitPipelineWhenCrownModelIsUncalibrated() async {
        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))
        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil,
            season: .off
        )

        let (yield, countResult) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.methodUsed, "crown_untrained")
        XCTAssertEqual(yield.confidence, "manual_review")
        XCTAssertEqual(yield.nLidar, 0)
        XCTAssertEqual(countResult.totalCount, 0)
        XCTAssertEqual(yield.diagnostics.pointCloudCandidateCount, 0)
        XCTAssertTrue(yield.note.contains("尚未标定"))
    }
}
