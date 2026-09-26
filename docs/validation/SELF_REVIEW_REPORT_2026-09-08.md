# FruitTreeScanner 自检报告

结论：**do not merge**。确认 5 项待处理问题。完整 iOS 模拟器 XCTest 为 **507 项：506 通过、1 项失败（9 处断言失败），0 跳过**；单独复跑失败测试仍失败。Release generic iOS 未签名构建成功。

## 已确认问题

### 1. P1 — 会话失败后，“重新扫描”没有重新启动 ARSession

- 位置：[ScanCoordinatorWorkflows.swift:269](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanCoordinatorWorkflows.swift:269)、[ScanCoordinatorWorkflows.swift:204](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanCoordinatorWorkflows.swift:204)、[ScanView+Actions.swift:186](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/ScanView+Actions.swift:186)。
- 触发：扫描中发生 session failure，用户在恢复提示中选择重新扫描。
- 调用链：`handleSessionFailure` 调用 `session.pause()`；`restartAfterInterruption → beginNewScan → coordinator.startRecording` 只清空数据、改变生命周期并设置 `renderer.isRecording = true`。`Renderer.isRecording.didSet` 也只重置点云/计时。全仓唯一的 `session.run(config)` 位于 `bind` 使用的初始配置方法，现有 `MetalView.updateUIView` 不会重新 bind。
- 后果：界面进入“扫描中”，但暂停的会话不再产出新帧，用户无法通过该恢复入口继续采集。
- 证据：当前源码的完整调用链；本机 iOS 27 SDK `ARSession.h:111–115` 明确说明暂停后必须再次调用 `run` 才会接收更新。可对照 [Apple ARSession.pause 文档](https://developer.apple.com/documentation/arkit/arsession/pause())。本轮未在真机注入 session failure。
- 最小修复：增加明确的失败会话重启路径，成功重启后再公布 recording 状态；根据新扫描语义处理 tracking reset。不要把用户普通暂停/继续与失败恢复混为同一操作。
- 缺失测试：通过可替换的 session 驱动验证 `pause → failure recovery → run`，随后在 LiDAR 设备确认帧时间戳、点数确实恢复增长。现有测试只证明状态与缓存重置，不能证明 ARSession 重启。
- 归属：已有问题；本次统一新扫描入口的修改仍未覆盖它。

### 2. P1 — 新增批量导出测试与记录初始化契约冲突，完整测试无法通过

- 位置：[BatchExportServiceTests.swift:24](/Users/reece24/FruitTreeScanner/FruitTreeScannerTests/BatchExportServiceTests.swift:24)，关联 [ScanHistoryStore.swift:173](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanHistoryStore.swift:173)。
- 触发：运行 `testBatchExportRejectsInvalidAndOverflowingTotalsInEveryFormat`。
- 原因：该测试通过 `makeRecord` 构造负数量、NaN 重量和负重量，再要求导出器抛错；但生产 `ScanFileRecord.init` 已把这些值转换成 0，并保留 `.complete`。导出器接收到的是规范化后的数据。
- 实测：三种这类输入 × CSV/Excel/JSON 三种格式，共产生 9 处失败断言。整数总和及浮点总和溢出两组案例被正确拒绝。全量运行与独立复跑结果一致。
- 最小修复：明确非法原始数据应在哪一层被拒绝。若保留记录初始化的兼容行为，应在输入边界验证拒绝规则，并分别测试记录规范化和导出总和溢出；若要求非法记录始终不可导出，则需保留其无效状态，而不是在转换成 0 后期待导出器恢复原始信息。
- 归属：本次未提交差异新增的测试问题。不能据此宣称所有导出溢出保护失效，也不能继续沿用旧报告的“全量通过”。

### 3. P2 — 极大合法数量可使界面汇总先于导出保护发生整数溢出

- 位置：[BatchExportContentView.swift:36](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/BatchExportContentView.swift:36)、[DashboardAnalyticsSheets.swift:15](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/DashboardAnalyticsSheets.swift:15)。
- 触发：历史伴随 JSON 中一条数量为 `Int.max`，另有至少 1 个果实的完整记录；打开产量报告或同时选择这些记录。
- 证据：使用当前 `PLYCompanionResultReader.swift` 和直接提取的生产 `ScanFileRecord`，在 iOS 27 模拟器运行独立探针。读取器返回 `.complete` 和 `9223372036854775807`，该值与 1 相加报告 overflow。两处 SwiftUI 属性仍使用普通 `Int` 加法，渲染时会触发溢出陷阱。探针使用报告溢出的加法确认边界，没有故意令 App 崩溃。
- 后果：用户尚未点击导出就可能崩溃，`BatchExportFormatting.totalFruitCount` 的安全求和覆盖不到这个调用阶段。现实触发通常需要异常、损坏或外部编辑的历史数据。
- 最小修复：让展示与导出共同使用能表达无效/超界状态的汇总函数，界面显示可解释的错误状态。新增“读入极大值 → 界面汇总”的测试；不要只测导出服务。
- 归属：已有消费者缺口；本次整数读取精度和服务层溢出修复没有覆盖界面。

### 4. P2 — 覆盖率仍把米制深度当作裁剪坐标，未与实际点云反投影统一

- 位置：[RendererDepthCoverage.swift:363](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/RendererDepthCoverage.swift:363)。
- 触发：实时深度覆盖体素更新。
- 原因：代码构造 `(fx * depth, fy * depth, -depth, 1)` 并乘 `(projection * view).inverse`。这个输入既不是正确的齐次裁剪坐标，也不是规范化设备坐标；米制深度不能直接用作裁剪空间 Z。原始深度像素还直接按显示视口的归一化坐标解释，未完成图像尺寸及方向映射。
- 对照：实际 Metal 点云使用 `cameraIntrinsics.inverse * imagePixel * depth` 再转世界坐标；本次 `FusionValidatorProjection` 修正了相机轴向，但覆盖率入口仍保留另一套不一致的算法。
- 数学反例：在 iOS 模拟器用近裁剪面 0.001 的合成无限远反向 Z 投影矩阵验证，位于相机前 2 m 的中心点应生成裁剪坐标 `(0, 0, 0.001, 2)`；代入当前构造法，逆投影所得 Z 是 `+0.0005`，而不是 `-2`。
- 后果：覆盖体素的位置及其衍生覆盖指标不能可靠反映实际被扫描表面，影响采集指导。这不是对真机误差大小的测量，本轮也没有据此推断重量误差百分比。
- 最小修复：按深度分辨率映射回相机图像像素，复用与点云/融合一致的内参反投影与相机到世界变换，并检查有限值及齐次坐标。补中心/偏轴像素、多方向、多分辨率及相机位姿的跨链路一致性测试。
- 归属：已有覆盖率实现问题，位于本次投影修正的相关调用链；数学探针使用合成矩阵，不是实机 ARCamera 帧。

### 5. P2 — YOLO 契约解析失败没有进入持久化结果的错误诊断

- 位置：[ImageDetectorInference.swift:177](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ImageDetectorInference.swift:177)，关联 [ImageDetectionHelpers.swift:217](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ImageDetectionHelpers.swift:217)。
- 触发：模型张量通道轴歧义、输出类数与标签契约不匹配等解析失败。
- 原因：解析器返回 `labelMappingFailureReason`，但推理入口仍调用成功记录方法 `recordCoreMLDetection`，将 `lastDetectionError` 清空。随后错误仅传到调试状态、日志和失败样本，未写回供 `ScanDiagnosticsBuilder` 消费的 `ImageDetectionDiagnostics`。
- 后果：普通单次结果 JSON 的 `diagnostics.imageFailureReason` 为空，零产量信息会更像“没有检测到果实”，无法从普通结果文件区分模型输出不兼容。调试快照仍保留错误，不能表述为所有诊断都丢失。
- 证据：逐项追踪解析器、推理回调、诊断记录器、结果诊断构造及 JSON 写入；独立 iOS 探针复用实际记录器，失败场景的成功记录调用产生 `effectiveFailureReason=''`、`processedFrameCount=1`。
- 最小修复：让一次推理的计数与解析错误作为一个结果原子写入，避免“先记成功再记失败”把帧数重复增加。补“错误张量 → 普通扫描诊断 → JSON”回归测试。
- 归属：已有错误传递缺口，本次新增的通道轴拒绝分支也会触发它。

## 本轮执行范围

按 [自检提示词](/Users/reece24/FruitTreeScanner/docs/validation/SELF_REVIEW_PROMPT_2026-09-08.md) 检查当前工作区 47 个应用/测试修改文件的差异，并追踪相关未修改的消费者：采集和会话恢复、检测队列/后台归档、模型输入与张量解析、坐标/融合准入/去重、几何重量/遮挡/校准、保存重试、伴随文件重读、批量导出与界面汇总。额外检查 PLY 流式读取与头部/点数限制。

审查分支：`codex/fix-outdoor-canopy-depth`；HEAD：`c3ca0b2685b862717456120a26a34a937877c0df`。审查对象是该 HEAD 上的当前未提交工作区，不是远端 main 或旧报告描述的隔离分支。

测试前后 `git diff --binary | shasum -a 256` 一致：

```text
961d17f7940bf725184f48feeb70d26ac8d7ffb5505e0c712a529ab95349f332
```

既有融合准入测试本轮通过，覆盖无深度、低置信度深度、confidenceMap 复制失败、拒绝 ROI 候选和 cloud-only 保守结果等路径；未发现本次差异把 imageOnly/cloudOnly 加入可靠估产。新增数量/几何关联、平移/旋转、同扫描在途证据、排空等待和校准上下文等既有测试也通过。这些是合成输入和逻辑契约验证，不能证明田间精度。

## 验证命令与结果

所有 App 构建和 XCTest 使用仓库指定的 Xcode beta，未更改全局 Xcode 选择。

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -derivedDataPath /private/tmp/fts-self-review-20260908.iBbLsM/DerivedData \
  -resultBundlePath /private/tmp/fts-self-review-20260908.iBbLsM/tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

- `xcresulttool get test-results summary`：`totalTestCount=507`、`passedTests=506`、`failedTests=1`、`skippedTests=0`。XCTest 执行约 17.35 秒；`xcodebuild` 退出码 65。
- 失败方法：`BatchExportServiceTests/testBatchExportRejectsInvalidAndOverflowingTotalsInEveryFormat`，第 37 行，9 处 `Invalid batch should fail`。
- 在相同命令基础上移除 resultBundlePath，添加 `-only-testing:FruitTreeScannerTests/BatchExportServiceTests/testBatchExportRejectsInvalidAndOverflowingTotalsInEveryFormat` 独立复跑：1 项测试、相同 9 处断言失败，退出码 65。
- 日志末尾另有辅助 `xcrun` 找不到 `simctl` 的信息；这发生在 XCTest 明确记录上述断言失败之后，不能用它解释或忽略测试失败。命令级 Xcode beta `simctl` 可正常查询、启动模拟器并执行独立探针。

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild build -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/fts-self-review-20260908.iBbLsM/DerivedData \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

- Release generic iOS：`BUILD SUCCEEDED`，退出码 0；差异空白检查通过。
- 独立探针：编译为 `arm64-apple-ios27.0-simulator`，`vtool` 确认 Mach-O 平台为 `IOSSIMULATOR`，通过指定模拟器的 `simctl spawn` 执行；不是 macOS App 测试。探针编译出现链接工具 sysroot 提示，但产物平台核验与模拟器执行均成功。
- XCTest 编译仍有未使用变量、测试目标最低 iOS 版本与 XCTest 动态库版本不一致的警告；本轮不作无关修改。

探针关键输出：

```text
fixture negativeCount: count=0, yield=5.5, state=complete
fixture nanYield: count=10, yield=0.0, state=complete
fixture negativeYield: count=10, yield=0.0, state=complete
actual companion reader: state=complete, fruitCount=9223372036854775807
UI addition operands: 9223372036854775807 + 1; overflow=true
parserFailure=Ambiguous YOLO channel axis; persisted effectiveFailureReason=''; processed=1
synthetic coverage projection: actual camera z=-2;
correct clip=(0, 0, 0.001, 2); current formula reconstructed z=0.0005
```

探针复用了生产伴随读取器、记录类型和诊断记录器；解析失败原因及投影矩阵是明确给定的场景输入，没有声称执行真实异常模型推理或真实 LiDAR 采集。

## 改动、保留与剩余工作

- 本轮仅新增这份报告及自检提示词；没有修改 App 或测试源文件，没有提交、推送、切换分支或暂存用户改动。
- 保留原有 47 个已修改文件、既有验证文档、模型和数据。核心融合准入规则、阈值、零产量诊断逻辑及校准兼容行为均未改动。
- 本轮只使用一个临时 DerivedData 目录；构建、结果包、日志和探针清理前共约 888 MiB。报告已保留关键证据，该临时目录已移除并验证不存在，模拟器已恢复到开始时的关闭状态；未清空既有模拟器或删除旧构建目录。
- 尚未执行真机 session failure 恢复、实际界面按钮端到端操作、真实果树数量/重量对照及 LiDAR 扫描精度实验。校准准确性、真机覆盖误差和最坏实时性能不能据本轮结果作通过判断。
- 本轮是检查任务，以上 5 项尚未修复。合并前至少解决会话恢复与失败测试，并处理相关数值/坐标/诊断问题，再运行对应回归验证。

最终决定：**do not merge**。
