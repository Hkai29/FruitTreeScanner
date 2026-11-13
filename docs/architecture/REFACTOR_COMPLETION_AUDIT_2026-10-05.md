# FruitTreeScanner 原范围完成条件核验

日期：2026-10-05，第 48 轮。核验对象是 [原 R0–R7 蓝图](REDESIGN_BLUEPRINT_2026-09-26.md) 第 3–9 节及其核心不变量，目标仍为整体架构重构、下一轮构思与持续迭代。

**整体决定：needs changes。** 业务状态、结束流程和仓储主线已经收拢；算法领域边界、真实观测留存及资源/物理验收仍有缺口。第 46 轮的代码约 90%、整体约 80% 是历史定性估算，没有阶段权重，不能作为本表任一项已完成的证据。本次不按文件数、行数、测试数或完成行数计算新的百分比。

## 1. 当前状态与证据范围

- HEAD：`3398423774bf3f88f3fb4a732718a4e504a752fb`，分支 `codex/variety-draft-concurrency`。开始时 11 个已有改动路径全部记录摘要，308 个 App/单元/UI 测试 Swift 源文件记录摘要；本轮只增加本核验文件和第 48 轮执行记录，不修改 App、测试、工程或既有工作流文件。
- 第 47 轮全量 `ui` report 和结果树重新读取：**1073/1073 Passed、59 类、8 步退出 0，零失败/跳过/预期失败**。本轮开始时 App/Test 与该轮最终受测摘要相同；执行记录使用第 47 轮收尾后的摘要核对。此处是核验已有结果，**本轮没有重新运行 XCTest 或原生页面走查**。
- 本轮重新执行整个 Domain 独立编译：**24 个源文件，iOS 16 simulator、Swift 5，退出 0**；当前 App **unsigned Release 模拟器构建退出 0**。这两项均为编译证据，不能证明最低运行版本或物理设备运行。
- 工程结构化读取确认 App、单元 XCTest、原生 UI XCTest 三个 target；App/单元最低版本 16.0，原生 UI target 为 17.0。App 使用工程继承的 Swift 5 设置。生产仍是单 App target，独立 Domain framework/package 需要实际收益评估，原蓝图并未强制拆包。
- 证据位于仓库外 `/private/tmp/fruit-iteration48/`：`baseline.json`、`current-test-inventory.json`、`project-targets.json`、`domain-command.json`/`domain.log`、`release-command.json`/`release.log`。原 XCTest 包位于 `/private/tmp/fruit-iteration47/fruit-code-improvement-n9nvc4mm/tests.xcresult`。

状态用语：**已证明**仅针对表内明确范围；**部分**表示实现/局部证据存在但该项整体仍未达标；**待证明**表示没有足够证据；**条件评估**表示蓝图要求评估，不能自动当作必须迁移的任务。

## 2. 当前真实生产链

```text
FruitTreeScannerApp.AppDependencies
  → ScanView / MetalView / ScanCoordinator
  → ScanPlanFactory → Domain.ScanPlan
  → Domain.ScanSession + CaptureAdmissionGate
  → Core.Renderer / ImageDetector.FramePacket
  → Infrastructure.Observation.capture → Domain.Observation
  → Application.ScanFinalizationWorkflow
      → Coordinator 排空检测
      → Renderer 排空 GPU、冻结 FinalPointCloud、分块写 PLY
      → ScanRepository 绑定 source/plan/snapshot 身份
      → ScanYieldEstimationController detached estimate
          → Core.ScanFusionYieldBuilder / ScanFusionPipelines
          → Domain 投影、深度候选、去重、匹配与分配
          → Core.ReliableYieldEvidence / YieldResultComposer / diagnostics updater
      → ScanRepository → 事务导出服务 → metadata/CSV → manifest 最后发布
  → 注入的 History / 校准来源；批量导出再次验证源与 revision
```

目录中的 `Core` 仍同时包含平台适配和数值编排。**整个现有 Domain 能独立编译，不等于上图中的全部领域算法已纳入独立编译门禁。** 本表不通过把尚未迁入的算法重新定义为“无需隔离”来关闭缺口。

## 3. R0–R7 交付核对

