# FruitTreeScanner 架构重构实施提示词

日期：2026-09-26。设计基线：`main` / `81f49a6ec3d5`。执行时必须重新确认 HEAD、工作区和真实调用链。

配套方案：[整体架构与底层精简设计](REDESIGN_BLUEPRINT_2026-09-26.md)。本文件给出可复制的任务指令，不表示相应重构已经实施。

2026-09-28 继续实施入口：[当前迭代记录与下一轮提示词](REFACTOR_ITERATIONS_2026-09-27.md)。R0–R7 已有迁移和后续修复；续做时先读该记录与源码，避免重复执行历史阶段。

## 使用方式

新会话先复制“总提示词”，再附上需要执行的一个阶段。首次实施从 R0 开始，之后按 R1 → R7 推进。单阶段可拆成多个小提交，下一阶段建立在前一阶段已验证的接口上。

如果希望连续实施，在总提示词末尾加上：“依次执行 R0–R7，每阶段完成必要验证后继续；出现编译失败、行为回归或无法保证数据兼容时，先修复，不带着失败进入下一阶段。”这不自动授权推送、合并或删除远端分支。

## 总提示词

```text
你是 FruitTreeScanner 的资深 iOS/ARKit/Metal/CoreML 工程师。
请实施我附在后面的重构阶段，交付可运行的代码和真实验证结果。

开始前：
1. 阅读当前 AGENTS.md、docs/architecture/REDESIGN_BLUEPRINT_2026-09-26.md
   和 docs/architecture/REFACTOR_PROMPTS_2026-09-26.md。
2. 检查 git status、HEAD、分支、已有改动及实际调用者；以当前源码为准。
3. 先指出本阶段涉及的状态、并发、内存、数据兼容风险，然后直接实施。
   合理的可逆实现细节自行决定；真正缺少产品决策或授权时才询问。

整体目标：
- 五个逻辑区域：App、Features、Application、Domain、Infrastructure。
- 一个扫描业务状态所有者，一个结束扫描流程，一个扫描存档入口。
- 不可变 ScanPlan、完整 ScanEvidenceSnapshot、可验证 ScanRecord。
- 底层减少重复状态、跨层副作用、无用转换和长寿命缓冲。

必须遵守：
- 先稳定职责，后移动目录；先保持一个 App target、iOS 16 和 Swift 5 配置。
- 保留现有 Design 和 SwiftUI 交互，展示模型沿用可支持 iOS 16 的方式。
- 保留 ScanFusionYieldBuilder、ImageDetector 等兼容入口直到调用者迁移完成。
- 保留有意义的候选、融合、结果合成、诊断拆分，不堆成巨型服务。
- 只在硬件、I/O、异步长任务和测试替身边界引入 protocol。
- 只有 .fused 可以进入可靠估产。低置信度、imageOnly、cloudOnly、
  被拒绝的深度证据不能被回退逻辑升级。保留 zeroYieldReasons 和全部诊断。
- 暂停/正常完成保留已接纳的同代在途证据；中断/取消/新扫描拒绝旧证据。
  区分 BindingID、ScanID、EvidenceEpoch、WorkID，不粗暴合并代次。
- 不改变算法阈值、公式、坐标约定、采样和聚类上限来达成“精简”。
- 不为减少行数删除异常恢复、完整性检查、模型资产或关键回归测试。
- 不以新增 unchecked Sendable 掩盖所有权问题；不让重计算或文件 I/O
  阻塞 MainActor；不创建无界逐帧 Task。
- 不回滚、覆盖或混入无关工作区改动。手工修改用 apply_patch。
- 不执行 reset --hard、清空用户数据、改写远端历史或删除远端分支。

验证与交付：
1. 运行本阶段相关 XCTest；高风险阶段完成时执行完整模拟器测试和 Release 构建。
2. 使用本仓库规定的 Xcode beta 和 iOS Simulator，不能用 My Mac 代替。
3. 执行 git diff --check，检查 git diff --stat 和实际差异。
4. 记录实际命令、退出码、测试数；未完成的测试明确写未验证。
5. 报告：变化、保留行为、测试证据、兼容层退出条件、剩余风险及
   mergeable / needs changes / do not merge。
6. 若本次会话已授权提交，按职责形成小提交；推送与合并服从当前明确授权。
   没有推送授权时留下可审查改动与建议提交信息即可。
```

