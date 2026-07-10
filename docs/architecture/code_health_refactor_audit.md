# Code Health and Refactor Hotspot Audit

本审计基于当前分支从 `main` 同步后的代码，只做静态检查和职责分析。审计范围覆盖生产 Swift、指定 App 文件、`tools/ml`、`ml/audit_reports` 和 recognition training audit 文档。

## 1. Summary

结论：当前代码不是“全仓屎山”，已经有明显的 service split 和 presentation split；但仍有几个需要按小步、带基线测试处理的重构热点。

最大的 code-health 问题不是某一个 800 行文件，而是状态与契约跨层耦合：

1. `ScanCoordinator` 仍同时持有 AR session、Renderer、检测队列、检测证据、HUD、扫描完成度、相机速度和 yield task。文件已经拆成 extension，但对象职责没有真正拆开。
2. `ScanYieldDiagnostics` 是一个约 64 个字段的扁平状态袋，混合 point-cloud、depth、fusion、canopy、coverage、calibration、recognition 和 zero-yield 诊断。它被 builder/updater、Result UI 和 export 同时消费。
3. 新的 `ScanFusionYieldBuilder` pipeline 与旧的 `YieldEstimator` 并存。旧类目前主要由测试和历史文档保留，但仍然提供另一套双路线估算语义，容易造成维护者误判生产入口。
4. ML tooling 的 `apply_dataset_cleanup.py`（869 行）把数据读取、YOLO label 校验、审批 CSV 校验、目标计划、dry-run 报告和 apply copy 放在同一脚本中；这是 ML tooling 中最明显的 God Script。

当前没有发现编译错误、行为回归或数据损坏证据。本任务未修改实现，也没有执行训练或 dataset apply。

## 2. Formatting / Single-Line Source Findings

### 2.1 统计方法和结论

对仓库内 Swift/Python 文件统计了 line count、character count、average line length 和 max line length，并额外筛选了不超过 3 行、平均行长至少 150、或最大行长至少 300 的文件。

- 生产 Swift：252 个文件，32,312 行。
- `tools/ml`：14 个文件，5,279 行。
- 没有发现被压成一行或极少行的 Swift/ML Python 源文件。
- 没有发现“大量源码单行化”问题，因此本项没有 P0。
- 发现的超长行都来自长日志或论文正文字符串，不属于源代码整体压缩。

### 2.2 超长行候选

| file path | line count | character count | average line length | max line length | risk |
| --- | ---: | ---: | ---: | ---: | --- |
| `research/paper/generate_paper.py` | 364 | 31,833 | 86.5 | 1,288 | P2 可读性风险；长行主要是中英文论文段落字符串，不是逻辑被压成一行。仅在该脚本下次维护时处理。 |
| `FruitTreeScanner/Core/ScanFusionYieldBuilder.swift` | 77 | 3,487 | 44.3 | 397 | P3；第 45 行是聚类统计日志，影响 diff 和 review，但不影响语义。 |

`tools/ml/generate_semantic_review_assistant.py` 的最大行长为 296，仍属于 HTML/文本生成场景；没有证据表明它需要立即格式化。审计期间不自动格式化任何文件。

## 3. Existing Good Decomposition

以下区域已经拆得比较好，不应因为单个文件偏大就立即重构：

