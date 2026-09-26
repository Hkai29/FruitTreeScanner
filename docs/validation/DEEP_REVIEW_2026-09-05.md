# 深层构建与跨模块复核：2026-09-05

> 以下保留修复前的检查证据；当前修复与完整回归结果见 [REPAIR_REVIEW_2026-09-05.md](REPAIR_REVIEW_2026-09-05.md)。

**结论：当前估产核心链路存在发布阻断问题，决策为 `do not merge`。**

这次使用真实 iOS Simulator XCTest 执行、完整 Release 真机目标构建和隔离修正对照。它替代上一轮仅靠代码路径阅读所得的优先级判断。最重要的新发现是：Metal 点云与融合算法的坐标约定不一致，而 ROI 候选也使用融合侧的错误坐标，掩盖了跨模块失配。

## 检查对象和构建证据

- 当前 HEAD：`c3ca0b26`，包含用户原有 7 个未提交 Swift 文件。
- 创建 `/tmp/fts-deep-review-src` 隔离源码副本。原有测试不改断言，只追加 9 项检查。执行完后核对源码 SHA-256，主工作区 App/工程文件与取样时一致。
- Xcode：`/Users/reece24/Downloads/Xcode-beta.app`，27.0 / 27A5194q。
- 缺失的 iOS 27 runtime 已下载安装，版本 24A5355p，下载量约 8.39 GB。
- 专用模拟器：FTS-DeepReview-20260905，iPhone 17 Pro，`2F3B9471-0B29-42AA-9C2B-C0A58FE3D49A`。未修改全局 Xcode selection。
- Release / generic iOS / arm64：独立 DerivedData 完整构建成功，实际 Swift 编译使用 `-O`。关闭签名，因此不是可分发 IPA 或 TestFlight 验收。
- Debug / iOS Simulator / build-for-testing / strict concurrency complete：构建成功。
- 工程包含全部 253 个 App Swift 文件的文件引用；App Sources 阶段 254 项，测试 Sources 阶段 19 项。
- Release 产物包含 `FruitsDetector.mlmodelc` 和 `default.metallib`。实测模型输入 RGB 320×320，输出 `[1,30,2100]`，26 类标签。
- 模拟器实际加载并执行了生产 CoreML 模型的 CPU 推理；黑色输入最大类别分数约 0.001377，输出形状符合契约。这是加载/推理冒烟验证，不是果园识别准确率测试。

| 执行组 | 结果 |
|---|---|
| 原有完整 XCTest，排除新增检查 | 472 通过，0 失败 |
| 新增跨模块/边界/性能/模型检查 | 9 项执行，2 通过、7 失败，共 8 处断言失败 |
| 隔离最小修正后的针对性对照 | 4 项通过，0 失败 |

原有全量测试通过不代表原型修正后全量通过：修正对照只运行了对应的 4 项检查。正式修复需要迁移原有错误坐标假设，并重新跑全部测试。

## 1. P0：Metal 与融合的相机坐标不一致，使真实点云匹配失败并造成跨视角重复计数

代码：

- `FruitTreeScanner/Core/RendererFrameSupport.swift` 的 `makeRotateToARCameraMatrix` 使用 `flipYZ`。
- `FruitTreeScanner/Core/RendererFrameRendering.swift` 的 `update(frame:)` 为 Metal 生成 local-to-world 矩阵。
- `FruitTreeScanner/Core/FusionValidatorProjection.swift:116` 的 `cameraPointFromImagePoint` 把内参反投影所得正 Z 光学坐标直接返回；随后乘的是 ARKit `cameraTransform`。
- 同文件第 67 行，反向投影又要求 `cameraPoint.z > 0.05`，排除了真实位于 AR 相机前方的负 Z 点。

