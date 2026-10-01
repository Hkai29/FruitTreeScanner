# FruitTreeScanner 重构行为基线

日期：2026-09-26。R0 基线在生产代码修改之前采集。

## 1. 检出状态与验证环境

| 项目 | 基线 |
|---|---|
| 基线提交 | `81f49a6ec3d5582343d52cdafdd1354e53871358` |
| 基线分支 | `main` |
| 实施分支 | `codex/scan-architecture-refactor` |
| 初始工作区已有改动 | `docs/README.md` 已修改；两份 2026-09-26 架构文档未跟踪。均予以保留。 |
| Xcode | `/Users/reece24/Downloads/Xcode-beta.app`，Xcode 27.0，Build 27A5194q |
| 模拟器 | `FruitTreeScanner-iPhone-17-iOS27`，iOS 27.0，UDID `C722B4F0-E16F-4C14-84A1-8C796DB0FE11` |
| 工程配置 | iOS deployment target 16.0；Swift 5.0；App 与 XCTest 两个 target |
| 源码规模 | `FruitTreeScanner/` 下 255 个 Swift 文件、45,908 行（含空行与注释） |

初始时模拟器为关机状态。两组测试均由上述 iOS 模拟器目标启动并完成。此次只运行 XCTest，没有操作模拟器 UI，也没有连接 LiDAR 真机。

## 2. 生产调用链

```text
ScanView.startRecording / stopRecording / finishScan
  → ScanCoordinator 与 ScanLifecycleController
  → Renderer.savePointCloud
  → ScanYieldEstimationController
      → ScanCoordinator.flushPendingDetections
      → ScanCoordinator.makeYieldEstimationSnapshot
      → ScanFusionYieldBuilder.build
          → PointCloudCandidatePipeline + DetectionDepthCandidatePipeline
          → FusionEvidencePipeline
          → YieldResultComposer + ScanFusionDiagnosticsUpdater
  → ScanResultExportService.exportIfNeeded
  → ScanHistoryStore.readRecords / PLYCompanionResultReader 验证
  → BatchExportService / 校准记录读取
```

