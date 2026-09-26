# FruitTreeScanner 自检问题修复与复核

决定：**mergeable**，范围为本轮确认的五项修复。最终完整 iOS 模拟器 XCTest **516 项全部通过，0 失败、0 跳过**；generic iOS Release 未签名构建成功；`git diff --check` 通过。真机采集和界面端到端验收仍见下方限制。

本轮依据[自检提示词](/Users/reece24/FruitTreeScanner/docs/validation/SELF_REVIEW_PROMPT_2026-09-08.md)和[原始五项问题报告](/Users/reece24/FruitTreeScanner/docs/validation/SELF_REVIEW_REPORT_2026-09-08.md)，在用户授权“修改问题”“继续”后实施。原始报告保留修复前的失败证据。

## 五项修复

### 1. 会话失败后重新扫描能再次启动 ARSession

- [ScanCoordinatorWorkflows.swift:180](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanCoordinatorWorkflows.swift:180) 在 `.failed` 状态下，使用原 AR 配置重新 `run`，同时重置 tracking 和 anchors；随后才公布新扫描状态、接收可靠证据。
- 新增窄接口 `ScanSessionControlling`，生产对象仍是 ARSession；通过替代驱动验证实际 `pause → run` 调用，而非只验证状态枚举。
- 会话或配置缺失时返回失败，保留失败状态及旧点数；[扫描入口](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/ScanView+Actions.swift:121) 给出重试提示。
- 普通暂停/继续不重启 ARSession，保留同一扫描标识和点云；失败重扫更换扫描标识并拒绝旧代检测结果。

### 2. 导出回归测试与数据边界契约一致

- 保留 `ScanFileRecord` 对旧记录负数、NaN 的既有规范化行为。
- 将原失败测试拆清三种情形：规范化后的记录仍可导出；原始伴随文件中的负数、非整数数量、NaN/Infinity 被读取器拒绝；整数或浮点批次总和溢出被 CSV、Excel、JSON 三种导出拒绝。
- 没有移除溢出断言，也没有改变导出服务或读取器规则来迁就测试。

### 3. 界面汇总不再因超大数量而溢出崩溃

- [ScanRecordTotals](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/BatchExportFormatting.swift:8) 复用导出层已检查溢出的求和规则，以可选值表达无法表示的总量。
- [批量导出](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/BatchExportContentView.swift:31)和[产量报告](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Views/DashboardAnalyticsSheets.swift:13)使用该汇总；异常总量显示“超出范围”和原因，批量导出按钮禁止启动，进行中的导出仍可取消。
- 回归输入经过真实伴随 JSON 读取器：单条 `Int.max` 保持精度，加 1 时数量总和为无效状态；重量仍正常。另覆盖重量总和溢出、平均值和空记录。

### 4. 深度覆盖体素使用正确的相机反投影

- [RendererDepthCoverage.swift:342](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/RendererDepthCoverage.swift:342) 将深度像素按分辨率映射到相机图像，使用内参逆矩阵恢复光学坐标，再转换到 ARKit 相机及世界坐标。
- [共享坐标换算](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ImageCameraCoordinateSpace.swift:5)与融合入口统一右/下/前到右/上/后的轴向变换。原始深度几何不依赖显示视口裁剪。
- 保留步长 4 的采样、深度范围及置信度门槛；明确保留覆盖率包含配置最小值、融合严格大于 0.1 m 的既有不同准入规则。
- 增加有限值、像素格式、无效几何和体素整数转换检查，异常输入直接跳过。
- 回归比较中心/偏轴样本、两组图像和深度分辨率、三组相机旋转/平移位姿，验证覆盖体素与融合、Metal 相机约定一致；另覆盖低置信度、非有限值、无效矩阵和体素坐标溢出。

### 5. YOLO 解析失败进入普通扫描 JSON 诊断

- [recordYOLOParsingResult](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ImageDetector.swift:191) 将解析统计及错误原因在原有锁内一次写入诊断记录器，每帧只累计一次。
- 明确记录无效张量秩/批次、缺失模型输入尺寸等错误；保留通道歧义和标签契约失败原因。
- 回归执行“错误 MultiArray → 实际解析器 → 检测诊断 → 扫描诊断 → 真实 JSON 导出”，验证 `diagnostics.imageFailureReason`；随后合法结果清除上次错误，帧计数继续准确增长。

## 验证记录