- Fusion：`FusionValidator.swift`、`FusionValidatorMatching.swift`、`FusionValidatorProjection.swift`、`FusionValidatorServices.swift` 已按核心验证、matching、projection/depth、services 分散。`FusionValidatorProjection.swift` 仍然偏大（817 行），但内部已经进一步包含 `DetectionDepthCandidateBuilder`、`DepthSampler` 和 `DepthConfidenceSampler`，属于下一阶段的可选拆分，而不是当前的 God Object。
- Renderer：`Renderer.swift`（199 行）把 AR/Metal 核心状态保留在主类型，帧渲染、Metal helper、point-cloud access/export、scan progress/settings、depth coverage 通过 `Renderer*.swift` extensions 分散。结构方向正确，风险集中在共享可变状态，而不是文件长度。
- ImageDetector：`ImageDetector.swift` 是 facade/state，旁边已有 `ImageDetectorModelLoading.swift`、`ImageDetectorQueue.swift`、`ImageDetectorInference.swift`、`ImageDetectorInferenceSupport.swift`、`ImageDetectorYOLOParser.swift`、`ImageDetectorYOLOSupport.swift` 和 `ImageDetectorDebugging.swift`。这已经覆盖 model loading、queue、inference、parser、debugging 的主要边界。
- Scan/fusion orchestration：`ScanFusionYieldBuilder.swift`、`ScanFusionPipelines.swift`、`ScanFusionDiagnosticsUpdater.swift`、`YieldResultComposer.swift`、`FusionValidator*`、`DetectionDeduplicator.swift` 已经形成 pipeline、diagnostics、composition、validation、deduplication 的分层。
- Batch export：`BatchExportService.swift` 已委托给 `BatchExportCSVWriter.swift`、`BatchExportExcelWriter.swift`、`BatchExportJSONWriter.swift` 和 `BatchExportFormatting.swift`。这是推荐保留的拆分方式。
- Result UI：`ResultView.swift`（65 行）、`ResultSummaryComponents.swift`、`ResultDiagnosticsSection.swift`、`ResultActionButtons.swift`、`ResultCardRows.swift` 和 `ResultPresentationModels.swift` 已将页面、组件、diagnostics 和 presentation mapping 分开。`ResultPresentationModels.swift` 425 行主要是展示映射，不应仅按行数拆分。
- Scan UI：`ScanView.swift` 及其 `+Actions`、`+Export`、`+Lifecycle`、`+State` 和 overlay 文件也已经避免了一个巨型 SwiftUI body。
- ML tooling：`audit_yolo_dataset.py` 被 `apply_dataset_cleanup.py`、`plan_test_split.py` 和其他审计脚本复用其中的 YAML/图像扩展能力；`export_coreml.py`、`check_data_yaml_app_mapping.py`、`check_model_metadata.py` 已形成独立 guardrail 入口。当前问题主要是公共 I/O helper 仍有复制，而不是完全没有分层。

## 4. Refactor Hotspots

### P1 — `ScanCoordinator` 是状态型 God Object

证据：`FruitTreeScanner/Core/ScanCoordinator.swift:14-95` 同时持有 AR session/MTKView/Renderer、扫描覆盖率、completion、detected fruits、HUD callbacks、display link、camera speed、detection lock、`ImageDetector` 和两个异步 task。`FruitTreeScanner/Core/ScanCoordinatorWorkflows.swift:196-265` 又负责读取 settings、flush detection、提取点云、加载 calibration、组装 `ScanFusionYieldBuilder.Input`、启动 detached task、清理共享状态并回调 UI。

这不是“文件太长”问题，而是生命周期和线程边界集中在一个对象中。特别是 post-capture estimation 需要同时访问 Renderer、ImageDetector、MainActor 状态和持久化 calibration，后续拆分若没有快照边界，容易引入 task cancellation、重复 completion 或检测证据丢失。

建议先拆出纯 snapshot/input builder，再考虑 `ScanDetectionCoordinator` 和 `ScanYieldEstimationCoordinator`。不建议一次性重写 `ScanCoordinator`。

### P1 — `ScanYieldDiagnostics` 是跨域字段袋

证据：`FruitTreeScanner/Core/YieldEstimateModels.swift:46-109` 同一 struct 混合 point-cloud 计数、depth candidate、fusion source counts、calibration、canopy geometry、coverage、image model、label compatibility、selected fruit filter 和 `zeroYieldReasons`。`ScanDiagnosticsBuilder.swift`、`ScanFusionDiagnosticsUpdater.swift`、`YieldResultComposer.swift`、`ScanResultExportService.swift:209-224`、`ResultDiagnosticsSection.swift` 同时依赖它。

它目前是有价值的诊断契约，不应直接删除或随意改字段。长期方向是增加嵌套的 `PointCloudDiagnostics`、`FusionDiagnostics`、`RecognitionDiagnostics`、`CanopyDiagnostics` 和 `ScanQualityDiagnostics`，再由 export 层提供兼容的扁平 payload；这需要先锁定 JSON/CSV 字段和 zero-yield 语义。

### P1 — 新旧 yield engine 并存

`FruitTreeScanner/Core/YieldEstimator.swift:9-198` 仍然包含 route A regression、route B clustering、双路线 fuse 和一站式 `run`。当前生产路径从 `ScanCoordinatorWorkflows.swift:237` 进入 `ScanFusionYieldBuilder.build`；`YieldEstimator` 没有被生产调用搜索命中，但仍有 `YieldEstimatorTests.swift` 和历史文档引用，`PointCloudCluster.swift:25` 还保留“用于 YieldEstimator”的注释。