## R0：建立可比较的行为基线

```text
实施 R0：读取当前生产调用链，为后续重构建立可复用的行为基线。

检查范围：
ScanView* → ScanCoordinator* → Renderer*/ImageDetector* →
ScanYieldEstimationController → ScanFusionYieldBuilder/ScanFusionPipelines →
YieldResultComposer → ScanResultExportService → 历史/批量/校准读取。

具体工作：
1. 记录当前 HEAD、Xcode/模拟器身份、已有测试入口和生产调用关系。
2. 列出业务状态、各代次、缓冲和文件的所有者；给出事件到状态的表格。
3. 复核现有测试是否覆盖暂停、中断、换绑、排空、保存重试、事务恢复、
   低置信度拒绝和旧记录读取。仅对实际缺失的关键行为补特征测试。
4. 将基线写入 docs/architecture/REFACTOR_BASELINE.md，记录运行结果。
5. 选取已有合成数据或合法脱敏样例比较候选 ID、来源、数量、质量、
   几何、产量、拒绝原因、诊断和导出字段。数值比较遵循已有容差；
   不能新设宽松容差来隐藏差异。不提交真实用户扫描或大型生成数据。
6. 记录可重放输入的采样数、各阶段耗时和资源上限。没有真机时明确
   尚无真机性能基线，不用模拟器内存推断真实 LiDAR 性能。

优先运行已有测试：
ScanLifecycleControllerTests、ScanCapturedEvidenceConcurrencyTests、
ScanCoordinatorCameraTrackingTests、FusionValidatorTests、
DetectionDeduplicatorTests、ScanFusionYieldBuilderTests、
DetectionDebugStateTests、PointCloudProcessingTests、
ScanExportReadinessTests、BatchExportServiceTests、CalibrationRecordPersistenceTests。

完成标准：有真实通过/失败证据和缺口清单；没有为了建立基线重写生产架构。
若基线失败，定位并单独修复或明确阻塞原因，再开始依赖它的迁移。
```

## R1：固定配置与依赖入口

```text
实施 R1：引入最小 AppDependencies 和不可变 ScanPlan。
前置条件：R0 已完成，当前行为可比较。

首先检查 FruitTreeScannerApp、SettingsStore、FruitScanExperimentConfig、
ScanFruitConfiguration、CalibrationRecord、Renderer 配置和检测模型加载。

具体工作：
1. App 负责构造真实依赖并向下传递；保留旧初始化入口作短期适配。
   只抽取本次扫描必需依赖，不一次替换全应用的所有 shared 实例。
2. 以现有 ScanFruitConfiguration 为迁移起点汇总 ScanPlan，包含本次
   品类/树/季节、采集/检测/算法配置、预算、模型身份、校准上下文。
3. 扫描开始前验证计划，后台准备模型摘要，缓存需由可验证模型身份失效。
4. 扫描内读取固定计划；用户中途修改设置只影响下一次扫描。
5. 运行统计由状态输出，不能反写计划。旧校准上下文仍可解码和判断兼容。
6. 模型缺失、模型变化、身份无法确认分别返回可解释结果；身份不明时
   不自动复用校准，不以空字符串冒充匹配。

验证：ScanSessionConfigurationTests、CalibrationRecordPersistenceTests、
FruitParametersStoreTests、ScanFusionYieldBuilderTests，以及缺失的
“开始后改设置/计划准备取消/模型身份变化”边界测试。

完成标准：本次扫描配置来源唯一且可审计；没有新增一套漂移的默认阈值。
```

## R2：把结束扫描流程移出视图

