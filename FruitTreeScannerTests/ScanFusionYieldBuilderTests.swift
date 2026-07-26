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

    private func makeConfidenceMap(width: Int, height: Int, fillValue: UInt8) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0 ..< height {
                let rowPointer = baseAddress
                    .advanced(by: y * bytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                for x in 0 ..< width {
                    rowPointer[x] = fillValue
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func setDepth(_ depthMap: CVPixelBuffer, x: Int, y: Int, value: Float) {
        CVPixelBufferLockBaseAddress(depthMap, [])
        defer { CVPixelBufferUnlockBaseAddress(depthMap, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let rowFloats = bytesPerRow / MemoryLayout<Float>.size
        floatBuffer[clampedY * rowFloats + clampedX] = value
    }

    private func setDepthAtDetectionGrid(
        _ depthMap: CVPixelBuffer,
        detection: DetectedFruit,
        row: Int,
        col: Int,
        sampleGrid: Int = 9,
        imageSize: CGSize,
        value: Float
    ) {
        let normalizedPoint = CGPoint(
            x: detection.boundingBox.origin.x
                + detection.boundingBox.width * (CGFloat(col) + 0.5) / CGFloat(sampleGrid),
            y: detection.boundingBox.origin.y
                + detection.boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(sampleGrid)
        )
        let depthPoint = FusionValidator.depthSamplePoint(
            normalizedPoint: normalizedPoint,
            imageSize: imageSize,
            depthSize: CGSize(
                width: CVPixelBufferGetWidth(depthMap),
                height: CVPixelBufferGetHeight(depthMap)
            )
        )
        setDepth(depthMap, x: Int(depthPoint.x), y: Int(depthPoint.y), value: value)
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
                r: 0.7, g: 0.25, b: 0.15
            ))
        }
        return points
    }

    private func makePurpleSphere(center: SIMD3<Float>, radius: Float = 0.03) -> [ColoredPoint] {
        makeAppleSphere(center: center, radius: radius).map { point in
            ColoredPoint(pos: point.pos, r: 0.25, g: 0.10, b: 0.55)
        }
    }

    private func makeLeafGreenSphere(center: SIMD3<Float>, radius: Float = 0.03) -> [ColoredPoint] {
        makeAppleSphere(center: center, radius: radius).map { point in
            ColoredPoint(pos: point.pos, r: 0.32, g: 0.45, b: 0.18)
        }
    }

    func testSelectedFruitFilteringKeepsMatchingDetectionsAndCountsMismatches() {
        let detections = [
            DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.9),
            DetectedFruit(category: .pear, boundingBox: .zero, confidence: 0.9)
        ]

        let result = ScanFusionCategoryFilter.detectionFilterResult(
            detections,
            targetCategory: .apple
        )

        XCTAssertEqual(result.detections.map(\.category), [.apple])
        XCTAssertEqual(result.filteredBySelectedFruitTypeCount, 1)
    }

    func testSelectedFruitFilteringKeepsAllDetectionsWhenNoTargetCategory() {
        let detections = [
            DetectedFruit(category: .apple, boundingBox: .zero, confidence: 0.9),
            DetectedFruit(category: .pear, boundingBox: .zero, confidence: 0.9)
        ]

        let result = ScanFusionCategoryFilter.detectionFilterResult(
            detections,
            targetCategory: nil
        )

        XCTAssertEqual(result.detections.count, 2)
        XCTAssertEqual(result.filteredBySelectedFruitTypeCount, 0)
    }

    func testBuildDiagnosticsExposeSelectedFruitFilteredCount() async {
        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: [
                DetectedFruit(category: .pear, boundingBox: .zero, confidence: 0.9)
            ],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "apple",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: .default,
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.diagnostics.filteredBySelectedFruitTypeCount, 1)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 0)
    }

    private func ringPoints(
        angleStart: Float,
        angleEnd: Float,
        count: Int,
        radius: Float,
        color: SIMD3<Float>
    ) -> [ColoredPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let fraction = Float(index) / Float(count)
            let angle = angleStart + (angleEnd - angleStart) * fraction
            return ColoredPoint(
                pos: SIMD3<Float>(radius * cos(angle), 0, radius * sin(angle)),
                r: color.x,
                g: color.y,
                b: color.z
            )
        }
    }

    private func cameraTransform(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, forward))
        let up = simd_cross(forward, right)
        return simd_float4x4(
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(up.x, up.y, up.z, 0),
            SIMD4<Float>(forward.x, forward.y, forward.z, 0),
            SIMD4<Float>(eye.x, eye.y, eye.z, 1)
        )
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
        XCTAssertEqual(yield.occlusionK, 1, accuracy: 0.001, "没有有效可见果实时不应产生遮挡放大系数")
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

    func testBuildAppliesFruitColorFilterBeforeCloudClustering() async {
        let points = makePurpleSphere(center: SIMD3<Float>(0, 0, 2))
        let clusterConfig = ClusterConfig(
            minPoints: 3,
            minDiameter: 0.015,
            maxDiameter: 0.20,
            baseEps: 0.1,
            sphericityThreshold: 0.5
        )
        let unfilteredInput = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "自定义果",
            fruitCategory: nil,
            paramsSnapshot: [:],
            defaultParams: appleParams(),
            clusterConfig: clusterConfig,
            fusionConfig: .default,
            colorFilter: nil
        )
        let filteredInput = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: clusterConfig,
            fusionConfig: .default,
            colorFilter: FruitCategory.apple.colorFilter
        )

        let (unfilteredYield, _) = await ScanFusionYieldBuilder.build(from: unfilteredInput)
        let (filteredYield, _) = await ScanFusionYieldBuilder.build(from: filteredInput)

        XCTAssertGreaterThan(
            unfilteredYield.diagnostics.pointCloudClusterCandidateCount,
            0,
            "没有目标果色过滤时，通用果色点云仍会形成几何候选"
        )
        XCTAssertEqual(
            filteredYield.diagnostics.pointCloudClusterCandidateCount,
            0,
            "苹果扫描应在聚类前过滤掉不符合苹果颜色范围的点"
        )
        XCTAssertEqual(filteredYield.pointCloudSize, points.count, "结果仍应保留原始采样点数")
        XCTAssertFalse(filteredYield.colorFilterDesc.isEmpty)
    }

    func testBuildWritesRawPointCloudCanopyGeometryWhenFruitFilterRejectsLeaves() async {
        let canopyPoints: [ColoredPoint] = (0...100).map { index in
            let fraction = Float(index) / 100.0
            return ColoredPoint(
                pos: SIMD3<Float>(
                    -1.0 + 2.0 * fraction,
                    4.0 * fraction,
                    -0.5 + fraction
                ),
                r: 0.05,
                g: 0.80,
                b: 0.05
            )
        }
        let input = ScanFusionYieldBuilder.Input(
            points: canopyPoints,
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

        XCTAssertEqual(yield.treeHeightM, 3.6, accuracy: 0.001)
        XCTAssertEqual(
            yield.diagnostics.canopyOuterVolumeM3,
            Float.pi / 6 * 1.8 * 3.6 * 0.9,
            accuracy: 0.001
        )
        XCTAssertLessThan(yield.crownVolM3, yield.diagnostics.canopyOuterVolumeM3)
        XCTAssertEqual(yield.crownVolM3, yield.diagnostics.canopyVolumeM3, accuracy: 0.001)
        XCTAssertEqual(yield.diagnostics.canopyPointCount, 101)
        XCTAssertEqual(yield.diagnostics.canopyPreprocessedPointCount, 101)
        XCTAssertEqual(yield.diagnostics.canopyGroundFilteredPointCount, 0)
        XCTAssertEqual(yield.diagnostics.canopyTrunkFilteredPointCount, 0)
        XCTAssertEqual(yield.diagnostics.canopyNeighborFilteredPointCount, 0)
        XCTAssertEqual(yield.diagnostics.canopyClusterCount, 1)
        XCTAssertEqual(yield.diagnostics.canopyRobustPointCount, 91)
        XCTAssertEqual(yield.diagnostics.canopyHeightM, yield.treeHeightM, accuracy: 0.001)
        XCTAssertLessThan(yield.diagnostics.canopyEffectiveVolumeCoefficient, 0.05)
        XCTAssertLessThan(yield.diagnostics.canopyProjectionEffectiveCoefficient, 0.10)
        XCTAssertGreaterThan(yield.diagnostics.canopyVoxelSizeM, 0)
        XCTAssertEqual(
            yield.diagnostics.canopyPartitionSizeM,
            5 * yield.diagnostics.canopyVoxelSizeM,
            accuracy: 0.01
        )
        XCTAssertGreaterThan(yield.diagnostics.canopyPartitionCount, 1)
        XCTAssertEqual(yield.diagnostics.pointCloudClusterCandidateCount, 0)
    }

    func testBuildAppliesAppleLabColorGuardBeforeCloudClustering() async {
        let points = makeLeafGreenSphere(center: SIMD3<Float>(0, 0, 2))
        let clusterConfig = ClusterConfig(
            minPoints: 3,
            minDiameter: 0.015,
            maxDiameter: 0.20,
            baseEps: 0.1,
            sphericityThreshold: 0.5
        )
        let unfilteredInput = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "自定义果",
            fruitCategory: nil,
            paramsSnapshot: [:],
            defaultParams: appleParams(),
            clusterConfig: clusterConfig,
            fusionConfig: .default,
            colorFilter: nil
        )
        let appleFilteredInput = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
            defaultParams: appleParams(),
            clusterConfig: clusterConfig,
            fusionConfig: .default,
            colorFilter: FruitCategory.apple.colorFilter
        )

        let (unfilteredYield, _) = await ScanFusionYieldBuilder.build(from: unfilteredInput)
        let (filteredYield, _) = await ScanFusionYieldBuilder.build(from: appleFilteredInput)

        XCTAssertGreaterThan(
            unfilteredYield.diagnostics.pointCloudClusterCandidateCount,
            0,
            "没有目标果类过滤时，绿叶色球形点簇仍可能形成通用几何候选"
        )
        XCTAssertEqual(
            filteredYield.diagnostics.pointCloudClusterCandidateCount,
            0,
            "苹果扫描应在聚类前通过 Lab 色度护栏过滤掉绿叶色点簇"
        )
        XCTAssertTrue(filteredYield.colorFilterDesc.contains("Lab"))
    }

    func testBuildAppliesStatisticalOutlierRemovalBeforeCloudClustering() async {
        let inliers = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))
            + makeAppleSphere(center: SIMD3<Float>(0.002, 0, 2))
            + makeAppleSphere(center: SIMD3<Float>(-0.002, 0, 2))
        let outlier = ColoredPoint(
            pos: SIMD3<Float>(4, 0, 2),
            r: 0.70,
            g: 0.25,
            b: 0.15
        )
        let points = inliers + [outlier]
        let input = ScanFusionYieldBuilder.Input(
            points: points,
            savedDetections: [],
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
            fusionConfig: .default,
            colorFilter: FruitCategory.apple.colorFilter
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.pointCloudSize, points.count, "结果仍应保留原始点云规模")
        XCTAssertEqual(yield.diagnostics.pointCloudColorFilteredCount, points.count)
        XCTAssertGreaterThanOrEqual(yield.diagnostics.pointCloudOutlierPointCount, 1)
        XCTAssertLessThan(yield.diagnostics.pointCloudDenoisedPointCount, points.count)
        XCTAssertGreaterThan(yield.diagnostics.pointCloudOutlierRatio, 0)
        XCTAssertLessThan(yield.diagnostics.pointCloudOutlierRatio, 0.2)
        XCTAssertEqual(yield.diagnostics.pointCloudClusterCandidateCount, 1)
        XCTAssertEqual(yield.diagnostics.cloudOnlyFruitCount, 0)
    }

    func testBuildAppliesLocalCalibrationCorrectionToYieldAndCount() async {
        let points = makeAppleSphere(center: SIMD3<Float>(0, 0, 2))
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )

        func makeInput(
            calibrationCorrection: YieldCalibrationCorrection = .neutral
        ) -> ScanFusionYieldBuilder.Input {
            ScanFusionYieldBuilder.Input(
                points: points,
                savedDetections: [detection],
                imageDiagnostics: emptyImageDiagnostics(),
                fruitType: "苹果",
                fruitCategory: .apple,
                paramsSnapshot: [FruitCategory.apple.rawValue: appleParams()],
                defaultParams: appleParams(),
                clusterConfig: .default,
                fusionConfig: .default,
                colorFilter: FruitCategory.apple.colorFilter,
                calibrationCorrection: calibrationCorrection
            )
        }

        let (baselineYield, _) = await ScanFusionYieldBuilder.build(from: makeInput())
        let correction = YieldCalibrationCorrection(
            countFactor: 1.25,
            yieldFactor: 0.8,
            countSampleCount: 3,
            yieldSampleCount: 2
        )
        let (calibratedYield, _) = await ScanFusionYieldBuilder.build(
            from: makeInput(calibrationCorrection: correction)
        )

        XCTAssertGreaterThan(baselineYield.yieldFinalKg, 0)
        XCTAssertEqual(calibratedYield.yieldFinalKg, baselineYield.yieldFinalKg * 0.8, accuracy: 0.001)
        XCTAssertEqual(
            calibratedYield.nLidar,
            Int((Float(baselineYield.nLidar) * 1.25).rounded())
        )
        XCTAssertEqual(calibratedYield.diagnostics.localCalibrationCountFactor, 1.25, accuracy: 0.001)
        XCTAssertEqual(calibratedYield.diagnostics.localCalibrationYieldFactor, 0.8, accuracy: 0.001)
        XCTAssertEqual(calibratedYield.diagnostics.localCalibrationCountSampleCount, 3)
        XCTAssertEqual(calibratedYield.diagnostics.localCalibrationYieldSampleCount, 2)
        XCTAssertTrue(calibratedYield.note.contains("本地校准"))
    }

    func testOcclusionPointCoverageUsesTargetFruitColorInsteadOfBackgroundCanopy() async throws {
        guard let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0) else {
            XCTFail("depth map should be created")
            return
        }

        let backgroundRing = ringPoints(
            angleStart: 0,
            angleEnd: 2 * Float.pi,
            count: 180,
            radius: 1.2,
            color: SIMD3<Float>(0.10, 0.55, 0.12)
        )
        let fruitColorArc = ringPoints(
            angleStart: -Float.pi / 9,
            angleEnd: Float.pi / 9,
            count: 80,
            radius: 1.0,
            color: SIMD3<Float>(0.75, 0.24, 0.12)
        )
        let points = backgroundRing + fruitColorArc
        let fullPointCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
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
                baseEps: 0.08,
                sphericityThreshold: 0.5
            ),
            fusionConfig: .default,
            colorFilter: nil
        )

        let (yield, _) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertGreaterThan(fullPointCoverage, 0.75)
        XCTAssertLessThan(
            yield.diagnostics.pointCloudAngleCoverage,
            fullPointCoverage - 0.20,
            "遮挡估计应使用目标果色区域约束点云覆盖，而不是被全环背景枝叶点抬高"
        )
        XCTAssertEqual(
            yield.diagnostics.scanAngleCoverage,
            yield.diagnostics.pointCloudAngleCoverage,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(yield.correctionK, 1)
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
            yield.diagnostics.pointCloudClusterCandidateCount, 0,
            "全局点云应聚类出至少 1 个候选"
        )
        XCTAssertGreaterThan(
            yield.diagnostics.detectionDepthCandidateCount, 0,
            "有对齐检测深度时应生成 ROI 深度候选"
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

    func testBuildRequiresStableRepeatedDetectionForYieldWhenConfigured() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.95,
            timestamp: 10,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )

        let input = ScanFusionYieldBuilder.Input(
            points: makeAppleSphere(center: SIMD3<Float>(0, 0, 2)),
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
                sphericityThreshold: 0.5,
                minimumStableDetectionsForYield: 2
            ),
            colorFilter: nil
        )

        let (yield, countResult) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 1)
        XCTAssertGreaterThan(yield.diagnostics.detectionDepthCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 0)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 0)
        XCTAssertEqual(countResult.totalCount, 0)
        XCTAssertEqual(yield.yieldFinalKg, 0, accuracy: 0.001)
        XCTAssertTrue(
            yield.diagnostics.cloudOnlyConservativeMode,
            "配置要求多帧稳定观测时，单帧高置信深度检测不能直接产生产量"
        )
    }

    func testBuildUsesDetectionDepthROICandidateWhenGlobalCloudHasNoCluster() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )

        let input = ScanFusionYieldBuilder.Input(
            points: [],
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

        XCTAssertGreaterThan(yield.diagnostics.pointCloudCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.pointCloudClusterCandidateCount, 0)
        XCTAssertGreaterThan(yield.diagnostics.detectionDepthCandidateCount, 0)
        XCTAssertGreaterThan(yield.diagnostics.detectionDepthSupportRatio, 0)
        XCTAssertLessThanOrEqual(yield.diagnostics.detectionDepthSupportRatio, 1)
        XCTAssertGreaterThan(yield.diagnostics.fusedFruitCount, 0)
        XCTAssertFalse(yield.diagnostics.cloudOnlyConservativeMode)
        XCTAssertGreaterThan(yield.yieldFinalKg, 0)
        XCTAssertGreaterThanOrEqual(countResult.totalCount, 1)
    }

    func testBuildDoesNotPromoteRejectedROIDepthCandidateToCloudOnly() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )
        let input = ScanFusionYieldBuilder.Input(
            points: [],
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
                sizeTolerance: 0.001,
                sphericityThreshold: 0.5
            ),
            colorFilter: nil
        )

        let (yield, countResult) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 1)
        XCTAssertEqual(yield.diagnostics.fusedValidationCount, 0)
        XCTAssertEqual(yield.diagnostics.cloudOnlyFruitCount, 0)
        XCTAssertEqual(countResult.totalCount, 0)
        XCTAssertEqual(yield.yieldFinalKg, 0, accuracy: 0.001)
    }

    func testBuildMergesDuplicateDetectionDepthROICandidatesAcrossFrames() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.9,
                timestamp: 10,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.496, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.82,
                timestamp: 13,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
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

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.pointCloudClusterCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 1)
        XCTAssertEqual(yield.diagnostics.pointCloudCandidateCount, 1)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 1)
        XCTAssertEqual(countResult.totalCount, 1)
    }

    func testCombineCandidatesMergesOverlappingPointCloudAndROIDepthEvidence() {
        let cloudCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 2),
            diameter: 0.08,
            sphericity: 0.82,
            pointCount: 30,
            averageColor: SIMD3<Float>(0.7, 0.2, 0.15),
            points: [
                SIMD3<Float>(-0.02, 0, 2),
                SIMD3<Float>(0.02, 0, 2)
            ]
        )
        let roiDepthCandidate = FruitCandidate(
            position: SIMD3<Float>(0.01, 0, 2),
            diameter: 0.078,
            sphericity: 0.92,
            pointCount: 4,
            averageColor: SIMD3<Float>(0.75, 0.18, 0.12),
            points: [
                SIMD3<Float>(0.0, 0.0, 2),
                SIMD3<Float>(0.01, 0.0, 2),
                SIMD3<Float>(0.01, 0.01, 2)
            ],
            sourceCategory: .apple,
            depthSupportRatio: 4.0 / 81.0
        )

        let combined = ScanFusionYieldBuilder.combineCandidates(
            pointCloudCandidates: [cloudCandidate],
            detectionDepthCandidates: [roiDepthCandidate]
        )

        XCTAssertEqual(combined.count, 1, "重叠的点云候选和 ROI-depth 候选应合并为同一果实证据")
        let merged = combined[0]
        XCTAssertEqual(merged.sourceCategory, .apple, "合并后应保留 2D 检测带来的类别证据")
        XCTAssertNil(
            merged.depthSupportRatio,
            "已有完整点云候选时，低 ROI 支持率不应作为整个融合候选的置信度惩罚"
        )
        XCTAssertEqual(merged.pointCount, 34)
        XCTAssertGreaterThanOrEqual(merged.points.count, 5)
        XCTAssertEqual(merged.sphericity, 0.92, accuracy: 0.001)
    }

    func testBuildKeepsOverlappingDetectionDepthROICandidatesButCountsOnlySelectedCategory() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.9,
                timestamp: 10,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .orange,
                boundingBox: CGRect(x: 0.496, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.88,
                timestamp: 10.1,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "苹果",
            fruitCategory: .apple,
            paramsSnapshot: [
                FruitCategory.apple.rawValue: appleParams(),
                FruitCategory.orange.rawValue: FruitVarietyParams(category: .orange)
            ],
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

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 1)
        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 2)
        XCTAssertEqual(yield.diagnostics.pointCloudCandidateCount, 1)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 1)
        XCTAssertEqual(countResult.totalCount, 1)
        XCTAssertEqual(countResult.fruitCountsEnum[.apple], 1)
        XCTAssertEqual(countResult.fruitCountsEnum[.orange], 0)
    }

    func testBuildCountsMultipleCategoriesWhenNoSelectedFruitCategory() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.9,
                timestamp: 10,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .orange,
                boundingBox: CGRect(x: 0.496, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.88,
                timestamp: 10.1,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
            imageDiagnostics: emptyImageDiagnostics(),
            fruitType: "自定义果",
            fruitCategory: nil,
            paramsSnapshot: [
                FruitCategory.apple.rawValue: appleParams(),
                FruitCategory.orange.rawValue: FruitVarietyParams(category: .orange)
            ],
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

        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 2)
        XCTAssertEqual(countResult.totalCount, 2)
        XCTAssertEqual(countResult.fruitCountsEnum[.apple], 1)
        XCTAssertEqual(countResult.fruitCountsEnum[.orange], 1)
    }

    func testBuildUsesDetectionCameraAnglesForOcclusionWhenPointCloudIsSparse() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let target = SIMD3<Float>(0, 0, 2)
        let cameraEyes = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(2, 0, 2),
            SIMD3<Float>(0, 0, 4),
            SIMD3<Float>(-2, 0, 2)
        ]
        let detections = cameraEyes.enumerated().map { index, eye in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.9,
                timestamp: 10 + TimeInterval(index * 3),
                cameraTransform: cameraTransform(eye: eye, target: target),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        }

        func makeInput(_ detections: [DetectedFruit]) -> ScanFusionYieldBuilder.Input {
            ScanFusionYieldBuilder.Input(
                points: [],
                savedDetections: detections,
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
        }

        let (singleViewYield, _) = await ScanFusionYieldBuilder.build(from: makeInput([detections[0]]))
        let (multiViewYield, multiViewCount) = await ScanFusionYieldBuilder.build(from: makeInput(detections))

        XCTAssertGreaterThan(singleViewYield.correctionK, 1)
        XCTAssertLessThan(multiViewYield.correctionK, singleViewYield.correctionK)
        XCTAssertEqual(multiViewYield.diagnostics.detectionDepthCandidateCount, 1)
        XCTAssertEqual(multiViewYield.diagnostics.fusedFruitCount, 1)
        XCTAssertGreaterThan(
            multiViewYield.diagnostics.cameraAngleCoverage,
            multiViewYield.diagnostics.pointCloudAngleCoverage
        )
        XCTAssertGreaterThan(multiViewYield.diagnostics.validationSourceReliability, 0)
        XCTAssertLessThanOrEqual(multiViewYield.diagnostics.validationSourceReliability, 1)
        XCTAssertEqual(
            multiViewYield.diagnostics.scanAngleCoverage,
            max(
                multiViewYield.diagnostics.pointCloudAngleCoverage,
                multiViewYield.diagnostics.cameraAngleCoverage * multiViewYield.diagnostics.validationSourceReliability
            ),
            accuracy: 0.001
        )
        XCTAssertEqual(multiViewCount.totalCount, 1)
    }

    func testBuildIgnoresLowConfidenceDepthCameraAnglesForOcclusion() async {
        let reliableDepthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let lowConfidenceDepthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        let lowConfidenceMap = makeConfidenceMap(width: 256, height: 192, fillValue: 0)
        XCTAssertNotNil(reliableDepthMap)
        XCTAssertNotNil(lowConfidenceDepthMap)
        XCTAssertNotNil(lowConfidenceMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let target = SIMD3<Float>(0, 0, 2)
        let boundingBox = CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012)
        let reliableDetection = DetectedFruit(
            category: .apple,
            boundingBox: boundingBox,
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: cameraTransform(eye: SIMD3<Float>(0, 0, 0), target: target),
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: reliableDepthMap
        )
        let lowConfidenceDetections = [
            SIMD3<Float>(2, 0, 2),
            SIMD3<Float>(0, 0, 4),
            SIMD3<Float>(-2, 0, 2)
        ].enumerated().map { index, eye in
            DetectedFruit(
                category: .apple,
                boundingBox: boundingBox,
                confidence: 0.88,
                timestamp: 13 + TimeInterval(index * 3),
                cameraTransform: cameraTransform(eye: eye, target: target),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: lowConfidenceDepthMap,
                depthConfidenceMap: lowConfidenceMap
            )
        }

        func makeInput(_ detections: [DetectedFruit]) -> ScanFusionYieldBuilder.Input {
            ScanFusionYieldBuilder.Input(
                points: [],
                savedDetections: detections,
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
        }

        let (baselineYield, _) = await ScanFusionYieldBuilder.build(from: makeInput([reliableDetection]))
        let (withLowConfidenceYield, countResult) = await ScanFusionYieldBuilder.build(
            from: makeInput([reliableDetection] + lowConfidenceDetections)
        )

        XCTAssertEqual(withLowConfidenceYield.diagnostics.detectionDepthCandidateCount, 1)
        XCTAssertEqual(withLowConfidenceYield.diagnostics.fusedFruitCount, 1)
        XCTAssertEqual(
            withLowConfidenceYield.diagnostics.cameraAngleCoverage,
            baselineYield.diagnostics.cameraAngleCoverage,
            accuracy: 0.001,
            "低置信度 ROI 深度不能扩大相机角度覆盖并降低遮挡补偿"
        )
        XCTAssertEqual(
            withLowConfidenceYield.correctionK,
            baselineYield.correctionK,
            accuracy: 0.001
        )
        XCTAssertEqual(countResult.totalCount, 1)
    }

    func testBuildFlagsLowCoverageStrongOcclusionAsManualReview() async throws {
        guard let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0) else {
            XCTFail("depth map should be created")
            return
        }

        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: cameraTransform(
                eye: SIMD3<Float>(0, 0, 0),
                target: SIMD3<Float>(0, 0, 2)
            ),
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )
        let input = ScanFusionYieldBuilder.Input(
            points: [],
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

        XCTAssertEqual(countResult.totalCount, 1)
        XCTAssertGreaterThan(yield.correctionK, 1.35)
        XCTAssertLessThan(yield.diagnostics.scanAngleCoverage, 0.35)
        XCTAssertEqual(yield.confidence, "manual_review")
        XCTAssertTrue(yield.methodUsed.hasSuffix("_coverage_review"))
        XCTAssertTrue(yield.note.contains("扫描角度覆盖"))
        XCTAssertTrue(yield.note.contains("复核"))
    }

    func testBuildDoesNotUnionCameraAnglesAcrossDifferentFruitTracks() async {
        let leftDepthMap = makeDepthMap(width: 256, height: 192, fillValue: 1.5)
        let rightDepthMap = makeDepthMap(width: 256, height: 192, fillValue: 1.5)
        XCTAssertNotNil(leftDepthMap)
        XCTAssertNotNil(rightDepthMap)
        guard let leftDepthMap, let rightDepthMap else { return }

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let leftFruit = SIMD3<Float>(-0.5, 0, 2)
        let rightFruit = SIMD3<Float>(0.5, 0, 2)
        let bbox = CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: bbox,
                confidence: 0.9,
                timestamp: 10,
                cameraTransform: cameraTransform(eye: SIMD3<Float>(-2, 0, 2), target: leftFruit),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: leftDepthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: bbox,
                confidence: 0.88,
                timestamp: 13,
                cameraTransform: cameraTransform(eye: SIMD3<Float>(2, 0, 2), target: rightFruit),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: rightDepthMap
            )
        ]

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
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

        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 2)
        XCTAssertEqual(countResult.totalCount, 2)
        XCTAssertLessThan(
            yield.diagnostics.cameraAngleCoverage,
            0.08,
            "相机覆盖应按单果轨迹计算，不能把不同果实的单侧观察合并成多角度覆盖"
        )
        XCTAssertEqual(
            yield.diagnostics.scanAngleCoverage,
            yield.diagnostics.pointCloudAngleCoverage,
            accuracy: 0.001
        )
    }

    func testBuildIgnoresUnalignedDetectionCameraAnglesForOcclusion() async {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)

        let intrinsics = pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540)
        let imageSize = CGSize(width: 1920, height: 1080)
        let target = SIMD3<Float>(0, 0, 2)
        let aligned = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: cameraTransform(eye: SIMD3<Float>(0, 0, 0), target: target),
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let unalignedCameraOnly = [
            SIMD3<Float>(2, 0, 2),
            SIMD3<Float>(0, 0, 4),
            SIMD3<Float>(-2, 0, 2)
        ].enumerated().map { index, eye in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.494, y: 0.494, width: 0.012, height: 0.012),
                confidence: 0.8,
                timestamp: 20 + TimeInterval(index * 3),
                cameraTransform: cameraTransform(eye: eye, target: target),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: nil
            )
        }

        func makeInput(_ detections: [DetectedFruit]) -> ScanFusionYieldBuilder.Input {
            ScanFusionYieldBuilder.Input(
                points: [],
                savedDetections: detections,
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
        }

        let (alignedOnlyYield, _) = await ScanFusionYieldBuilder.build(from: makeInput([aligned]))
        let (withUnalignedYield, _) = await ScanFusionYieldBuilder.build(
            from: makeInput([aligned] + unalignedCameraOnly)
        )

        XCTAssertEqual(withUnalignedYield.diagnostics.deduplicatedImageDetectionCount, 1)
        XCTAssertEqual(
            withUnalignedYield.diagnostics.cameraAngleCoverage,
            alignedOnlyYield.diagnostics.cameraAngleCoverage,
            accuracy: 0.001
        )
        XCTAssertEqual(
            withUnalignedYield.correctionK,
            alignedOnlyYield.correctionK,
            accuracy: 0.001
        )
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

    func testBuildDoesNotCountTrackedImageWithoutFusedDepthCandidate() async {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        XCTAssertNotNil(depthMap)
        guard let depthMap else { return }
        let imageSize = CGSize(width: 900, height: 900)
        let intrinsics = pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450)
        let detections = [
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
                confidence: 0.9,
                timestamp: 10,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            ),
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
                confidence: 0.82,
                timestamp: 13,
                cameraTransform: identityTransform,
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        ]
        for row in 4...5 {
            for col in 1...8 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detections[0],
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
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

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.deduplicatedImageDetectionCount, 2)
        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.validatedFruitCount, 0)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 0)
        XCTAssertEqual(yield.diagnostics.fusedValidationCount, 0)
        XCTAssertEqual(yield.diagnostics.trackedImageFruitCount, 0)
        XCTAssertEqual(yield.diagnostics.imageOnlyFruitCount, 0)
        XCTAssertEqual(yield.diagnostics.cloudOnlyFruitCount, 0)
        XCTAssertEqual(countResult.totalCount, 0)
        XCTAssertTrue(
            yield.diagnostics.cloudOnlyConservativeMode,
            "未融合到有效深度候选的重复图像轨迹不能进入产量估计"
        )
        XCTAssertEqual(yield.yieldFinalKg, 0, accuracy: 0.001)
    }

    func testBuildDoesNotLetImageOnlyObservationBoostReliableFusionConfidence() async throws {
        let depthMap = try XCTUnwrap(makeDepthMap(width: 90, height: 90, fillValue: 2.0))
        let imageSize = CGSize(width: 900, height: 900)
        let intrinsics = pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450)
        let primaryDetection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.48, y: 0.48, width: 0.04, height: 0.04),
            confidence: 0.9,
            timestamp: 10,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let laterImageOnlyObservation = DetectedFruit(
            category: .apple,
            boundingBox: primaryDetection.boundingBox,
            confidence: 0.8,
            timestamp: 13,
            cameraTransform: identityTransform,
            cameraIntrinsics: intrinsics,
            imageSize: imageSize,
            depthMap: depthMap
        )
        let fusionConfig = FruitScanConfig(
            imageDetectionInterval: 10,
            minConfidence: 0.5,
            sizeTolerance: 0.35,
            sphericityThreshold: 0.5,
            minimumStableDetectionsForYield: 1,
            stableDetectionTimeWindow: 4.0
        )

        func makeInput(detections: [DetectedFruit]) -> ScanFusionYieldBuilder.Input {
            ScanFusionYieldBuilder.Input(
                points: [],
                savedDetections: detections,
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
                fusionConfig: fusionConfig,
                colorFilter: nil
            )
        }

        let (singleEvidenceYield, _) = await ScanFusionYieldBuilder.build(
            from: makeInput(detections: [primaryDetection])
        )
        let (mixedEvidenceYield, _) = await ScanFusionYieldBuilder.build(
            from: makeInput(detections: [primaryDetection, laterImageOnlyObservation])
        )

        XCTAssertEqual(mixedEvidenceYield.diagnostics.deduplicatedImageDetectionCount, 2)
        XCTAssertEqual(singleEvidenceYield.diagnostics.fusedFruitCount, 1)
        XCTAssertEqual(mixedEvidenceYield.diagnostics.fusedFruitCount, 1)
        XCTAssertEqual(singleEvidenceYield.validatedFruits.count, 1)
        XCTAssertEqual(mixedEvidenceYield.validatedFruits.count, 1)
        XCTAssertEqual(
            mixedEvidenceYield.validatedFruits[0].confidence,
            singleEvidenceYield.validatedFruits[0].confidence,
            accuracy: 0.0001,
            "imageOnly 观测不能提高可靠 fused 轨迹的置信度"
        )
        XCTAssertEqual(
            mixedEvidenceYield.yieldBVisibleKg,
            singleEvidenceYield.yieldBVisibleKg,
            accuracy: 0.0001,
            "imageOnly 观测不能进入可靠可见产量权重"
        )
    }

    func testTrackedImageEvidenceDoesNotExpandCameraAngleCoverageForOcclusion() async {
        let depthMap = makeDepthMap(width: 90, height: 90, fillValue: 3.0)
        XCTAssertNotNil(depthMap)
        guard let depthMap else { return }
        let imageSize = CGSize(width: 900, height: 900)
        let intrinsics = pinholeIntrinsics(fx: 1000, fy: 1000, cx: 450, cy: 450)
        let target = SIMD3<Float>(0, 0, 2)
        let cameraEyes = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(2, 0, 2),
            SIMD3<Float>(0, 0, 4),
            SIMD3<Float>(-2, 0, 2)
        ]
        let detections = cameraEyes.enumerated().map { index, eye in
            DetectedFruit(
                category: .apple,
                boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
                confidence: 0.88,
                timestamp: 10 + TimeInterval(index * 3),
                cameraTransform: cameraTransform(eye: eye, target: target),
                cameraIntrinsics: intrinsics,
                imageSize: imageSize,
                depthMap: depthMap
            )
        }
        for row in 4...5 {
            for col in 1...8 {
                setDepthAtDetectionGrid(
                    depthMap,
                    detection: detections[0],
                    row: row,
                    col: col,
                    imageSize: imageSize,
                    value: 2.0
                )
            }
        }

        let input = ScanFusionYieldBuilder.Input(
            points: [],
            savedDetections: detections,
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

        XCTAssertEqual(yield.diagnostics.trackedImageFruitCount, 0)
        XCTAssertEqual(yield.diagnostics.validationSourceReliability, 0, accuracy: 0.001)
        XCTAssertEqual(yield.diagnostics.cameraAngleCoverage, 0, accuracy: 0.001)
        XCTAssertEqual(
            yield.diagnostics.scanAngleCoverage,
            yield.diagnostics.pointCloudAngleCoverage,
            accuracy: 0.001
        )
        XCTAssertEqual(countResult.totalCount, 0)
        XCTAssertEqual(yield.yieldFinalKg, 0, accuracy: 0.001)
    }

    func testLowConfidenceFusedEvidenceReducesValidationReliability() async throws {
        let depthMap = makeDepthMap(width: 256, height: 192, fillValue: 2.0)
        XCTAssertNotNil(depthMap)
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.55,
            timestamp: 10,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap
        )
        let input = ScanFusionYieldBuilder.Input(
            points: [],
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

        XCTAssertEqual(yield.diagnostics.fusedValidationCount, 1)
        let fusedConfidence = try XCTUnwrap(countResult.validatedFruits.first?.confidence)
        XCTAssertEqual(yield.diagnostics.validationSourceReliability, fusedConfidence, accuracy: 0.001)
        XCTAssertLessThan(yield.diagnostics.validationSourceReliability, 0.65)
        XCTAssertGreaterThan(yield.diagnostics.validationSourceReliability, 0.40)
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
            yield.diagnostics.fusedValidationCount,
            0,
            "未携带深度的检测不应产生伪融合结果"
        )
        XCTAssertEqual(
            yield.diagnostics.cloudOnlyFruitCount,
            0,
            "无对齐深度的检测不应凭点云候选产生水果计数"
        )
        XCTAssertEqual(
            yield.yieldFinalKg,
            0,
            accuracy: 0.001,
            "无图像+深度融合证据时不应产生产量估计"
        )
    }

    func testBuildFailsClosedAndPreservesReasonWhenConfidenceCopyFailed() async throws {
        let depthMap = try XCTUnwrap(makeDepthMap(width: 256, height: 192, fillValue: 2.0))
        let detection = DetectedFruit(
            category: .apple,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
            confidence: 0.9,
            cameraTransform: identityTransform,
            cameraIntrinsics: pinholeIntrinsics(fx: 500, fy: 500, cx: 960, cy: 540),
            imageSize: CGSize(width: 1920, height: 1080),
            depthMap: depthMap,
            depthConfidenceProvenance: .copyFailed
        )
        let input = ScanFusionYieldBuilder.Input(
            points: makeAppleSphere(center: SIMD3<Float>(0, 0, 2)),
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

        let (yield, countResult) = await ScanFusionYieldBuilder.build(from: input)

        XCTAssertEqual(yield.diagnostics.imageDetectionCount, 1)
        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.fusedFruitCount, 0)
        XCTAssertTrue(yield.diagnostics.cloudOnlyConservativeMode)
        XCTAssertEqual(yield.diagnostics.depthConfidenceFailureReason, DepthConfidenceProvenance.copyFailureReason)
        XCTAssertTrue(yield.diagnostics.zeroYieldReasons.contains(DepthConfidenceProvenance.copyFailureReason))
        XCTAssertTrue(countResult.validatedFruits.isEmpty)
        XCTAssertEqual(yield.yieldFinalKg, 0, accuracy: 0.001)
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
        XCTAssertEqual(yield.diagnostics.pointCloudClusterCandidateCount, 0)
        XCTAssertEqual(yield.diagnostics.detectionDepthCandidateCount, 0)
        XCTAssertTrue(yield.note.contains("尚未标定"))
    }
}