这会造成“哪个 engine 是可靠估产入口”的认知分叉。建议先完成 usage inventory、结果差异对照和文档标注，再决定 deprecate、迁移测试还是删除；本审计不建议现在删除旧类。

### P1 — `tools/ml/apply_dataset_cleanup.py` 是 God Script

该脚本 869 行，入口链路覆盖：参数解析、源 dataset 加载、YOLO label 解析、记录收集、duplicate decision 校验、split decision 校验、target plan、dry-run summary 生成和最终 staging/copy。对应函数分布在 `:77-326`、`:405-600`、`:607-718`、`:721-869`。

它的 guardrails（源数据不改、审批必须完整、目标目录不能覆盖源目录、staging 后 replace）是正确方向，不能因拆分而弱化。建议先把纯数据模型/CSV/YAML I/O 提取为共享模块，再把 `target_plan` 和 `write_target_dataset` 分离；apply 行为本身最后动。

### P2 — `FusionValidatorProjection.swift` 仍偏大但已有内部边界

该文件 817 行，包含 robust depth、2D-to-3D projection、ROI depth candidate building、尺寸/颜色/centroid helpers、depth pixel format 读取和 confidence map 读取（`8-243`、`245-688`、`690-817`）。这是最值得拆的 Swift 算法文件之一，但同时直接承载低置信度 depth 不得升级为 `.fused` 的可靠性边界。

可选拆分方向：`ProjectionMath`、`DetectionDepthCandidateBuilder`、`DepthSampler`。必须先补齐 projection/depth confidence/invalid pixel 的 characterization tests，拆分时保持函数签名和决策顺序不变。

### P2 — `ImageDetectorInference.swift` 仍混合执行、解析映射和诊断

`FruitTreeScanner/Core/ImageDetectorInference.swift:11-63` 负责队列执行和 model dispatch；`:66-206` 负责 CoreML/Vision request、feature observation fallback、错误记录和 debug diagnostics；`:209-261` 负责 observation-to-fruit mapping 和 classification fallback。虽然周边文件已经拆好，但该文件仍把“推理执行”“输出解析/映射”“诊断记录”绑在一个流程中。

建议未来提取无状态的 `CoreMLInferenceExecutor`、`ObservationMapper` 和 `DetectionDiagnosticsRecorder`，但不要在没有模型输出 fixture 的情况下修改当前 CoreML fallback、YOLO parser 或 confidence filtering。

### P2 — ML tooling 有重复 I/O helper 和相邻职责重叠

`apply_dataset_cleanup.py:147-168`、`audit_dataset_invalid_images.py:99-112`、`generate_semantic_review_assistant.py:117-128` 各自实现 CSV 读取；`repo_path`/`display_path` 也在多个脚本重复。`audit_yolo_dataset.py:403-565` 负责主审计，`:584-640` 负责报告写出；`plan_test_split.py`、`audit_dataset_invalid_images.py` 和 cleanup script 又各自读取同一类 dataset 结构。

建议建立一个很小的 `tools/ml/dataset_io.py`，只放路径、CSV、YAML 和 image/label pairing 的无状态 helper，不把业务决策放进去。这样能减少重复而不把所有脚本合并成一个框架。

### P2 — `point_cloud_analyzer.py` 是独立的算法漂移风险

`tools/ml/point_cloud_analyzer.py` 604 行同时实现 PLY ASCII/binary 读取（`:38-121`）、颜色启发式（`:128-184`）、质量报告、DBSCAN 和球形度筛选（`:284-378`）、可视化和端到端重量估算（`:381-604`）。脚本注释声称“复刻 iOS 端”，但它维护自己的颜色阈值、DBSCAN 参数和密度估算，不是生产 `PointCloudCluster`/fusion pipeline 的可执行共享实现。

如果它继续作为研究验证工具，应该明确“diagnostic approximation”而不是 production parity；如果需要做 parity，则应导出可复现 fixture 并建立对照测试。当前不建议把它直接并入 App 或反过来驱动生产阈值。

### P3 — 单扫描 export service 可继续拆，但不紧急

`ScanResultExportService.swift` 318 行同时生成 CSV、metadata JSON、recognition diagnostics、fruit mass/validated fruit payload，并负责数值清洗和 CSV escaping。Batch export 已经拆好，因此下一步可提取 `ScanResearchJSONPayloadBuilder` 和 `ScanCSVWriter`，但必须先保留现有字段、有限值处理和 `zeroYieldReasons`。

## 5. Do Not Touch Yet