```text
实施 R2：从 ScanView+Export 和相关扩展抽出 ScanFinalizationWorkflow。
前置条件：R1 的计划和依赖可用；旧协调器继续负责设备生命周期。

具体工作：
1. 追踪当前 exportAndEstimate、flushPendingDetections、GPU 写入屏障、
   makeYieldEstimationSnapshot、persistScanResult、discard 和重试路径。
2. 定义一个流程输出，表达阶段、错误、可重试动作和最终结果。
   复用当前生命周期权威来源，不能引入第二套独立扫描状态机。
3. 按“关闭接纳→排空→冻结→写 PLY→估算→提交 companions”编排；
   若当前实现的顺序存在必要差异，先用证据说明再迁移。
4. 视图只发送 finish/retry/cancel 命令并展示输出。历史刷新在完整提交
   后触发一次，不能由多个成功回调重复宣布保存完成。
5. 失败时保留阶段所需输入：PLY 失败保留快照、估算失败保留输入、
   结果保存失败保留同一结果和源文件。重试不能新建 ScanID 或重采数据。
6. 同一扫描重复 finish 合并或拒绝；每个异步完成都验证 ScanID/WorkID。
   取消不能删除已经成功提交的记录，迟到回调不能恢复已取消的 UI。
7. 先复用现有事务服务，不在本阶段重写文件格式或移除互斥锁。

验证：YieldEstimationRequestGateTests、ScanExportReadinessTests、
ScanLifecycleControllerTests、ScanCapturedEvidenceConcurrencyTests。
对流程的 PLY/估算/保存失败、重复完成、取消与成功同时到达增加可控测试。
在 iOS 模拟器检查结束、重试、返回、历史刷新路径，记录真实操作证据。

完成标准：视图不再编排文件写入与估产；流程只有一个副作用执行入口。
```

## R3：统一会话业务状态与身份规则

```text
实施 R3：以 ScanSession 收拢业务状态，建立 ScanFeatureModel 展示投影。
前置条件：R2 流程可通过命令调用并有失败/取消测试。

具体工作：
1. 逐一列出 ScanView、ScanLifecycleController、ScanCoordinator 和
   估算请求门当前持有的状态，标明唯一写入者和派生字段。
2. ScanSession 串行处理开始、暂停、继续、结束、取消、中断和完成事件。
   MainActor 模型只发布状态快照，UI 导航/弹窗等展示状态仍留在展示层。
3. 明确定义 BindingID、ScanID、EvidenceEpoch、WorkID 的失效条件。
   不把暂停、完成和系统中断处理成相同的 epoch 更新。
4. 保留 ARKit delegate 可同步关闭的最小 CaptureAdmissionGate。
   它只守护准入和身份，不能另存一套估算/保存业务状态。
5. 用有界 worker 接纳帧，保留单待处理帧等限量策略。actor 不执行
   重计算、不阻塞等待 GPU，也不为每帧产生无界任务。
6. 在每个 await 后检查任务身份。已有锁仅在其保护的数据迁移完毕、
   测试证明等价后删除；不能以“已经 actor 化”推导事务原子性。
7. 将排空轮询改成可取消通知/屏障时，准确界定已接纳任务集合，
   无任务、取消、失败均需唤醒等待者，超时不能当作排空成功。

验证：ScanLifecycleControllerTests、ScanCoordinatorSessionRestartTests、
ScanCoordinatorARSessionIdentityTests、MetalViewBindingLifecycleTests、
ScanReadinessRecoveryBindingTests、ScanCoordinatorCameraTrackingTests、
ScanCapturedEvidenceConcurrencyTests、YieldEstimationRequestGateTests。
用可控同步点验证乱序，不依赖任意 sleep 猜测竞争时序。
阶段结束运行完整 iOS 模拟器测试和 Release 构建。

完成标准：生命周期一个权威来源；暂停保留证据，中断和换绑拒绝旧回调。
```

## R4：收紧证据、诊断与算法边界

```text
实施 R4：引入帧级所有权、值类型 Observation 和可靠融合证据契约。
前置条件：R3 已稳定身份和取消规则。

检查 DetectedFruit、ImageDetectorQueue、深度投影、归档去重、
ScanFusionYieldBuilder.Input、ScanFusionPipelines、FusionValidator、
DetectionDeduplicator、YieldResultComposer 和 diagnostics。

具体工作：
1. FramePacket 拥有同帧 RGB/depth/confidence/pose；共享一帧缓冲，
   明确最后消费者和释放点，不为每个检测复制整幅图。
2. 定义 Observation，保留 FrameID、检测/候选身份、框、类别、时间、
   内参、位姿、坐标约定、ROI 几何、深度置信度来源和拒绝原因。
   先逐阶段证明等价，再释放原始缓冲，不能把全部证据压成中心点。
3. CoreVideo 适配放在 Infrastructure，Domain 消费可检查 Sendable 的值。
   原图右/下/前到 ARKit 右/上/后的坐标变换保持不变。
4. 可靠证据只由融合接纳入口构造，估重只消费该类型集合。
   保留 sourceCandidateIDs、稳定轨迹、实测几何和稀疏一对一匹配。
5. 将诊断和质量原因逐步类型化，通过适配器保持现有显示与导出字段。
6. 保持所有阈值、confidenceMap 拒绝、fallback 拒绝和 .fused 限制。
   旧 facade 只作兼容映射，不允许新旧路径同时提交生产结果。

验证：FusionValidatorTests、DetectionDeduplicatorTests、
ScanFusionYieldBuilderTests、DetectionDebugStateTests、
ScanDiagnosticsBuilderTests、YieldEstimatorTests、ResultConfidencePresentationTests。
补充有针对性的旧/新路径比较：同帧不同检测、缺失/损坏深度、
低置信度、候选重排、遮挡、稳定观测、几何保留、零产原因和取消释放。
阶段结束运行完整模拟器测试与 Release 构建。

完成标准：Domain 不持有 CVPixelBuffer；数值、关联和拒绝规则可证明保持。
```