当前扫描结束入口在视图：[`ScanView+Export.swift`](../../FruitTreeScanner/Views/ScanView+Export.swift#L26) 负责停止录制、进入 finishing、启动 PLY 导出、触发估产、提交 companion 文件、更新结果 UI 和刷新历史。它还直接组装持久化请求，并从 PLY 读取原始元数据（同文件 54–109、145–168、171–184 行）。`ScanCoordinatorWorkflows.swift` 中有实际捕获、检测排空、最终快照与生命周期转换；[`ScanYieldEstimationController.swift`](../../FruitTreeScanner/Core/ScanYieldEstimationController.swift#L21) 将排空和快照交换放在主 actor 流程，将融合计算放在 detached task。

[`ScanFusionYieldBuilder.swift`](../../FruitTreeScanner/Core/ScanFusionYieldBuilder.swift#L4) 继续作为估产入口。它分别运行点云候选与检测深度候选流水线，再由 `FusionEvidencePipeline` 作融合准入，最后交给结果合成与诊断更新。估产输入本身是 `@unchecked Sendable`，并持有点云数组与检测值；[`DetectedFruit`](../../FruitTreeScanner/Core/FruitDetectionModels.swift#L17) 又携带复制后的 depth/confidence `CVPixelBuffer`。这属于待逐步收紧的所有权边界，当前不代表已经发现错误结果。

PLY 导出由 Renderer 等待在途 GPU 写入、按 `analysisInputSampleLimit` 采样和去噪、缓存分析快照，再构造整份 PLY `Data` 并交给文件保存（[`RendererPointCloudExport.swift`](../../FruitTreeScanner/Core/RendererPointCloudExport.swift#L223)）。当前设置为：默认点数 1,000,000、可配置上限 3,000,000；实时快照上限 240,000 点、分析输入上限 120,000 点。此处只有源码预算，没有本轮真机内存或耗时测量。

[`ScanResultExportService`](../../FruitTreeScanner/Core/ScanResultExportService.swift#L78) 通过事务协调器串行化每个源文件的写入/丢弃，并验证 revision、sidecar 摘要和源 PLY 摘要。R6 回看基线提交时确认：旧实现先发布 manifest，再发布 metadata/可选 CSV；读取端在文件不匹配时拒绝完成状态，R6 已将发布顺序改为 manifest 最后。读取端 [`PLYCompanionResultReader`](../../FruitTreeScanner/Core/PLYCompanionResultReader.swift#L27) 支持旧无 manifest 记录和 schema 1–3 的事务记录。历史由 `ScanHistoryStore` 单独枚举和解析 PLY，删除也从该 store 直接执行；校准记录使用独立的 `CalibrationRecordPersistence`。因此扫描记录的写入、删除、读取和校准读取目前由多个入口协作，后续统一时必须保留已有事务与兼容行为。

## 3. 状态、任务与数据所有者

| 状态/数据 | 当前所有者 | 事件语义与观察 |
|---|---|---|
| 生命周期 | `ScanCoordinator.scanLifecycle` 持有的 `ScanLifecycleController`，内部用锁保护状态、`scanIdentity`、`generation` 和中断诊断 | 开始产生新 scan identity；用户暂停/恢复改变生命周期 generation；完成只允许从 finishing 进入 completed。 |
| 同步证据准入 | `ScanCoordinator` 的锁保护 `acceptsReliableEvidence`、独立 `reliableEvidenceGeneration` 和 `capturedEvidenceInvalidationEpoch` | 新帧只能在门开启时取得 token。暂停/正常完成关闭新帧准入，但已捕获 token 在同一 identity 下仍可于 paused/finishing 提交；中断、失败、取消或 teardown 推进失效 epoch。相机 tracking 暂停也阻止新帧，同时保留正常 tracking 时捕获的在途证据。 |
| 页面投影与副本 | `ScanView` 的 `@State` 保存 `isRecording`、`isEstimating`、`lifecycleSnapshot`、`savedFilename`、`resultScanIdentity`、`yieldResult`、持久化状态及结果弹层状态 | Coordinator 生命周期经回调投影到页面；若干录制/估算/结果字段仍由不同页面动作与回调分别维护。它们是 R2/R3 应收敛的职责边界，不是本轮已复现的 UI 不一致。 |
| 检测队列与帧缓冲 | `ImageDetector` 的锁、串行 detection queue、`queueGeneration`、一个准备中帧和至多一个待处理帧；入队时复制 RGB/depth/confidence buffers | 限流避免高帧率积压；`clearQueue()` 推进内部队列 generation。检测结果追加到 Coordinator 的活动/稳定证据归档，执行时校验 scan identity、证据 token 和 archive revision。 |
| 估算工作 | `ScanYieldEstimationController` 持有 `YieldEstimationRequestGate` generation 与 `Task`；Coordinator 在回调时再验证生命周期 generation；页面另验 scan identity | 估算可取消且旧请求不能交付到更新请求。系统中没有统一命名的 `WorkID`；不同层目前各自持有请求或回调身份。 |
| 点云 | `Renderer` 持有 Metal 粒子环形缓冲及 GPU 写屏障；导出和估算路径生成值数组与缓存快照 | 最终分析输入有界；渲染缓冲与领域点类型之间仍有转换。没有本轮 COW 拷贝或峰值存活测量。 |
| 扫描文件 | `ScanResultExportService` 写入/丢弃事务；`ScanHistoryStore` 读取摘要并独立删除文件；reader 验证 companion | 已有 revision、SHA-256、schema 兼容和恢复机制；基线 manifest 发布顺序为先于 sidecar，R6 改为最后发布。新统一仓储必须复用其余规则。 |
| 设置与校准 | `SettingsStore` 持久化设置；Coordinator 在开始时捕获 `ScanFruitConfiguration`；Renderer/其他服务仍可读取共享设置；校准上下文由 `YieldCalibrationContext` 计算并另行存储 | 已有估产配置快照，但还不是覆盖设备、检测、预算、模型身份和运行计划的完整 `ScanPlan`。 |

### 生命周期事件表

| 事件 | 新帧准入 | 已捕获证据 | 结果/文件 |
|---|---|---|---|
| 用户暂停 | 关闭 | 同 identity 的 token 仍可提交；检测队列允许被 finishing 流程排空 | 保留，可恢复同一扫描 |
| tracking 临时降级 | 关闭 | tracking 正常期间捕获的 token 可在同 scan identity 下完成 | 保留 |
| 用户完成 | 关闭并进入 finishing | 显式 flush 后冻结快照，随后估产 | PLY → 估产 → 事务 companion 保存；失败结果可重试保存 |
| 系统中断/AR 失败 | 立即关闭并推进 evidence invalidation epoch | 旧 epoch 的迟到结果被拒绝 | 按现有恢复 UI 决定重开或放弃；旧估算回调不应覆盖新 identity |
| 取消/新扫描/teardown | 关闭并失效旧 token | 旧任务不可写入当前扫描 | 未完成文件走丢弃路径；completed 记录由历史删除语义处理 |

排空实现当前包含 25 ms 轮询：`ImageDetector.drainPendingFrames()` 等待帧复制完成，再由 `ScanCoordinator.flushPendingDetections()` 等待已启动的检测任务并处理剩余队列。正常停止不会使已捕获证据失效；这种语义由 lifecycle/concurrency 测试覆盖。后续改事件通知或 barrier 时必须维持这一差异。

## 4. 已有测试与实际运行结果

| 运行 | 覆盖 | 结果 |
|---|---|---|
| 第一组 targeted XCTest | ScanLifecycleController、ScanCapturedEvidenceConcurrency、ScanCoordinatorCameraTracking、FusionValidator、DetectionDeduplicator、ScanFusionYieldBuilder、DetectionDebugState、PointCloudProcessing、ScanExportReadiness、BatchExportService、CalibrationRecordPersistence | 440 tests，0 failures；`TEST SUCCEEDED`；测试执行 7.181 秒，Xcode 总计 29.236 秒。结果包：`/Users/reece24/Library/Developer/Xcode/DerivedData/FruitTreeScanner-glhqyvxijtffpqetxsicxtrfxgby/Logs/Test/Test-FruitTreeScanner-2026.09.26_21-54-05-+0800.xcresult`。 |
| 第二组 targeted XCTest | YieldEstimationRequestGate、ScanCoordinatorSessionRestart、ScanCoordinatorARSessionIdentity、MetalViewBindingLifecycle、ScanReadinessRecoveryBinding、ScanSessionConfiguration | 27 tests，0 failures；`TEST SUCCEEDED`；结果包：`/Users/reece24/Library/Developer/Xcode/DerivedData/FruitTreeScanner-glhqyvxijtffpqetxsicxtrfxgby/Logs/Test/Test-FruitTreeScanner-2026.09.26_21-58-19-+0800.xcresult`。 |

两组运行合计 467 项通过、0 失败。测试包含内存合成输入和故障注入，覆盖融合拒绝/可靠来源、零产原因、检测去重、点云处理、生命周期与绑定、保存重试、manifest 校验及校准存储。工作区没有单独维护的生产扫描回放样例，因此没有形成候选 ID/产量/诊断的版本间黄金文件比较；本次无代码行为变更，不将测试运行时当作算法或硬件性能基线。

本轮没有执行完整测试套件、Release 构建、模拟器 UI 流程或真机 LiDAR 采集。尚无 30/60/120 秒 LiDAR 运行、峰值缓冲存活、阶段耗时或真实果数/重量对照数据。以上属于明确的后续验收缺口，不由模拟器测试替代。

## 5. R0 缺口与迁移约束

1. 生产结束流程的 UI 编排、副作用入口和生命周期投影尚未收敛；先在 R1/R2 明确配置与流程接口，再考虑 `ScanSession`，不能通过删除状态字段来假定其已派生。
2. `ScanID`、证据 epoch、检测队列 generation、估算请求 generation 和 AR/Metal 绑定 identity 分散于不同所有者；迁移需分别保持失效语义。
3. `DetectedFruit` 与估算输入跨边界持有 CoreVideo buffer/unchecked Sendable；必须先证明 Observation 保留 ROI、深度置信度来源、位姿和拒绝理由，再缩短 buffer 生命周期。
4. 文件写入和删除的调用入口分散，但当前事务、manifest、摘要、恢复及旧格式读取已有较强测试覆盖；不能先重写格式或移除协调锁。
5. 点云与检测队列有明确数量上限；需先测量真实拷贝与峰值存活，才能声称内存改善。全局点云去噪与候选点去噪保持不同语义。
6. `YieldEstimator` 是待进一步核实的旧路线；R7 前需复查生产、测试、脚本和研究调用。`FruitCounter` 当前仍参与结果合成，保留。

R0 完成。下一阶段按提案先收拢扫描配置，维持 iOS 16、Swift 5、单 App target、既有算法阈值和文件格式兼容。