- 不要先拆 `Renderer`/Metal 核心采集、depth buffer、point-cloud buffer 和 capture state。当前 extension 拆分已经改善可读性，真正风险是共享状态和实时性能；需要设备或至少 targeted capture tests。
- 不要修改 `FusionValidator` 的 projection/matching decision policy、`.fused` 唯一可靠来源规则、rejected depth fallback、confidence map 规则或 `zeroYieldReasons`。这些是 thesis-critical/product-critical invariant。
- 不要改变 `ImageDetectorInference` 的 CoreML/Vision fallback、YOLO MultiArray 解析、confidence filtering、label mapping 或 diagnostics 语义。先建立模型输出 fixture 和 export compatibility tests。
- 不要直接拆或删除 `tools/ml/apply_dataset_cleanup.py` 的 apply 逻辑。dataset apply 涉及审批 CSV、源数据保护、staging copy 和 labels remap，应先提取纯 helper，再逐步验证 dry-run/apply preflight。
- 不要移动、删除或重写 dataset、labels、CoreML model 或 `ml/audit_reports` 生成结果作为“清理代码”的副作用。
- 暂不拆 `CanopyGeometryEstimator.swift`（687 行）和 `DetectionDeduplicator.swift`（615 行）。它们体量大但当前职责相对集中，先做行为基线和 profiling 比按行数拆更重要。
- 暂不为了“变小”拆 `ResultPresentationModels.swift`。它是 presentation mapping 集中处，拆散后反而会增加 UI/export 追踪成本。

## 6. Recommended Refactor Roadmap

### P0 — 建立不可回归基线（不是立即拆生产代码）

- 目标：在任何职责拆分前锁定 `.fused`、zero-yield、diagnostics、export fields 和当前生产 yield entry point。
- 涉及文件：`docs/architecture/`、`FruitTreeScannerTests/FusionValidatorTests.swift`、`DetectionDeduplicatorTests.swift`、`ScanFusionYieldBuilderTests.swift`、`DetectionDebugStateTests.swift`、`ScanDiagnosticsBuilderTests.swift`、相关 export tests。
- 是否改行为：否。
- 风险：低；主要是测试/文档基线维护成本。
- 测试：运行 AGENTS.md 指定 fusion/dedup/yield/diagnostics targeted tests，并检查 single/batch JSON 字段。
- 是否适合 Codex 自动改：适合自动补测试和生成字段快照，但 invariant 取舍需要人工 review。

### P1 — 提取 ML tooling 公共 I/O helper（首选第一步）

- 目标：从多个脚本抽出 `repo_path`、`display_path`、CSV 读取/写入、dataset path resolution 等纯 helper，避免 `apply`、invalid-image、semantic-review 和 split scripts 各自复制。
- 涉及文件：新增 `tools/ml/dataset_io.py`；`tools/ml/apply_dataset_cleanup.py`、`audit_dataset_invalid_images.py`、`generate_semantic_review_assistant.py`、`audit_yolo_dataset.py`、`plan_test_split.py`。
- 是否改行为：预期否；CLI 输出、CSV schema、路径解析必须保持一致。
- 风险：中；模块导入路径、从仓库根目录运行和脚本直接执行方式容易被误改。
- 测试：`PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile` 相关脚本；每个脚本 `--help`；用小型 fixture 对比 dry-run/report 输出。
- 是否适合 Codex 自动改：适合小步自动改，但 apply script 的最终 diff 需要人工 review。

### P1 — 拆 `ScanCoordinator` 的输入快照边界

- 目标：先提取“从当前扫描状态生成 `ScanFusionYieldBuilder.Input` 所需 snapshot”的纯边界，不先重写 AR session 或 detection queue。
- 涉及文件：`ScanCoordinator.swift`、`ScanCoordinatorWorkflows.swift`、`ScanCoordinatorARSession.swift`、新增小型 snapshot/coordinator 文件。
- 是否改行为：否；只改变状态读取位置和依赖注入方式。
- 风险：高；涉及 MainActor、Task cancellation、detection archive 清理时机和 renderer snapshot 生命周期。
- 测试：targeted fusion/yield/diagnostics tests；新增 cancellation、teardown、empty detection、preserved point cloud tests；必要时 iOS simulator test。
- 是否适合 Codex 自动改：可以自动执行机械提取，但必须人工审查 concurrency 和生命周期。

### P1 — 处理旧 `YieldEstimator` 的生命周期