## R5：精简点云缓冲与 PLY 写入

```text
实施 R5：明确 FinalPointCloud 的所有权，减少无用中间表示，分块写 PLY。
前置条件：冻结证据接口已稳定；先测量，再选择实际存在的复制热点。

具体工作：
1. 检查 RendererPointCloudAccess、RendererPointCloudExport、
   ScanFusionPipelines、PointCloudProcessing 与 PLY 读写调用。
2. 保存和估算共用同一个冻结、采样、去噪后的最终点云及其身份。
   预览仍独立限量；不能用预览点云代替最终输入。
3. GPU ParticleUniforms、领域 PointSample、SceneKit 顶点各留在边界。
   用最小可读接口减少全数组 positions/colors map，不造泛型大框架。
4. 对阶段输出的大数组做消费者分析，及时释放；用测量区分 COW 共享
   和实际拷贝。全局 SOR 与筛色后 SOR 保持各自语义。
5. PLY 写入移出 Renderer，分块写临时文件，检查取消、短写、失败，
   完成后原子发布。复用现有 GPU drain，不绕过在途写入屏障。
6. 保持 ASCII/二进制读取、头和字段校验、精度、颜色、单位、区域设置。
   大文件解析继续流式，禁止读取全文再 split。
7. 保留当前采样/聚类上限，记录峰值存活缓冲和阶段耗时。

验证：PointCloudProcessingTests、PointCloudClusterTests、
ScanFusionYieldBuilderTests、ScanExportReadinessTests、BatchExportServiceTests。
覆盖空点云、预算边界、截断文件、取消、写入失败和旧/新写入解析等价。
数据完整性比较源文件实际字节；不以解码后重新编码的摘要替代。

完成标准：文件与估算证据一致，测量支持精简效果，资源上限未放宽。
没有真机测量时报告剩余性能风险，不宣称降耗百分比。
```

## R6：统一扫描仓储与版本化存档

```text
实施 R6：让 ScanRepository 统一扫描文件生命周期，集中 DTO 和 legacy codec。
前置条件：流程和冻结输入稳定，既有存档兼容样例已具备。

具体工作：
1. 检查 ScanResultExportService、PLYCompanionResultReader、
   ScanHistoryStore、BatchExportService/JSONWriter、校准导入和删除路径。
2. 仓储提供暂存、提交、取消、读取已验证记录、查询摘要、删除的明确操作。
   区分 DraftScan/ScanAssessment/CommittedScan，保存完成只能来自提交确认。
3. 先包住现有路径互斥、revision、恢复标记和失效规则；所有扫描写/删入口
   迁入仓储后，才判断哪些旧同步机制冗余。actor 跨 await 不等于原子事务。
4. 使用 ScanMetadataDTO、CompletionManifestDTO、DiagnosticsDTO。
   旧字段解析集中于 legacy codec；先复用原编码器保持输出兼容。
5. 保留 manifest 最后发布、原始字节 SHA256、源 PLY 与 sidecar 校验、
   大小限制、schema 1–3 和旧记录路径。变更编码规则必须显式版本迁移。
6. 历史摘要不能替代完整性校验。批量导出继续在发布前确认源和 revision；
   未有等价快照保证前，不能删除现有前后源校验。
7. 校准保持原始基线和上下文兼容，拒绝身份不明或源变化的记录。
8. 设置、标签等小型持久化复用原子写原语，不强行加入扫描事务。

验证：ScanExportReadinessTests、BatchExportServiceTests、
CalibrationRecordPersistenceTests、DashboardSummaryTests。
覆盖旧格式、损坏/缺失 manifest、源替换、保存与删除竞争、取消与提交竞争、
写入失败、恢复标记、读取期间 revision 变化及批量数量溢出。
故障注入使用临时目录与可控 I/O，不触碰用户真实扫描目录。
阶段结束运行完整模拟器测试和 Release 构建。

完成标准：所有扫描文件副作用只有一个入口；兼容性和失败恢复无回退。
```

