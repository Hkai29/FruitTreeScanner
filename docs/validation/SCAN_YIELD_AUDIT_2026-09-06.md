# 扫描与产量核心专项检查

> 本文保留修复前证据。后续修复与完整回归见 [SCAN_YIELD_REPAIR_2026-09-06.md](SCAN_YIELD_REPAIR_2026-09-06.md)。

本轮聚焦几何、计数与遮挡补偿；生产逻辑未修改。新增四个探针，相关两组共 78 项测试通过。这是复现证据，不代表缺陷已修复。保留此前修改，未提交或推送。

## P1：观测次数被当作独立果实数量，放大遮挡补偿

调用链：ScanFusionPipelines.swift 将 stableEvidenceDetections（同一果实的多帧观测）传到 YieldResultComposer.swift:148，后者以 detections.count 作为 visualDetectionCount。OcclusionCorrector.swift:231 将它除以去重后的 lidarDetectionCount。

固定可见果实 10 个、冠层半径 0.3 m、深度 0.4 m、LiDAR 穿透参数 0.5 m、角度覆盖 1，仅把图像观测数由 20 改为 30：k 从 2.0 变为 3.0。可见重量固定时，最终遮挡修正重量增加 50%。这里隔离了补偿函数，尚未在完整实扫链路测得相同百分比；传入重复观测计数的生产调用链已确认。

根因是分子和分母口径不同，不能靠再限制最大 k 解决。应使用同一目标集合、同一去重口径的可见性证据，并验证重复帧不改变独立果实计数及遮挡结论。

## P1：非球形果实估重依赖世界坐标朝向

SimpleFruitGeometryMetrics.swift:14-19 分别取世界 X/Y/Z 的稳健跨度；SimpleFruitGeometryEstimator 用这三个跨度计算椭球体积。轴向跨度不是果实固有主轴尺寸。

构造同一 4×10×4 cm 梨形椭球表面 760 个点，密度 1 g/cm³，置信度与深度支持均为 1。点集绕 Z 旋转 45°，没有任何增删或缩放：估重由 59.41731 g 变为 93.00418 g，增加 56.527%。这是刚体旋转不变量被破坏，和模型识别误差无关。

上述绝对重量并非真实秤重精度评估，稳健分位数也影响其值；本案例证明的是相同证据仅改变朝向就产生重量偏差。修复需使用有遮挡/离群保护的主轴或形状拟合，不能未经验证直接引入 PCA 后就宣称真实精度改善。

## P2：按品类最大尺寸去重，可能合并相邻小果实

DetectionDeduplicator.swift:600 附近用 category.sizeRange.upperBound / 2 作为融合果实的默认距离阈值，没有使用实测尺寸或独立实例来源。草莓品类范围为 2–5 cm，因此默认阈值 2.5 cm。

输入两个 fused 草莓位置，中心相距 2.2 cm，输出只剩 1 个。对于直径 2 cm、互不重叠的两颗果实，这是允许尺寸范围内的潜在误合并。探针直接从去重入口输入两个实例，尚未证明真实扫描的上游会将该场景完整识别成两个候选；不能把输出 2→1 当作真实总体漏计率 50%。

## 未确认的假设

将一个苹果的两视角深度由中心 2 m 改为表面 1.96 m，运行完整 ScanFusionYieldBuilder，仍得到 1 个 fused 果实。该简化深度面场景未复现重复计数，不列为缺陷；它不覆盖全部视角/遮挡/噪声条件。

## 验证与后续

- iOS 27 模拟器，Xcode beta；YieldEstimatorTests 38 项，ScanFusionYieldBuilderTests 40 项，共 78 项通过。
- 日志 `/tmp/fts-yield-audit-final.log`；git diff --check 通过。
- 本轮未跑全量、Release 或真机 LiDAR。探针中的缺陷行为断言需要在正式修复时替换为正确不变量断言。
- 优先修复观测计数口径及几何旋转不变量，再处理相邻实例去重；可靠证据门槛不能放宽。

判断：**needs changes**。