- 目标：完成 production usage inventory，明确旧 engine 是历史兼容、研究对照还是待废弃入口；先标注文档和测试，不直接删除。
- 涉及文件：`FruitTreeScanner/Core/YieldEstimator.swift`、`FruitTreeScannerTests/YieldEstimatorTests.swift`、`docs/implementation/multi-modal-yield-estimation-plan.md`、`docs/reference/TECHNICAL_DOCUMENT.md`。
- 是否改行为：初期否。
- 风险：中；删除或改名可能影响研究复现实验和测试 target。
- 测试：`YieldEstimatorTests`、新旧 engine 结果对照 fixture、现行 `ScanFusionYieldBuilderTests`。
- 是否适合 Codex 自动改：适合先做 inventory 和文档标注；删除决策不应自动完成。

### P2 — 拆 `ScanYieldDiagnostics` 的域模型，但保持 export 兼容

- 目标：将诊断按 point-cloud/fusion/recognition/canopy/scan-quality 分域，保留现有 flat JSON keys 和 `zeroYieldReasons`。
- 涉及文件：`YieldEstimateModels.swift`、`ScanDiagnosticsBuilder.swift`、`ScanFusionDiagnosticsUpdater.swift`、`ScanResultExportService.swift`、`ResultPresentationModels.swift`、`ResultDiagnosticsSection.swift`。
- 是否改行为：不应改诊断值或导出 schema。
- 风险：高；字段被 UI、single export、batch export 和 thesis field map 同时消费。
- 测试：diagnostics builder/update tests、JSON golden tests、Result diagnostics view model tests。
- 是否适合 Codex 自动改：适合在已有字段快照后分阶段实现；不适合一次性自动重写。

### P2 — 拆 `FusionValidatorProjection` 内部实现

- 目标：将 projection math、depth sampling、ROI candidate construction 分成独立文件，保持可靠性判断和调用签名。
- 涉及文件：`FusionValidatorProjection.swift`、`FusionValidatorMatching.swift`、相关 `FusionValidatorTests` 和 depth fixtures。
- 是否改行为：否。
- 风险：高；属于 2D-to-3D 和 `.fused` 证据边界。
- 测试：projection geometry、depth format、confidence map、invalid depth、candidate rejection 和 fusion decision tests。
- 是否适合 Codex 自动改：只适合在 characterization tests 完整后做机械移动；需要人工复核每个 fallback。

### P2 — 拆 `ImageDetectorInference` 的执行、映射和诊断

- 目标：保留现有 CoreML/Vision fallback，把 request executor、observation mapper、diagnostics recorder 变为清晰边界。
- 涉及文件：`ImageDetectorInference.swift`、`ImageDetectorInferenceSupport.swift`、`ImageDetectorYOLOParser.swift`、`ImageDetectorDebugging.swift`、相关 detection tests。
- 是否改行为：否。
- 风险：高；模型 output shape、confidence threshold、unmapped label 和 fallback 语义必须完全一致。
- 测试：YOLO parser、label mapping、confidence filtering、diagnostics、model failure fixture tests。
- 是否适合 Codex 自动改：可以自动拆文件，但必须人工审查 CoreML callback 和 queue 行为。

### P3 — 处理超长日志/论文字符串

- 目标：在相关文件下一次功能维护时改善长行，不启动全仓格式化。
- 涉及文件：`FruitTreeScanner/Core/ScanFusionYieldBuilder.swift:45`、`research/paper/generate_paper.py:89-90` 等长文本行。
- 是否改行为：日志和论文生成内容应保持等价；不涉及 App 行为。
- 风险：低，但论文生成器可能有输出 diff。
- 测试：`python` 生成器的 smoke test；App 只需编译/相关 log test（如有）。
- 是否适合 Codex 自动改：适合，但优先级低，不应作为独立大范围格式化任务。

## 7. First Safe Task

第一项推荐任务是 **P1：提取 `tools/ml/dataset_io.py` 公共只读 I/O helper**，范围限定为路径解析、CSV/YAML 读取和 image/label pairing；不要在同一任务中动 `target_plan`、label remap 或 `write_target_dataset`。

原因：它能消除真实重复逻辑，影响面小于 App concurrency/fusion，且可以用小型 fixture 对比每个 CLI 的输入输出；它不触碰 Swift、CoreML、模型、labels 或 dataset 内容。完成后再以同样的“纯边界 + golden test”方式处理 `ScanCoordinator` snapshot，而不是直接重写 Renderer 或 fusion rules。