## R7：删除失效路径并固定模块边界

```text
实施 R7：完成旧入口清理和目录整理，交付架构迁移的最终证据。
前置条件：R1–R6 已验证，每项临时适配层的调用者已清点。

具体工作：
1. 搜索 Swift 调用、Xcode target、脚本、预览、测试和研究使用。
   仅删除确证已无职责的 facade、重复状态、缓存和转发包装。
2. YieldEstimator 只是待核实的旧路线候选；先查依赖，再隔离或删除。
   FruitCounter 有生产用途，保留算法，必要时改为清晰的无状态实现。
3. 将文件渐进归入 App/Features/Application/Domain/Infrastructure。
   文件移动与行为修复分开提交，保护模型、shader 和资源 target membership。
4. 只在 Domain 依赖已经清晰且有实际收益时拆独立 target/package；
   否则保持一个 target，并以轻量检查约束依赖，不为目录美观改构建系统。
5. 更新真实架构图、入口表、兼容说明、删除理由和剩余真机验收项。
6. 证明没有双套生产入口、没有死掉的重试/错误分支、没有意外删除诊断。

验证：完整 iOS 模拟器测试、Release 模拟器构建、git diff --check。
模拟器检查扫描进入/退出、结束/重试、历史读取、删除、批量和校准入口。
若有可用 LiDAR 设备，按基线复测 30/60/120 秒采集；否则明确真机未验证。

完成标准：提交清单与验收证据可以逐项回看；遗留风险不被“已重构”掩盖。
未经授权不推送、合并、删除分支或改写历史。
```

## 独立复核提示词

```text
请对已实施的 FruitTreeScanner 架构迁移做独立代码审查。
先读取 AGENTS.md 和本次真实 diff，不把设计文档或作者总结当作通过证据。

逐条核查：
1. 生命周期是否确有唯一写入者；UI 派生状态是否可能不同步。
2. 暂停与中断是否保持不同证据失效语义；旧绑定/旧任务能否污染新扫描。
3. actor await、GPU completion、Vision callback、保存/取消间是否仍有竞态。
4. 原始帧释放前，ROI/置信度/位姿/几何证据是否被完整保留。
5. .fused 唯一可靠来源和所有拒绝规则是否被适配器或 fallback 绕过。
6. 产量、sourceCandidateIDs、几何、零产和质量诊断是否与基线等价。
7. PLY/估算是否消费同一冻结点云，限量、流式读写和错误回收是否有效。
8. 旧文件、校准上下文、manifest、摘要、事务失败恢复是否保持兼容。
9. 是否删除了实际生产/研究依赖，或引入比原实现更复杂的空泛抽象。
10. 测试是否真正运行、覆盖了变化，真机结论是否有真实设备证据。

输出按严重性排列的 findings，给出文件/行号、触发条件、影响和修复建议。
编译失败、行为回归、数据丢失、并发错误、关键证据测试缺失均阻止合并。
无阻塞发现时明确说明，并保留未经验证的设备与性能风险。
最后给出 mergeable / needs changes / do not merge。
```

## 本地验证命令

下面是相关测试的命令示例。根据实际阶段选择 `-only-testing`，不能只运行一个示例就宣布全部架构通过。

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -only-testing:FruitTreeScannerTests/ScanCapturedEvidenceConcurrencyTests \
  -only-testing:FruitTreeScannerTests/FusionValidatorTests \
  -only-testing:FruitTreeScannerTests/DetectionDeduplicatorTests \
  -only-testing:FruitTreeScannerTests/ScanFusionYieldBuilderTests \
  -only-testing:FruitTreeScannerTests/ScanExportReadinessTests
```

完整测试去掉 `-only-testing` 参数。Release 验证使用：

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild build \
  -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

真机 LiDAR 采集、深度质量和估产精度需要单独验收；模拟器通过只能证明其覆盖的代码行为与构建。