| 阶段 | 明确交付要求 | 当前证据 | 判定与未完成部分 |
|---|---|---|---|
| R0 | HEAD、调用链、状态/数据契约、回归样例、测量入口 | [历史基线](REFACTOR_BASELINE.md)；本轮 HEAD/源码摘要；下文逐场景结果树关联 | **部分**。源码和回归基线存在；没有同设备原始性能测量基线，不能由历史测试耗时补上。 |
| R1 | 根依赖装配、完整不可变计划、后台模型/校准身份、扫描不读后续设置 | [AppDependencies](../../FruitTreeScanner/App/FruitTreeScannerApp.swift#L52)、[ScanPlan](../../FruitTreeScanner/Domain/ScanPlan.swift#L59)、[工厂](../../FruitTreeScanner/Application/ScanPlanFactory.swift#L191)；T01–T03 | **部分**。活动计划冻结已证明；Renderer 初始容量及未开始计划时的设置仍读取 `.shared`，见第 7 节。 |
| R2 | 唯一结束流程；PLY/估算/结果提交的失败阶段可准确重试 | [Workflow](../../FruitTreeScanner/Application/ScanFinalizationWorkflow.swift#L82)、[视图命令](../../FruitTreeScanner/Views/ScanView+Export.swift#L29)；T04–T09 | **已证明：当前源码所有权和模拟器失败/重试范围**。物理完成/重试流程另列，尚未验收。 |
| R3 | 单一业务状态、不同身份失效语义、同步准入；暂停保留、中断/取消拒绝旧结果 | [ScanSession](../../FruitTreeScanner/Domain/ScanSession.swift#L54)、[gate](../../FruitTreeScanner/Domain/ScanSession.swift#L223)、[页面投影](../../FruitTreeScanner/Views/ScanFeatureModel.swift#L7)；T10–T16 | **已证明：同步状态与模拟器身份/迟到结果范围**。采用锁保护单一 owner，蓝图建议 actor 不构成强制要求；gate 未拥有第二套业务状态。 |
| R4 | 同帧封装、完整 Observation、受限可靠证据构造、结构化诊断、阶段等价 | [FramePacket](../../FruitTreeScanner/Core/ImageDetectorQueue.swift#L11)、[Observation](../../FruitTreeScanner/Domain/Observation.swift#L49)、[采样边界](../../FruitTreeScanner/Infrastructure/Detection/ObservationCapture.swift#L99)、[可靠准入](../../FruitTreeScanner/Core/ScanFusionPipelines.swift#L155)；T17–T23、T35–T38 | **部分**。buffer-free 输入与关键等价/拒绝回归存在；可靠产量准入和部分数值编排仍在 Core，真实观测持久回放尚未证明。 |
| R5 | 共享最终输入、有界点表示/输出、流式 PLY、取消回收、等价字节、峰值内存 | [最终快照](../../FruitTreeScanner/Core/RendererPointCloudAccess.swift#L83)、[分块 writer](../../FruitTreeScanner/Core/RendererPointCloudExport.swift#L260)、[流式 ASCII](../../FruitTreeScanner/Core/PLYPointCloudParser.swift#L51)；T24–T27 | **部分**。预算/字节/取消证据通过；COW 实际拷贝、进程峰值、GPU 排空故障场景及资源回归预算不足。 |
| R6 | 仓储/DTO/legacy；历史、批量、校准、删除接入；完整性、并发和恢复 | [Repository](../../FruitTreeScanner/Infrastructure/Persistence/ScanRepository.swift#L89)、[DTO/codec](../../FruitTreeScanner/Infrastructure/Persistence/ScanArchiveDTO.swift#L44)、[历史删除](../../FruitTreeScanner/Core/ScanHistoryStore.swift#L224)；T28–T34、T39–T44 | **已证明：当前仓储主线与模拟器兼容/事务范围**。原生完整删除、真实磁盘故障仍未证明；持久观测不是现有 result DTO 提供的能力。 |
| R7 | 无双套生产副作用入口、清理旧路线、整理稳定边界、模块收益评估、完整验证 | 旧 YieldEstimator 在测试支持中；生产 FruitCounter 仍被 composer 使用；现有 Domain 全量门禁；1073 项当前测试、当前 Release；下文边界表与兼容退出条件 | **部分**。真实领域链仍有 Core 部分，兼容入口退出条件尚未满足，物理验收未完。目录示意与独立 package 均不作为无条件迁移指标。 |

T 编号对应第 5 节已执行方法。本表的“已证明”不外推到物理深度质量、掉电或磁盘满场景。

## 4. 架构与底层约束逐项核验

| ID | 蓝图要求 / 达标证据 | 当前核验 | 判定 |
|---|---|---|---|
| A01 | 根装配依赖，开始前捕获完整计划 | AppDependencies 注入设置/参数/仓储/历史/标签；工厂捕获模型、校准、实验、预算、相机、树和季节。 | 已证明所列字段；初始 Renderer 依赖缺口见 A03。 |
| A02 | 设置只影响下一扫描；HUD 输出运行数据 | activePlan 分支使用冻结值；ScanPlanTests 的 settings reload 与自定义计划断言通过，HUD 类型已从设置分离。 | 已证明活动计划范围。 |
| A03 | 渲染/捕获不独立读取全局设置 | Renderer.init 的容量、无参数 applyScanQualitySettings 仍读共享设置；MetalView 构造未传根配置；Coordinator 无 plan 时走无参数方法。 | 部分，下一轮先复现独立根配置。 |
| A04 | UI 只发命令，业务布尔从 owner 派生 | ScanView 使用 sessionModel 的 lifecycleSnapshot 和 workflow phase，finish/retry/cancel 不直接写扫描文件。 | 已证明扫描主线；不声称全部页面都重新审完。 |
| A05 | Application 不持有 MTKView/ARFrame/CVPixelBuffer | ScanFinalizationWorkflow 存值快照/受控 draft 与异步 closures；ScanEvidenceSnapshot 是 checked Sendable。 | 已证明上述存储边界。 |
| A06 | Domain 无 SwiftUI/ARKit/Metal/Vision/CoreVideo、磁盘与全局设置 | 全部现有 24 文件独立编译；源码包含 Foundation/CoreGraphics/simd 和值/锁逻辑。 | 已证明现有目录；不覆盖 Core 算法，见 A07。 |
| A07 | 融合接纳、可靠产量、几何/遮挡和诊断职责属于纯算法边界 | Domain 已有投影、深度候选、匹配、分配、去重；ReliableYieldEvidence、FusionEvidencePipeline、YieldResultComposer、部分点云/遮挡实现仍在 Core，builder 还关联 legacy DetectedFruit。 | 部分；需沿实际依赖逐段迁移，保留 facade 和构造权限。 |
| A08 | FrameID/检测ID/品类/框/时间/内参/位姿/坐标/ROI/置信度来源/拒绝原因完整 | Observation 字段明确；FramePacket 同帧采样绑定；ROI 9×9 与投影采样在平台边界，T17–T20。 | 已证明值契约与合成回归。 |
| A09 | 帧共享缓冲，最后消费者后释放；不为每个 detection 复制整图 | FramePacket 拷贝帧缓冲一次，ROI 映射返回紧凑值；队列取消/重置/排空 T21–T23。 | 已证明源码路径和测试；实际 RGB/深度/confidence 字节峰值未测。 |
| A10 | `.fused` 唯一可靠输入，构造只由接纳边界产生 | ReliableYieldEvidence 的 fileprivate failable init 检查 `.fused`，pipeline compactMap 后供 FruitCounter/估重；image/cloud/rejected 不能升级。 | 已证明准入源码与拒绝测试；类型仍在 Core。 |
| A11 | 确认 sourceCandidateIDs 后消费对应几何，不重新猜来源 | composer/质量关联按显式来源、候选 ID 和固定回放预期核对；混合形状与必须重分配的合成回放通过。 | 已证明合成边界；真实果实准确率待证明。 |
| A12 | BindingID/ScanID/EvidenceEpoch/WorkID 语义分别保留 | ScanSession/gate/workflow 分别拥有绑定、扫描、准入 epoch、attempt，暂停不推进失效 epoch。 | 已证明 T10–T16；未把身份压成一个 generation。 |
| A13 | await 后复核身份；不把每帧变成无界 Task | workflow accepts 与 coordinator 处理锁、单 detection task、单待处理帧；晚到/取消方法通过。 | 已证明相应路径；真机调度开销待测。 |
| A14 | 正常完成 drain→freeze→PLY→estimate→commit；重试不重新采集 | coordinator 排空已接纳检测；Renderer utility worker 等待 GPU；workflow 复用 staged cloud、snapshot、result。 | 检测/重试已证明；GPU 在途故障证据不足。 |
| A15 | 最终 PLY 与估算消费同一个 FinalPointCloud，预览不能冒充 | stagedPointCloud.pointCloud 传入 snapshot，身份含 revision/采样签名，receipt 校验 source、plan、snapshot。 | 已证明源码/T08–T09/T24；真实 GPU 输出仍待验收。 |
| A16 | 继承捕获/预览/分析/检测/聚类上限 | Plan 默认 240000/120000/360，上界 clamped；Renderer capacity、PLY 500000 显示上限、有界 ROI；边界回归通过。 | 数量上限已证明；帧数不等于字节预算。 |
| A17 | 减少中间数组存活，实际 COW 与峰值需测量 | PointCloudCandidatePipelineOutput 仍保留筛色、clusteringPoints/denoising.samples 与候选；数组可能 COW 共享。 | 部分；不能凭字段数量断言重复拷贝或已降耗。 |
| A18 | PLY 有界头/流式 ASCII/二进制、分块发布、取消清理、字节等价 | 当前 parser、1024 点分块 writer、fsync/exclusive move 与 T25–T27；ASCII/LE/BE 等解析回归通过。 | 已证明模拟器文件格式范围；掉电/磁盘满不是这些测试已证明的事项。 |
| A19 | 只让一个结束与扫描存档入口拥有生产副作用 | ScanView 发 workflow 命令；repository stage/bind/commit/delete/settle 复用受控服务和 shared archive transaction。 | 已证明扫描主线；compat facade 的公开调用仍保留。 |
| A20 | Draft/Assessment/Committed 区分；完整提交后才显示保存完成 | workflow.completed 只在 persist 成功后发出；repository.confirm 再核 revision、metadata/source SHA。 | 已证明 T06/T28；结果生成不会自动等于保存成功。 |
| A21 | DTO/legacy codec集中字段解释，历史/校准/批量消费验证记录 | ScanMetadataDTO/CompletionManifestDTO、ScanLegacyArchiveCodec、ScanResearchArchiveCodec；校准/批量重新验证。 | 已证明列出的存档字段；不是全 Observation 编码。 |
| A22 | manifest 最后发布；SHA 使用原始字节；旧格式/错误恢复保持 | exporter 先 metadata/CSV 再 manifest；reader 版本1–3；源变化/损坏/失败回滚/并发测试。 | 已证明模拟器事务/兼容样例；恢复标记失败的全部故障组合仍需专门核验。 |
| A23 | 列表摘要不是永久凭证，批量/校准提交前后核 revision | repository verified read、confirm、batch校验，源替换和未知身份拒绝，T29/T31/T32。 | 已证明相应测试；摘要缓存不替代文件完整性。 |
| A24 | 小型设置/参数/标签/校准保留独立语义；历史字节不随目录迁移改变 | 各自独立 store/persistence；默认校准 canonical bytes、UUID/字段合并/冻结计划回归；46/47来源身份和物理位保持。 | 已证明已列回归；不合并到扫描事务。 |
| A25 | 移除无生产调用的旧 YieldEstimator，保留 FruitCounter | YieldEstimator 实例化只在测试支持/测试；App Sources 不含 LegacyYieldEstimator；composer 仍调用 FruitCounter。 | 已证明当前 Swift/target 搜索范围；不删除有效算法或研究资产。 |
| A26 | 只在真实设备/文件/长任务边界加接口；不为helper制造protocol | 现有 operations、模型身份provider和repository构成相关边界；数值核心使用具体类型。 | 本轮未发现新增空壳层；剩余迁移仍遵守此限制。 |
| A27 | 现有诊断、zeroYieldReasons、模型、shader、训练/论文资产保留 | 无生产/资源改动；全量包含 builder/debug/replay 的零产及诊断断言。 | 本轮字节保留已证明；真机诊断解释仍需实际扫描。 |
| A28 | 只在有实际收益时评估独立Domain target/package | 当前独立编译门禁与单 App target可用；公开API、资源归属和依赖收益尚未作新拆包决策。 | 条件评估；不强制拆包，不将不拆包等同于原目标完成。 |
| A29 | 长时归档保存紧凑观测，形成真实输入黄金回放 | coordinator 内存归档 Observation；现有 result/research JSON 保存结果/统计，不保存完整 frame/pose/ROI 观测包；ReplayTests 明确synthetic。 | 待证明：有界可还原基线、脱敏和真实采集黄金预期。 |
| A30 | 同设备同输入峰值内存/阶段耗时，对照确认的回归预算 | FinalPointCloud.buildDuration 是单阶段；estimatedPeakPayloadBytes 是 payload 算术估算，cached路径为0；未找到对应物理峰值/全结束阶段报告。 | 待证明；估算不是进程测量，0也不是零峰值。 |
| A31 | 30/60/120秒、同LiDAR设备/路线/参数；FPS/main thread/内存/温度/误差 | [真机表](../validation/REAL_DEVICE_ACCEPTANCE.md) 与 [ground truth](../validation/GROUND_TRUTH_PROTOCOL.md) 有验收协议；尚无本次实测报告。 | 待证明；设备可连接或设备SDK编译成功不计通过。 |
| A32 | 完整模拟器与Release；最低支持版本运行、原生完成/重试/删除 | 当前1073结果树与本轮Release/Domain通过；47原生展示走查已完成。 | 编译/模拟器已证明；iOS16运行、物理完成/重试及永久删除仍未全部验收。 |
| A33 | 捕获适配层拥有硬件缓冲；Renderer 渐进收敛绘制/交互，移出文件与全局设置 | [stagePointCloud](../../FruitTreeScanner/Core/RendererPointCloudExport.swift#L417) 仍由 Renderer 组织日期/文件名、目的路径、repository staging 和 PLY writer；GPU 排空与最终快照仍在该 worker。 | 部分。分块 writer 与统一仓储已有实现，文件编排职责尚未移出 Renderer；搬迁前需固定快照、取消及发布后 receipt 所有权。 |
| A34 | 临时兼容入口明确保留原因和退出条件 | 下表区分公开 facade、测试适配和仍被生产内部使用的 DetectedFruit；未将包装方法当作已经移除。 | 部分。退出条件已记录，调用者完整复核与迁移尚未全部完成；不能删有效生产算法或回归来达标。 |

### 临时兼容入口的保留原因与退出条件

以下是当前可核验的入口及退出标准；Swift 调用搜索不是所有脚本、研究和外部调用者均已迁移的证明。

| 兼容入口 | 当前保留原因 | 可退出条件 |
|---|---|---|
| Renderer.savePointCloud / callback stagePointCloud | 包装 async staging，保持默认参数及主线程 completion 契约；当前 Swift 搜索未见其他 App savePointCloud 调用，不能据此直接删除公开入口。 | 复核所有 target、脚本/研究依赖及支持的调用契约；调用者统一迁至异步捕获/存档边界；固定取消、GPU失败、发布后receipt处理及回调语义后再决定移除。 |
| ImageDetector.processQueue / Coordinator.appendDetectedFruits、fusionEstimateDetectionsSnapshot | 原始兼容输入和现有回归继续使用；生产队列已经消费 Observation。DetectedFruit 仍被推理/解析内部使用，不能整类视为无用。 | 迁移剩余调用者并保留同帧深度、confidence拒绝、迟到结果和诊断回归；只有证实不再需要缓冲适配时移至测试支持或移除 facade。 |
| ScanFusionYieldBuilder.Input(savedDetections:) / legacy detection 适配 | 旧 buffer/reference fixtures 与阶段等价测试仍调用；原生估算使用 Observation。 | 先保留固定数值/几何和拒绝预期，迁移公共输入契约及所有调用者，再复核可将仅测试适配移出生产；不扩大 ReliableYieldEvidence 构造权限。 |
| ScanHistoryStore.deleteFilesWithResult convenience | 默认仓储的兼容包装与删除故障回归仍使用；根生产 deleteRecords 已使用注入仓储。 | 所有正式消费者使用根仓储，保留部分删除失败、提交竞争、残留文件与重试测试，核验其他调用者后再退出默认共享包装。 |

LegacyYieldEstimator 已在测试支持中；FruitCounter 仍有生产调用，不属于待删除兼容层。暂存这些入口没有授权增加第二套副作用实现，也不能将退出标准记录完毕算成迁移完成。

### 全应用协作范围补充

原蓝图第 3.1 节的七条功能协作不能仅用扫描主线的验证代替：

| 功能 | 当前实际入口与证据范围 | 判定 / 缺口 |
|---|---|---|
| 扫描 | ScanView 使用根 planFactory/finalizationOperations；默认 `@State coordinator = ScanCoordinator()` 尚未传根 settings，MetalView/Renderer 又存在共享来源。 | 部分。活动计划已冻结；根配置到预览/初始化仍需失败回归。 |
| 历史/结果 | 根注入 historyStore；仓储读取/删除与结果完整性规则；结果页面接收结果和根 tagStore。 | 仓储与既有消费者测试可核验；本轮没有重新走查所有详情页，完整原生删除未完成。 |
| Dashboard/趋势 | 根 historyStore 传入汇总/趋势；DashboardDailySummary 按 complete 记录聚合，但纯聚合代码仍在 `Views/DashboardSummary.swift`。 | 部分。功能消费者已有测试，蓝图要求聚合移至 Application/Domain 尚未按该目录边界实现。不能为关闭本项把数值聚合改称纯展示。 |
| 批量导出 | BatchExportView 捕获选中记录/选项；服务在生成/发布前后验证源和revision，格式写出仍分服务。 | 已证明对应文件事务与选择快照测试；UI内仍持有异步任务编排，本轮不宣称已满足蓝图全部Application编排要求。 |
| 校准 | 根 calibrationScanSource 读取仓储原始基线；Domain 校准上下文/系数；独立 CalibrationRecordPersistence。 | 原始基线、上下文/不可用身份拒绝与根消费者已有证据；物理人工数/重量仍未验收。 |
| 果园/标签 | ScanLaunchRequest 捕获 plotId/tagIds，Dashboard.activateScan 将分类写入根TagStore；ScanPlan目前只含treeID，不含plot/tag快照。 | 部分。保持了独立编辑存储，但没有按蓝图字面将分类身份/值纳入计划；需要明确哪些值属于扫描身份与哪些允许后续编辑，并经回归固定契约，不能直接视为等价完成。 |
| 设置 | 根 settings/parametersStore 注入设置、品种库和校准页；计划按根工厂冻结。 | 活动计划/字段合并/未编辑零写入已证明；预览和初始容量的共享fallback仍未关闭。 |

这是对原范围的补充核验，尚未实施上述剩余迁移，也不要求为每个页面建立同名 service。

## 5. 必测场景与已执行方法

以下方法均在第 47 轮真实结果树中唯一出现且 `Passed`。`current-test-inventory.json` 保留完整方法节点；`selected-test-evidence.json` 给出对应源码位置。本轮核验用例范围，不把方法名或汇总数当作物理验证。

| 编号 | 场景 / 方法（ClassName.method） |
|---|---|
| T01 | ScanPlanTests.testPlanKeepsScanConfigurationAndBudgetsAfterSettingsChange |
| T02 | ScanPlanTests.testCustomPlanConfigurationReachesFrozenEstimateAfterSettingsReload |
| T03 | ScanPlanTests.testMissingModelAndUnverifiedIdentityDisableCalibrationWithSpecificReasons |
| T04 | ScanFinalizationWorkflowTests.testDuplicateFinishIsRejectedAndFailedExportCanRetryWithSameScanIdentity |
| T05 | ScanFinalizationWorkflowTests.testEstimationFailureRetriesTheSameFrozenInputWithoutReexportOrRedrain |
| T06 | ScanFinalizationWorkflowTests.testPersistenceRetryReusesResultAndRefreshesHistoryOnlyAfterCommit |
| T07 | ScanFinalizationWorkflowTests.testCancelRacingWithCommittedPersistencePreservesTheRecord |
| T08 | ScanFinalizationWorkflowTests.testProductionSnapshotEstimateAndRepositoryPreserveOneEvidenceIdentity |
| T09 | ScanFinalizationWorkflowTests.testEstimateFromAnotherObservationSnapshotIsRejectedAndCanRetryOriginalInput |
| T10 | ScanSessionSnapshotTests.testCaptureAdmissionGateSeparatesPauseFromInvalidationEpoch |
| T11 | ScanSessionSnapshotTests.testFeatureModelRejectsAnOlderQueuedLifecycleSnapshot |
| T12 | ScanCapturedEvidenceConcurrencyTests.testCapturedEvidenceCanCommitAfterRapidPauseResumeOfSameScan |
| T13 | ScanCapturedEvidenceConcurrencyTests.testFinishingFlushCommitsInFlightCapturedEvidence |
| T14 | ScanCapturedEvidenceConcurrencyTests.testHardInvalidationRejectsCapturedEvidenceBeforeLifecycleCallback |
| T15 | ScanCapturedEvidenceConcurrencyTests.testReplacementScanRejectsCapturedEvidenceFromPreviousIdentity |
| T16 | ScanCoordinatorARSessionIdentityTests.testStaleSessionInterruptionCannotInvalidateReplacementScan |
| T17 | DetectionDebugStateTests.testEnrichedDetectionStoresBoundedFrameObservationInsteadOfPixelBuffers |
| T18 | DetectionDebugStateTests.testNativeObservationsKeepFrameEvidenceThroughArchiveTrimAndFreeze |
| T19 | DetectionDebugStateTests.testConfidenceCopyFailurePreservesDetectionButRejectsAlignedDepthContext |
| T20 | DetectionDebugStateTests.testEnrichedObservationRecordsWhenConfidenceGateRejectsAllDepthSamples |
| T21 | DetectionDebugStateTests.testCancelledDrainLeavesLateFrameForAnotherConsumer |
| T22 | DetectionDebugStateTests.testCancellingOneDrainDoesNotCancelAnotherWaitingConsumer |
| T23 | DetectionDebugStateTests.testResetWakesOldDrainWithoutConsumingNewGeneration |
| T24 | ScanPlanTests.testRendererAppliesBoundedBudgetAndInvalidatesPreviousAnalysisCache |
| T25 | PointCloudProcessingTests.testChunkedPLYWriterMatchesCompatibilityBuilderBytes |
| T26 | PointCloudProcessingTests.testCancelledChunkedPLYWriteKeepsPriorFileAndRemovesTemporaryFile |
| T27 | PointCloudProcessingTests.testChunkedPLYPublishNeverReplacesAnExistingScan |
| T28 | BatchExportServiceTests.testRepositoryCommitConfirmsManifestAndCalibrationRejectsUnknownSourceIdentity |
| T29 | BatchExportServiceTests.testRepositoryConfirmationRejectsRevisionReplacedAfterExport |
| T30 | BatchExportServiceTests.testManifestPublishesAfterMetadataAndCSVOnRevisionChange |
| T31 | BatchExportServiceTests.testFirstCommitRejectsSourceReplacedAfterStaging |
| T32 | BatchExportServiceTests.testRootCalibrationSourceReadsOriginalBaselineAndRejectsChangedEvidence |
| T33 | BatchExportServiceTests.testHistoryDeletionWaitsForResultCommitAndRemovesWholeScan |
| T34 | BatchExportServiceTests.testFailedConcurrentPublishCannotRollbackLaterSuccessfulRevision |
| T35 | ScanObservationReplayTests.testReliableDepthReplayPreservesGeometryYieldAndArchiveAcrossInputOrder |
| T36 | ScanObservationReplayTests.testMixedCloudReplayKeepsMeasuredGeometryThroughArchiveAndExport |
| T37 | ScanObservationReplayTests.testRequiredCandidateReassignmentSurvivesArchiveAndExport |
| T38 | ScanObservationReplayTests.testConfidenceCopyFailureReplayPreservesRejectionThroughResearchExport |
| T39 | BatchExportServiceTests.testBatchResearchJSONAcceptsMetadataFromMatchingTransaction |
| T40 | BatchExportServiceTests.testBatchResearchJSONRejectsRevisionedMetadataWithoutManifest |
| T41 | BatchExportServiceTests.testScanResultExportMetadataStagingFailureDoesNotPublishCompletion |
| T42 | BatchExportServiceTests.testScanResultExportManifestFailureKeepsPreviousCompleteRevisionReadable |
| T43 | BatchExportServiceTests.testScanResultExportRecoversStaleStagingDirectoryBeforeRetry |
| T44 | BatchExportServiceTests.testBatchExportTotalsRejectIntegerOverflowWithoutTrapping |

原蓝图必测项的范围核对：

| 必测项 | 当前对应证据 | 是否足够 |
|---|---|---|
| 暂停/继续的在途检测 | T12/T13/T10 | 模拟器token/排空范围足够；非物理推理耗时。 |
| tracking降级/恢复 | ScanCoordinatorCameraTrackingTests.testLimitedTrackingSuspendsEvidenceAndNormalResumesSameScan | 模拟回调范围足够。 |
| 旧ARSession回调 | T16及同类failure/interruptionEnd方法 | 模拟器身份范围足够。 |
| 中断/取消/新扫描 | T14/T15、T07；取消估算及late export方法 | 对应逻辑范围足够。 |
| GPU未写完时结束 | RendererStateAccess.waitForPointCloudWritesToComplete；export utility worker调用 | **不足**。没有在已执行方法中确认一个GPU在途/超时/permit回收故障用例；后续先补确定性屏障回归，真GPU仍单独验证。 |
| 排空期间取消 | T21/T22/T23，finishing flush T13 | 对应队列逻辑足够。 |
| 结果保存重试 | T06 | 失败阶段复用范围足够；物理页面重试未验收。 |
| 取消与提交竞争 | T07，取消失败持久化/迟到export方法 | 模拟器事务范围足够。 |
| 源PLY被替换 | T31/T29，source change during staging方法 | 源/revision逻辑足够。 |
| manifest缺失/损坏 | T40、stale/corrupt companions和metadata内容损坏回归 | 当前拒绝样例足够；不代表穷尽所有损坏输入。 |
| 写入失败与恢复 | T41/T42/T43/T34 | 有文件权限/发布故障注入；**掉电/磁盘满与恢复标记失败组合尚不足**。 |
| 批量数量溢出 | T44 | Int边界回归足够。 |
| 旧校准上下文 | CalibrationRecordPersistenceTests.testDefaultCalibrationContextRetainsEstablishedCanonicalBytesAfterConfigSimplification；T03/T28 | canonical bytes/不可确认身份拒绝足够。 |
| 低置信度深度 | T20；FusionValidatorTests.testValidateDoesNotFuseCandidateUsingLowConfidenceDepth | 拒绝逻辑足够；真实LiDAR噪声待验收。 |
| 拒绝候选回退 | FusionValidatorTests.testValidateDoesNotFuseCandidateUsingFallbackDepthWhenROIDepthInvalid | 对应回退拒绝足够。 |
| 候选顺序变换 | T35/T36/T37 | 固定合成预期足够。 |
| 实测几何保留 | T36/T37、多尺寸果实回放 | **合成几何传递足够；真实实测几何准确性待证明**。 |

## 6. 核心不变量与交付门槛

| 不变量 / 门槛 | 当前证据与限度 |
|---|---|
| 只有fused可靠；imageOnly/cloudOnly不估产 | restricted init与ReplayTests的image-only/cloud-only零产，builder不允许image-only放大可靠confidence。 |
| low depth/low confidenceMap不能升级；拒绝不能fallback升级 | FusionValidator的low confidence、ROI invalid、copyFailed；T19/T20/T38。 |
| zeroYieldReasons、scan/confidence/debug诊断保持 | builder空输入/置信度复制失败、Replay研究导出保留拒绝和来源；不删除诊断字段。 |
| manifest1–3、legacyJSON/CSV、ASCII/LE/BE PLY读取 | codec显式1–3；T39使用v1；T28读v3后改v2保持读取且禁止无源身份校准；legacy无manifest与格式解析回归存在。 |
| 保存完成需manifest最后且确认原始source/sidecar/revision | T28–T31/T34；reader直接核原始字节摘要。 |
| dirty work、模型/shader/训练/论文材料保护 | 本轮全部308 Swift摘要、11已有路径保护；仅新增本表/执行记录，无生产删除或Git交付。 |
| 风险测试、结果树、编译与原生/物理证据分列 | 1073方法真实树；本轮Domain与Release；47原生图引用为历史证据，48不冒充重新走查。 |

## 7. 下一轮优先处理：Renderer设置与容量来源

发现是可追踪的源码边界问题，**尚未新增失败回归，不预先认定具体运行后果**：

1. [ScanView](../../FruitTreeScanner/Views/ScanView.swift#L14) 默认创建 `ScanCoordinator()`，没有传 `appDependencies.settings`；[MetalView.makeUIView](../../FruitTreeScanner/Views/ScanMetalView.swift#L23) 创建 Renderer 时也未传根设置或捕获配置。
2. [Renderer.init](../../FruitTreeScanner/Core/Renderer.swift#L210) 的 `maxPoints` 来自 `SettingsStore.shared.maxPointCount`；随后 lazy particlesBuffer按该值分配。
3. [Coordinator.loadSettings](../../FruitTreeScanner/Core/ScanCoordinatorWorkflows.swift#L13) 在没有 activePlan 时调用无参数 `renderer.applyScanQualitySettings()`，它再次读取共享设置。
4. [ScanPlanFactory.makePlan](../../FruitTreeScanner/Application/ScanPlanFactory.swift#L197) 依据已经分配的 `particlesBuffer.count` 截断根 settings 的点数；因此先从共享值分配，再捕获根值的顺序需要验证。
5. `ScanSettingsProviding` 目前没有渲染/容量完整值，不能只把现有调用改成 `settings.maxPointCount` 而忽略真实类型与平台初始化顺序。

完成标准：用隔离根设置与共享设置刻意不同的真实 ScanView/MetalView/Renderer 路径，先证明协调器/容量/预览设置来自错误来源，再将协调器输入、初始资源与预览配置由根装配或已有值捕获边界显式传入。覆盖绑定前、延迟settings load、创建计划、扫描中reload、换绑和无效容量上限；默认公共入口仍保持兼容。禁止通过扩大到固定300万点、取消clamp或变更深度/融合阈值“解决”问题。避免测试修改真实shared偏好；若必须短暂捕获/还原，保护整份持久suite和参数文件。

后续依赖顺序：关闭该实际根配置缺口 → 补GPU屏障确定性故障证据 → 把剩余可靠准入/数值编排纳入领域边界（先基线、保留fileprivate构造权限）→ 设计有界真实观测包与资源记录 → 由操作者完成同设备实测。必要时按实际严重度调整，不把文档列表当自动扩大改动范围的授权。

```text
继续 FruitTreeScanner 第49轮，先读取AGENTS.md、工作流和本核验表并preflight。
原R0–R7整体目标仍未完成；48只完成范围审计，当前Domain24文件和Release通过，
1073项结果树为已核验的47轮证据，未重新运行XCTest。
保护六项既有工作流及46/47轮源码/测试；不要提交或推送未授权改动。
追踪根AppDependencies.settings→ScanView→MetalView→Renderer初始化→绑定/延迟settings load→makePlan。
用根设置与shared设置不同的隔离夹具，先建立真实容量/预览来源失败回归。
检查lazy粒子buffer第一次分配时机和现有ScanSettingsProviding类型，不能臆造字段。
明确传递现有不可变渲染设置/初始容量，让根配置成为这条路径的来源；保留默认兼容入口。
保持捕获上限、analysis/live预算、深度/融合阈值、计划冻结、cache失效和绑定身份验证。
覆盖未开始计划、延迟回调、后续设置变化、扫描中reload、换绑及上限，保护持久数据。
完成lifecycle/ui相关定向、可行full/Release、iOS原生走查和独立只读复审。
不要同时重写领域流水线、存档格式或资源采样；分别记录后续原范围缺口。
本轮只在失败根因和完成标准关闭后交付，整体目标继续active。
```

## 8. 本次核验交付

本核验文件可独立审查；原蓝图保持历史提案，既有 46/47 轮记录与改动保留。本轮未提交、未推送、未合并。新发现的根配置来源、领域覆盖、GPU故障用例、真实观测和资源/物理缺口均未被标为完成。账户用量造成的首次Release审批失败未执行构建；重新读取用量确认恢复后经审批启动并通过。首次无缓存位置覆盖的Domain命令因沙箱缓存权限失败，缓存移至仓库外后重跑；中途会话handle丢失的尝试不计成功，仅采用已留存退出码的最终Domain记录。

最终核验与复审见本轮执行记录和仓库外 `final-source-preservation.json`、`final-review.json`。本次文档核验的决定与整个架构目标的决定分列，不能凭文档可合并将目标标记完成。