环境：Xcode 27.0，Build 27A5194q；命令级 `DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer`。未改变全局 Xcode 选择。模拟器 `FruitTreeScanner-iPhone-17-iOS27`，iOS 27.0、arm64，ID `C722B4F0-E16F-4C14-84A1-8C796DB0FE11`。

| 验证 | 实际结果 |
| --- | --- |
| 针对性回归：ScanReadiness、BatchExportService、PointCloudProcessing、DetectionDebugState、FusionValidator | 222 项通过，0 失败、0 跳过 |
| 首次完整回归 | 516 项通过，0 失败 |
| 最终源码完整回归（含近距离阈值边界补充） | 516 项通过，0 失败、0 跳过；XCTest 约 20.21 秒，退出码 0 |
| generic iOS Release 未签名构建 | `BUILD SUCCEEDED`，退出码 0 |
| 差异空白检查 | `git diff --check` 通过 |

相比修复前的 507 项，本轮新增 9 个测试方法，并修正原失败导出测试。最终结果包摘要为 `totalTestCount=516`、`passedTests=516`、`failedTests=0`、`skippedTests=0`、`result=Passed`。

完整验证命令（路径为本轮已清理的临时位置）：

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -derivedDataPath /private/tmp/fts-self-repair-20260908.3YK2Ox/DerivedData \
  -resultBundlePath /private/tmp/fts-self-repair-20260908.3YK2Ox/full-final.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild build -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/fts-self-repair-20260908.3YK2Ox/DerivedData \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

修复过程中的失败也已处理：首次编译缺少 ARKit 导入，已补齐；随后两项覆盖率新测试因沿用 `OneComponent32Float` 测试图而触发新增格式保护，已改用深度 `DepthFloat32` 测试图，并保留错误格式应被拒绝的断言。最终全量运行上述方法全部通过。

测试目标仍有最低 iOS 版本与 XCTest 库版本不一致的链接警告。模拟器日志仍出现既有 CoreML/MPSGraph 后端提示，后续模型加载成功；最终测试结果包无失败及运行时警告条目。这些结果不构成真实设备推理性能测量。

## 改动边界、保留内容与存储

- 分支仍为 `codex/fix-outdoor-canopy-depth`，HEAD 仍为 `c3ca0b2685b862717456120a26a34a937877c0df`；未提交、未推送、未切换分支、未暂存或回退其他修改。
- 以修复开始时的 275 个已跟踪 Swift/Metal/工程文件副本核对：本轮修改其中 18 个，其余 257 个逐字节不变，没有源文件丢失；新增 1 个坐标换算源文件及本报告。既有未提交工作保留在当前工作区。
- 保留只有 `.fused` 参与可靠估产的约束；imageOnly/cloudOnly、低置信深度以及已拒绝候选的融合准入规则、检测阈值、零产量原因、校准和持久化兼容行为未被放宽。对应既有回归均纳入完整测试。
- 修复前差异 SHA-256：`961d17f7940bf725184f48feeb70d26ac8d7ffb5505e0c712a529ab95349f332`；仅本轮相对基线的补丁（含新增源文件）SHA-256：`b44b751727984bbef0576f00b8fd89be284b1871aa17bee1b592e60f56aad014`。
- 仅使用一个临时 DerivedData 位置。构建、测试结果包、基线副本及日志清理前约 884 MiB；完成后移除本轮临时目录并核验不存在。未下载新模型或数据集，未清理其他构建目录；模拟器最终为开始时的关闭状态。保留代码、测试和轻量报告。

## 剩余验收范围

- 会话重启测试证明驱动收到 `run`、调用顺序与代次保护；尚未在真机注入 ARSession failure 并观察帧时间戳和点数恢复增长。
- 覆盖率测试使用合成深度图及相机位姿，没有真实树冠扫描或人工数量/重量对照，不能据此报告田间精度。
- 本轮 Computer Use 未能连接 Simulator，受支持 App 列表也没有 Simulator/Device Hub；未执行实际按钮导航、异常汇总页面截图和动态字体布局验收。界面已构建，汇总数据路径已通过模拟器 XCTest。
- 设备列表存在一台已配对的实体 iPhone，但本轮未安装到该设备或控制相机进行实际采集；真机恢复、覆盖与估产准确性仍需现场验证。

最终决定：**mergeable**（本轮代码修复及模拟器回归范围）。