Apple 对 ARCamera 的坐标定义可在 [ARCamera.transform](https://developer.apple.com/documentation/arkit/arcamera/transform) 核对。光学像素坐标与 AR 相机坐标的 Y/Z 方向需要一致转换。

实际复现：

1. 相机为单位变换，图像中心深度 2 米。Renderer 得到 `(0,0,-2)`，融合得到 `(0,0,+2)`，距离 **4.0 米**。
2. 给融合器提供真实前方 `(0,0,-2)` 的有效苹果点云候选，结果仍是 **imageOnly**，不是 fused。
3. 完整 builder 输入同一个物理苹果、两组相机观察。第一组相机在原点朝 -Z，第二组在 `(2,0,-2)` 朝 -X；两次中心深度均为 2 米，物理目标都是 `(0,0,-2)`。每组均有两次稳定观察。
4. 当前代码输出 **2 个 fused**，位置约为 `(0,0,2)` 和 `(4,0,-2)`。

为什么它仍可能输出“融合成功”：ROI 深度候选也调用同一个投影函数，错误的检测位置能匹配错误的 ROI 候选位置；真实 Metal 点云却在另一处。内部自洽掩盖了物理世界坐标失配。

隔离对照：仅修正正反投影的 Y/Z 转换，坐标差变为 **0**，真实前方候选变为 **fused**，完整链路只留下 **1 个**同一果实。

影响：零融合、错误融合位置、绕树后的重复计数、相机覆盖率及后续遮挡修正均可能受影响。不能靠放宽匹配距离修复，也不能靠增加模型训练量修复这处坐标错误。

## 2. P1：混合候选丢失几何类型语义，估重可突变 6.25 倍

代码：`ScanFusionPipelines.swift:284` 将 ROI 的 sourceCategory 写入混合轨迹，第 299 行在混入独立点云证据时清除 depthSupportRatio。但 `SimpleFruitGeometryEstimator.swift:107` 仅判断 sourceCategory 非空，就直接使用直径球体分支。

复现输入：同一份 4×10×4 cm 的梨形点集，密度固定 1 g/cm³，80 个点。向同位置、同直径的点云候选添加一致的 ROI 类别证据；合并前后没有改变物理点集。

| 状态 | 估重 |
|---|---:|
| 原点云候选，使用实测椭球几何 | 83.77573 g |
| 加入 ROI 后，混合候选被当作球体 | 523.59863 g |
| 隔离修正候选分支后的同一输入 | 83.77573 g |

这是候选来源与几何分支之间的契约错误；**6.25 倍是该合成用例的结果，不是对所有真实水果误差的统计**。

应显式区分纯 ROI、纯点云和混合候选，避免用“有类别”代替“只有 ROI 几何”。混合候选仍有可靠点集时应保留实测几何。

## 3. P1：在无效槽位上先做固定步长抽样，能把有效点全部丢掉

代码：`RendererPointCloudExport.swift:61–76` 用总槽位数确定 sampleStep，再过滤无效点；不是对有效点集合采样。

实际构造 1000 个槽位，其中 100 个有效点位于每十个槽位的第 2 个，其他槽位 confidence=0。未限量时返回 **100 点**；inputSampleLimit=100 时固定读取第 1、11、21…个槽位，返回 **0 点**。

这不是内存上限应该造成的结果。真实扫描中无效槽位来自深度范围、置信度和边缘过滤；若有效点布局与固定采样步长相关，用户可能看到采集有点，但最终分析/导出显著缺点甚至为空。

应对有效证据采用有界采样，或采用能避免固定相位遗漏的策略，并保留去噪和最大样本数限制。当前合成用例已复现，真实发生频率需要田间日志验证。

## 4. P1：合法世界坐标平移会把水果重量变为零

代码：`SimpleFruitGeometryMetrics.swift:8–16` 按绝对世界坐标 ±20 米过滤；`CanopyGeometryEstimator.swift:63–65` 也有同样限制。

实际将同一份梨形点集整体平移 25 米，尺寸、密度和相对几何全部不变：估重由 **83.7758 g → 0 g**。这是把世界原点距离误当作点集几何合法性。

`startRecording` 不重置 ARSession 的世界原点；同一扫描页面继续下一次扫描时，用户的位置可以逐渐离开初始原点。外部点云坐标也可能合法地超过此范围。

应在局部坐标中判断尺寸或离群值，保留原始世界位姿供显示/关联。不能仅扩大一个绝对常数掩盖问题。

## 5. P2：历史轨迹重建占用主线程，模拟器中耗时随输入明显增长

沿用真实 `ScanCoordinator.appendDetectedFruits` 路径，MainActor 上每帧输入 16 个稳定目标，2 Hz，累计 120 帧。归档目标没有增长，仍只有 48 条采样证据。

| 输入帧数 | 活动检测数 | 该次追加耗时 |
|---:|---:|---:|
| 20 | 320 | 17.9 ms |
| 60 | 960 | 52.7 ms |
| 120 | 1920 | 110.2 ms |

这是 Mac 上 iOS Simulator 的 Debug 测量，**不能当成真机 Release 的帧率结论**；首批冷启动峰值也不能简单归因于轨迹匹配。但在目标数量不变时，后续整理工作仍随历史量增加，足以说明当前全量重建缺少增量维护。

建议后台维护空间轨迹和投影缓存，主线程只接收摘要，再用 LiDAR 真机记录 Release 的耗时分布和长扫内存。

## 6. P2：转置 YOLO 输出解析失败，但当前生产模型恰好不触发

构造有效的 `[1,2100,30]` 单苹果输出，解析器误认 2100 是通道数，报出 `runtime label count 26 does not match output class count 2096`，实际检测数 **0**，预期 **1**。

当前打包模型实际是 `[1,30,2100]`，所以这不是当前所有识别失败的原因，优先级低于坐标错误。320 硬编码也属于更换输入规格时的风险。

## 并发和测试盲区

严格并发构建产生 87 条去重后的源码诊断，包括共享可变状态、跨隔离传递 ScanCoordinator、Renderer completion handler 捕获及主 actor UI 属性访问。它们是需要审计的边界，不能把每条警告都算成一次实际数据竞争。本轮未运行 Thread Sanitizer 或真机 GPU 竞争测试。

更关键的是：现有 472 项测试全部通过，但未把 Metal 的世界坐标作为 FusionValidator 的契约。大量 identity-camera 测试把正 Z 当作前方，让模块内部正确性掩盖了集成错误。正式修复需要增加基于真实相机约定的跨模块、跨视角和几何不变量测试。

上一轮保存失败恢复、停止丢弃在途推理、校准版本等发现仍需后续故障注入验证；本轮不把它们混在“已动态复现”清单中。上一轮关于 validDepthRatio 固定为 1 的说明也应收窄：纯 ROI 路径会用 candidate.depthSupportRatio 覆盖它；不能据此断言所有 ROI 质量都被写成 100%。

## 修复顺序及验收条件

1. 统一 Metal、ROI、检测去重和反投影坐标契约，迁移旧测试坐标；不能提高融合距离阈值来绕过错误。
2. 显式建模混合候选来源，保留实测几何；测试类别信息增加前后重量不突变。
3. 修复有效点抽样与世界坐标平移不变量，保留所有内存边界。
4. 完成 472 项原有测试和新增测试的整体验证，再测真机多视角、停止/恢复/写入失败流程。
5. 最后才用人工计数、称重和重复扫描评估真实误差；本次合成测试不能替代果园真值。

本轮对照原型只用来验证根因，未正式合并，未跑原型的完整兼容回归；不能把原型直接视为可发布修复。

## 证据文件

证据目录：`/Users/reece24/Documents/Codex/2026-09-05/FruitTreeScanner-deep-review/`

- `baseline.xcresult` / `baseline.log`：472 项原有测试。
- `adversarial.xcresult` / `adversarial.log`：9 项新增检查及数值输出。
- `prototype.xcresult` / `prototype.log`：4 项最小修正对照。
- `adversarial-tests.patch`：可复查的新增 XCTest 源码。
- `root-cause-prototype.patch`：隔离副本的最小根因验证修改。
- `release-iphoneos-build.log`、`debug-strict-build.log`、`strict-concurrency-warnings.txt`。
- `bundled-model-metadata.json`、`source-sha256.json`、各测试命令 JSON。

本轮只在主工作区新增/更新审查文档，原有 7 个未提交 App 文件和所有融合安全约束保持原样。未提交、未推送；未向用户物理设备安装测试版本。最终决策：**do not merge**。
