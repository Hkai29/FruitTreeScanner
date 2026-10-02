# 重构迭代执行记录

创建：2026-09-27；更新：2026-10-02。分支：`codex/scan-architecture-refactor`，基于 `81f49a6ec3d5` 及已有未提交迁移继续实施。

用户目标：进行重构，完成后继续构思下一轮并迭代。当前目标保持进行中；本文件区分已实施、待验证与下一轮范围，不把整个架构迁移宣称为已完成。

## 迭代 1：源身份与取消后的事务结算

实施内容：

- DraftScan 在暂存阶段记录原始文件 SHA-256、设备/文件节点身份和操作所有权；首次提交核对该凭证，拒绝同名、同大小、同 inode 但内容已改变的源。
- Renderer 向上返回 StagedPointCloud，包含凭证和实际写入的 FinalPointCloud。结束流程传递原凭证，不在估算结束后重新按文件名创建草稿。
- 源校验仍在提交锁内执行，保留提交期间源变化检查和原有 manifest/schema/原始字节摘要规则。不同目录中的同名路径不能被凭证混用。
- 取消后的文件结算返回 discarded、preservedCommitted 或 requiresRecovery。先验证文件身份和提交状态，再判断是否清理；不会直接删除已提交记录或由新操作接管的草稿。
- 仓储收尾和历史刷新不再依赖旧 UI WorkID 仍有效。取消后保存失败会结算草稿；取消与提交成功竞争时保留记录并刷新历史。
- 清理失败保留 PLY 历史锚点，保留可恢复原因；旧页面只能接收属于自身扫描的结算状态。

定向验证：120 项 XCTest 通过，0 失败，xcodebuild 退出码 0。

## 迭代 2：冻结估算输入与明确终态

复核发现：保存侧身份得到约束之后，估算仍使用只报告成功的回调，无法解释输入不可用或提供可靠的失败重试。因此本轮继续收紧估算边界。

实施内容：

- 增加可抛错、可取消的异步快照准备和后台估算接口，生产结束流程使用这些接口；旧回调入口暂保留用于兼容。
- 结束流程持有不可变估算 Snapshot 和其 ID；计算失败后重试同一 Snapshot，不重复导出 PLY，不再次消耗检测归档。
- 输入必须携带与 StagedPointCloud 一致的点云签名。估算直接使用实际写入的点集，不依赖 Renderer 缓存仍然有效。
- 估算任务句柄由流程持有，取消传给后台计算；即使替身或旧任务迟到返回，失效任务也不能继续保存。
- 增加估算失败状态、重试动作和中英文用户提示，避免快照不可用时静默停留在 estimating。
- 提交确认后释放草稿所有权。相同凭证对完全相同已提交结果的重试仍幂等；已经失效的凭证不能修改结果。这是本轮自审发现并补齐的二次边界。

定向验证：164 项 XCTest 通过，0 失败，xcodebuild 退出码 0。后续幂等重试与签名校验补充纳入全量验证。

## 迭代 3：取消通知、暂存凭证和资源生命周期

实施内容：

- 检测排空从每 25 ms 轮询改为准备完成、准备失败或队列清空时唤醒。准备状态与等待者注册使用同一把锁，continuation 在解锁后恢复；取消可早于注册发生，每个等待者仅恢复一次。
- 唤醒只通知就绪，不转移帧所有权。等待取消、旧代次清空不会消费新扫描的帧；取消一个等待者不影响其他消费者。
- 结束流程持有可取消的导出 Task；生产导出使用 async throws，并向后台任务传递取消。保留旧 callback 入口作为兼容适配。
- PLY writer 对实际写入的 header/chunk 增量计算 SHA-256，发布前从临时文件取得文件身份。独占 rename 成功后没有新的可抛错凭证读取步骤；仓储直接登记返回凭证，消除发布后摘要读取失败的窗口。
- 发布前取消清理临时文件；发布后取消仍返回凭证，由结束流程结算。覆盖“writer 已发布后取消当前 Task”的回归，验证仍可按凭证清理草稿。
- 估算失败保留冻结输入供重试；估算成功后释放流程持有的点云和 Snapshot，保存重试只保留结果与草稿。取消也解除这两个引用。
- 估算 await 不再强持有整个 workflow；页面退出时解除 onEvent 展示回调。新增弱引用测试验证取消后的流程可在估算替身尚未返回时释放。

定向验证：资源/队列第一批 63 项通过；导出、队列、点云、批量与流程第二批 311 项通过，均为退出码 0。后续发布后取消补充纳入迭代 4 全量验证。

限制：取消是协作式的。Metal 已提交命令保持原有最长 5 秒等待上限，超时返回失败；不会撤销已经提交到 GPU 的命令。已经运行的同步采样/计算需返回取消检查点后释放任务局部输入。上述引用测试不等于真机峰值内存测量。

## 迭代 4：抽出共同的存档访问底层

暂存凭证现在被 writer、仓储和旧 exporter 同时使用，因此先完成共享访问边界，再继续扩展证据身份。

- 新增 ScanArchiveAccess，集中每源文件信号量、草稿所有权和源身份错误。
- Repository 与兼容 exporter 均依赖同一个访问实例；ScanResultExportService 不再调用 ScanRepository，移除反向调用环。
- 保留同文件串行、不同文件可并行、等待锁时取消、提交后确认和 manifest 最后发布。锁顺序明确为 exporter queue → source semaphore → registry lock；registry lock 不跨文件锁等待持有。
- SourcePointCloudError 保留类型别名，旧调用者的错误匹配不变。新文件纳入原 App target，没有增加 target 或系统版本要求。

这是仓储解耦的一部分；动态研究 JSON 读取、可注入装配与完整记录契约仍在下节列为未完成项。

## 迭代 5：将冻结证据绑定到草稿与结果

- 增加 ScanContext（逻辑扫描/计划）、ScanCaptureIdentity（附带点云签名）和 ScanEvidenceIdentity（附带不可变输入 Snapshot ID、源所有权和摘要）。Renderer 写 PLY 时记录 captureIdentity，协调器排空检测后生成带真实活动扫描/计划身份的 Snapshot。
- ScanEvidenceSnapshot.freeze 校验上下文与点云签名，并在源事务锁内将草稿绑定到第一次冻结的 Snapshot。相同绑定可重试，另一批观测不能覆盖该绑定。绑定成功返回构造器受限的 ScanEvidenceReceipt。
- 异步估算器直接返回携带输入身份的 ScanEstimate。workflow 拒绝跨扫描、跨计划、跨 Snapshot 和跨源草稿的输出；保存只接收绑定凭证与对应估算。原始 YieldResult 继续供展示使用。
- ScanAssessment 从绑定凭证和估算生成 exportRequest，仓储提交前再次核对来源；服务新增受校验的 assessment 入口。活跃扫描不能通过旧裸结果接口、遗漏 expectedSource 或重新按路径领取旧式草稿来绕过证据约束。
- 估算失败仍复用同一冻结输入；估算成功释放大数组，仅保存小凭证与结果供持久化重试。提交后对同一结果的幂等重试保留原绑定凭证。
- RendererSnapshotSignature 的纯值定义移入 Domain，保留原类型名；新契约不引入 UIKit/Metal 缓冲或 unchecked Sendable。
- 新增错配扫描/计划/观测/点云/源所有权/摘要的拒绝测试、拒绝重新绑定和兼容入口绕过的测试，以及真实协调器 → 冻结输入 → 估算器 → 临时仓储提交/幂等重试的集成测试。

本轮身份是进程内操作契约。没有把逻辑 UUID 写入旧 manifest.scanID，也没有改变 schema 1–3 的摘要输入、算法阈值或数值公式。历史记录继续沿已有格式验证；跨进程的持久化 provenance 若未来需要，必须单独制定格式迁移。

验证状态：第一批 127 项、绑定凭证定向 167 项通过；全量结果包确认 939 通过、0 失败/跳过。该全量进程句柄随后失效，终端退出码未取回。之后补充了兼容裸导出入口的保护，127 项定向通过、退出码 0。Release 与仓储下一轮一并验证。

## 迭代 6：仓储记录契约与依赖装配

- 将研究 JSON 的 sidecar 字段解析和兼容默认值移入 ScanResearchArchiveCodec。批量 writer 逐条获取仓储返回的已验证记录 Data，不再读取动态 sidecar 键。仅移动原来的单次序列化，没有增加中间 JSON 编解码；未知诊断字段仍保留，原始预测大数组仍按原规则排除。
- 仓储在源文件锁内读取 sidecar、判断缺失/不一致和核对历史摘要，再在锁外编码该不可变字典快照，避免把大记录的编码时间放进文件锁。
- 新增 VerifiedScanRecord，包含现有 ScanFileRecord 摘要与可选 CompletionManifestDTO。构造入口要求合法 PLY 文件头和完整 companion；旧 CSV/JSON 记录的 manifest 保持 nil，不伪造旧记录没有的摘要证据。要求源校验的批量记录使用该入口，保留写出前后两次检查。
- 此处补齐一条拒绝规则：即使 companion 显示 complete，缺失或文件头无效的 PLY 也不能得到 VerifiedScanRecord，不能通过要求源校验的批量导出。新增针对性测试；普通历史摘要仍可展示恢复状态。
- ScanRepository 允许注入目录和 exporter。AppDependencies 提供仓储，并贯穿 ScanView → finalization → coordinator/renderer、freeze、persist、cancel settlement。默认目录/兼容入口保持原用法；各仓储实例共用按规范路径协调的事务锁，不能因实例不同破坏同文件互斥。
- 增加自定义目录及跨目录拒绝测试；真实 production operations 集成测试只替换物理捕获边界，验证准备、估算、落盘、完成事件与历史通知均使用注入仓储。研究 JSON 测试补充未知嵌套诊断和 Int64.max 的保留检查。

自审补充：旧按文件名删除入口也拒绝活跃 capture 草稿，且拒绝时不设置 discardedFilenames，避免污染后续合法提交。

验证过程中先发现历史通知默认回调缺少 MainActor 标记导致编译失败；补齐了接口隔离。随后 129 项通过、1 项失败，失败仅来自新测试的目录 URL 尾斜杠标记不一致；修正为显式目录 URL 后，全量 **942 项通过、0 失败/跳过，退出码 0**。Release 模拟器构建成功，退出码 0。没有剩余已知编译或测试失败。

## 迭代 7：落实计划配置与资源预算

- ScanFusionYieldBuilder.Input 显式携带冻结的 experimentConfiguration，协调器从 activeScanPlan 传入；候选去噪、两次候选合并、融合匹配/拒绝距离和遮挡合成均消费该值。旧入口保留默认参数，默认公式和阈值不变。
- 深度配置在检测入队锁内捕获进 FramePacket，ROI/投影采样在完成推理后使用该帧配置；更新检测器不会改变已经入队帧的采样规则。可靠 confidenceMap 仍至少要求 Medium，实验配置不能接纳 Low；采样网格和候选点保留量保留原有上界。
- RendererScanSettings 捕获深度配置，并传入实际帧质量检查；扫描引导使用同一个计划规则，避免采集已拒绝而提示仍显示正常。
- ScanResourceBudget 删除重复的 particleCapacity/maxCapturePoints 字段：物理容量仍由 Renderer 的 Metal buffer 持有，实际采集上限仍由 RendererScanSettings.maxPoints 持有。预算现在只承载实时点云采样、最终分析采样及活动检测窗口的帧保留上限，并接入实际执行点；已有稳定证据归档规则继续保留，活动窗口上限不表示全部归档观测总数。
- 预算不能扩大现有 240,000/120,000/360 上限。点云预算的读写与缓存失效使用 snapshotLock；最终点云签名附带本次分析采样上限，避免不同预算间复用缓存或混淆证据身份。
- 校准上下文编码实际实验配置，并在预算非默认时编码资源预算；默认预算不新增 JSON 键，保留原默认上下文的编码结构。不同实验或预算不复用旧校准记录。
- 增加计划贯通估算且设置重载不漂移、帧配置不漂移、置信度底线、候选距离/点保留、去噪与遮挡实际生效、预算缓存隔离和校准隔离测试。

定向测试初次 179 通过、1 失败，退出码 65。失败是新增遮挡夹具的默认/自定义两次结果均达到修正系数上限，无法区分配置；换为环绕覆盖的合成冠层后，该测试通过、退出码 0。全量模拟器 **951 项通过、0 失败/跳过，退出码 0**。

该阶段留下的默认种子与运行配置混合问题已在迭代 11 收敛，默认校准上下文编码兼容也有固定夹具验证。

## 迭代 8：分开计划值、应用工厂与展示模型

- Domain/ScanPlan.swift 只保存不可变计划、预算、模型身份和果类配置值；Application/ScanPlanFactory.swift 负责读取设置、加载校准记录、准备模型身份并创建计划。旧 ScanFruitConfiguration.capture 保留为应用层扩展。
- 将生命周期枚举、扫描/绑定/证据身份值移到 Domain/ScanSession.swift，移除其对 Combine 的直接依赖。ARKit 错误分类和追踪状态转换继续留在设备协调器；同步准入门和状态转换没有增加第二个所有者。
- ScanFeatureModel 移到 Views，仅提供 MainActor 上的只读展示投影。迟到快照拒绝、暂停保留在途证据、取消与重新绑定作废旧证据的规则保持不变。
- Xcode 项目引用同步更新，仍为原 App/XCTest target、iOS 16 和 Swift 5。此次是职责迁移，不新增 UI 流程或算法行为。

验证：项目文件结构检查通过；迁移后全量 **951 项通过、0 失败/跳过，退出码 0**。Release 模拟器构建成功，退出码 0。Domain 目录当前只直接导入 Foundation，但仍使用 Core 中的算法值类型；这不等于已经完成独立 Swift package 的依赖证明。

## 迭代 9：结果保留扫描时的校准身份

沿最终落盘链路复核发现：YieldResultComposer.makeVisibleYieldResult 仍自行从默认配置/当前 bundled model 生成 calibrationContext。虽然迭代 7 已让校准匹配使用实际实验配置，结果标记仍可能与本次扫描不同。

- 增加纯值 ScanCalibrationIdentity，包含算法修订和可选 context。协调器创建估算 Snapshot 时复制计划中的身份，结果合成直接沿用。
- 显式不可用的 context 保持 nil；不能在模型后来可用时补成另一个扫描身份。仅未提供计划身份的旧 builder 输入保留兼容计算，此路径也使用 Input 中的实际 experimentConfiguration。
- 新增正产量结果身份回归：固定身份被保留；显式 nil 不回退。计划到 Snapshot 的测试也核对 revision/context。

全量模拟器 **952 项通过、0 失败/跳过，退出码 0**。该修复后的模拟器 Release 与设备 SDK 未签名 Release 均构建成功，退出码 0。后者只证明设备目标可编译，未安装或运行采集验收。该修复没有改变可靠水果集合、数值公式或存档 schema，修复的是输出记录的校准来源标记。

## 迭代 10：相机请求与会话切换顺序

- 先加入相机规格选择边界并运行两个回归，确认开始扫描沿用预览规格、中断重启使用后来的设置，两项均失败，退出码 65。
- 新增 ScanCameraRequest 纯值，将计划中的分辨率/帧率请求传入 ARKit 视频规格选择器；预览读取注入的 settings，活动扫描和恢复使用对应计划。实际格式仍从设备支持列表选择，保留原有 FPS 上限筛选和优先级，无法匹配时沿用 ARKit 默认格式；请求不伪装成设备实际规格。
- 新计划开始前同步关闭旧证据门，再更新计划、检测/渲染配置。需要改变相机请求时重新运行会话并等待 normal tracking；请求相同则保留健康追踪，暂停后的同扫描恢复不重新运行 ARSession。
- 中断重启显式传入新计划请求，在失败旧扫描仍持有状态且证据门关闭时运行 ARSession，成功后才启动新扫描；新扫描识别已配置请求，避免第二次 run。没有绑定或不支持 AR 的情况继续拒绝采集。
- 删除延迟绑定初始化中 `loadSettings()` 之后额外读取全局 renderer 设置的调用。新增等待延迟回调的回归，确认它不能覆盖活动计划的采样预算。
- 相机请求切换后重新发布实际帧分辨率；Renderer 仍根据每个真实帧的图像尺寸更新网格/内参相关输入。

验证中修复一处跨文件 extension 访问 private 准入方法的编译错误。之后 41 项定向通过、退出码 0；补充不支持 AR 的新计划及同规格新扫描回归后，全量 **957 项通过、0 失败/跳过，退出码 0**。Release 与下一轮一起收尾。

## 迭代 11：消除重复默认配置

- FruitScanExperimentConfig 只保留运行时使用的融合匹配、去噪、深度、遮挡和候选合并参数；删除无执行消费者的 detector/clustering 默认容器及 fusion 中重复的四个设置种子。
- FruitScanConfig 和 ClusterConfig 各自定义唯一默认数值，用户设置仍生成这两个明确的实际配置。不再允许通过实验配置修改一个不会执行的同名种子。
- 旧校准上下文需要保留历史编码键。兼容种子的重建集中在 YieldCalibrationContext 的编码路径，取值来自实际配置类型的默认值；不再混入可变运行参数。
- 新增固定历史 JSON 夹具，校验默认上下文规范化后的完整字节相等；保留自定义配置生效与校准隔离测试。

验证：72 项定向通过；全量模拟器 **958 项通过、0 失败/跳过，退出码 0**；模拟器 Release 和设备 SDK 未签名 Release 均构建成功，退出码 0。设备目标编译不表示真机采集通过。

## 迭代 12：固定观测的估算与存档回放

- 增加测试目标内的 ScanObservationReplayTests，使用 30 个合成点、两帧固定 Observation 身份/时间、32×32 合成深度/置信度图；不引入真实用户数据、训练集或 App 资源。
- 通过生产 Observation.capture 验证置信度采样，再经过真实 freeze → estimate → commit → verified record → BatchExportService JSON 导出。可靠深度、Low 置信度、confidence copy failure、image-only、cloud-only 分别验证；拒绝场景提供同位置可聚类的果实点云，检查回退不能升级为可靠产量。
- 可靠场景的期望几何与重量按固定针孔投影、既有尺寸先验、球体体积及置信度加权公式独立手算，使用固定数值断言；两帧对应同一果实，融合权重 0.81、可靠果数 1、遮挡修正后的估计果数 2 分别检查。反转观测输入后比较导出业务字段。
- 输入扫描/计划/观测/帧身份固定。Snapshot、事务所有权和输出 UUID 仍由生产代码创建，每次验证其真实绑定；跨次比较仅剔除 validatedFruits.id、fruitMassEstimates.id/createdAt，不更改生产身份或摘要规则。
- 这组回放从推理完成后的二维检测边界开始，不覆盖模型推理精度、ARKit 调度或物理 LiDAR；下一轮可在该边界补多果实竞争关联和异类干扰。

初次定向 4 项通过、1 项失败：夹具误将默认 9×9 投影网格写成 5×5，已修正。之后全量 962 项通过、1 项失败：手算期望漏计既有融合置信度权重 0.81，已补充对应推导与权重断言，生产算法未改变。修正后全量 **963 项通过、0 失败/跳过，退出码 0**；模拟器与设备 SDK 未签名 Release 均通过，退出码 0。

## 迭代 13：模型指纹的基础设施边界

- 模型定位、文件枚举和分块摘要移入 Infrastructure/Configuration/ScanModelFingerprint。Application 的模型身份准备器直接调用该边界；校准上下文保留旧入口适配，实际文件读取只在新位置实现。
- 保留路径排序、相对路径字节拼接、1 MiB 分块读取和 bundled identity 一次性缓存。固定 SHA-256 夹具覆盖目录创建顺序、根路径变化、文件内容变化、单文件及超过分块边界的内容；文件打开中途失败返回不可用。
- 自审发现旧目录枚举会吞掉读取错误并可能对可读子集生成已验证指纹。改为逐层可抛错读取，子目录读取或文件属性查询失败均返回不可用；不跟随目录符号链接。新增失败子目录、列出后消失的文件和目录符号链接回环测试。完整模型仍保持历史路径/内容摘要字节。

初次迁移定向 42 项通过。故障注入最初尝试覆盖 Foundation extension 方法，编译器拒绝覆盖，退出码 65；改用目录读取边界注入后 43 项定向通过。补充文件消失和目录链接回归后，全量 **968 项通过、0 失败/跳过，退出码 0**；模拟器与设备 SDK 未签名 Release 均通过，退出码 0。

## 迭代 14：可检查的观测值边界

- 将 FrameID、深度置信度来源、观测拒绝原因、ObservationDepthSample 和 Observation 从带 CoreVideo 依赖的共享文件移到 Domain/Observation.swift。定义和行为不变；该文件仅依赖 Foundation、CoreGraphics 和 simd 的值类型。
- ScanFusionYieldBuilder.Input 改为编译器检查的 Sendable，不再使用 unchecked 声明。输入存储点值、紧凑观测和配置快照；兼容 savedDetections 仍是计算投影，不存储旧帧缓冲。
- DetectedFruit/FramePacket 的平台缓冲适配仍保留；未将这些私有缓冲包装误标为完全由编译器证明的并发安全类型。Domain 仍有 Core 值类型依赖，完整模块分离继续推进。

全量 **968 项通过、0 失败/跳过，退出码 0**；模拟器与设备 SDK 未签名 Release 均构建成功，退出码 0。编译未报告 Input 的 Sendable 字段问题。随后显式标注新增测试的 openFile 闭包参数，以消除尾随闭包匹配警告；补充校准测试 **27 项通过、0 失败/跳过，退出码 0**。仍有既有 XCTest 最低链接版本提示，不属于本轮新增问题。

## 迭代 15：分离投影核心、ROI 候选和像素缓冲适配

- Domain/Fusion/ObservationProjection 保存稳健深度、世界/图像坐标转换和紧凑观测投影；DetectionDepthCandidateBuilder 保存 ROI 前景、连通性、形状与尺寸计算。ImageCameraCoordinateSpace 同时移入该领域目录。
- Observation.capture 和两种私有像素采样器移入 Infrastructure/Detection/ObservationCapture；CVPixelBuffer 生命周期与采样实现整体保留。旧 DetectedFruit/CVPixelBuffer 的融合和投影入口集中在 FusionValidatorLegacyInput，先转换为观测值再调用数值核心。
- 融合匹配、去重、结果合成和采样坐标映射直接调用 ObservationProjection。DepthProjectionService 不再持有不参与数值计算的 FusionValidator；原 FusionValidatorProjection 保留旧签名的薄转发，以支持已有测试和兼容入口。
- 迁移后的领域投影/ROI 文件没有 CoreVideo、ARKit、Metal、Vision、UIKit 导入，也不接受 DetectedFruit 或 CVPixelBuffer。算法函数体只改变所属类型及调用路径；没有合并两种不同的前景深度策略，没有改变拒绝阈值或固定距离回退的适用范围。
- 已逐项核对移动前的函数体与新文件，项目文件检查与差异检查通过。定向融合、去重、诊断、估产和完整存档回放 **178 项通过、0 失败/跳过，退出码 0**；全量 **968 项通过、0 失败/跳过，退出码 0**；模拟器及设备 SDK 未签名 Release 构建均成功，退出码 0。

## 迭代 16：让去重直接消费观测值

- 稳定轨迹、证据压缩、2D 去重与已有 3D 去重移入 Domain/Fusion/DetectionDeduplicator。观测入口使用明确的 `observations:` 标签，保留旧接口空数组调用的可解析性。算法只更换输入类型、参数标签和已解析观测的读取方式；规范化这些差异后，函数体与迁移前一致。
- FusionEvidencePipeline 的稳定性过滤和去重直接消费 Observation，移除两次 Observation → DetectedFruit → Observation 往返。帧身份、采样值、拒绝原因和顺序随原观测保留。
- DetectedFruit 兼容接口与旧帧窗口保留策略集中到 Infrastructure/Detection/DetectionDeduplicatorLegacyInput。兼容接口按被选中的身份返回原始检测对象，保留私有缓冲；重复出现的同一对象不触发字典唯一键错误，选择结果的顺序和数量不被字典去重。
- FruitCandidate、ValidatedFruit、ValidationSource 及计数序列化值移入 Domain/Fusion/FruitEvidence，声明、阈值、权重与编码字段原样保留。ReliableYieldEvidence 的 fileprivate 构造器继续限制在融合准入所在文件，未为移动目录而放宽可靠证据构造权限。
- 新增 3 项回归，覆盖帧身份/拒绝原因与最近窗口、有限样本的最小持续时间/异果保留、原缓冲适配对象及重复身份；原 3D 关联、无效深度和低置信度深度测试同时验证原生观测入口。

定向融合、去重、点云、诊断、估产与存档回放 **316 项通过、0 失败/跳过，退出码 0**；全量 **971 项通过、0 失败/跳过，退出码 0**；模拟器及设备 SDK 未签名 Release 均构建成功，退出码 0。两份 Release 日志没有编译警告；测试构建仍有既有 XCTest 最低链接版本及异步 RunLoop 警告。协调器的实时与归档数组仍使用旧检测对象，纯值类型还依赖 Core 中的品类/配置；本轮不宣称已经完成领域模块隔离。

## 迭代 17：协调器贯通原生观测

- ImageDetector.processObservations 与 ImageDetectorQueue.observations 在同帧推理完成后直接产出 Observation；旧 processQueue/enrich 只在兼容调用时包装检测对象。
- 协调器的活动数组、稳定证据归档、后台归档任务、HUD 融合与最终估算快照都改用 Observation。冻结合并按原归档优先顺序去重，避免先拼接两份证据数组；帧身份、采样值和拒绝原因保持原值。
- 原检测输入在非主 actor 的 async 兼容边界采样，使用当前扫描计划的深度配置；如果已经携带 Observation，保留捕获时的证据，不重新套用当前配置。旧调试与快照入口仅在返回时构造兼容门面。
- 帧保留策略移入 Domain，原生与旧接口共享按采集时间戳选取最近帧的实现，不改变同帧多个检测、原顺序与 360 帧上限。品类核对使用最小的类别/时间/置信度值，不为统计读取或复制深度缓冲。
- 新增 3 项回归覆盖归档裁剪后冻结的完整观测、旧缓冲按计划采样与已捕获观测不漂移、同帧多框的品类计数。正常结束/暂停保留证据，以及硬中断/换扫描/销毁拒绝旧结果的 6 项回归改为直接走原生观测入口；原队列配置与窗口测试同时核对新入口。

定向 **292 项通过、0 失败/跳过，退出码 0**；全量 **974 项通过、0 失败/跳过，退出码 0**；模拟器与设备 SDK 未签名 Release 均成功，退出码 0。可靠产量规则、归档修订复核、生命周期令牌与原有阈值没有改变。

复核发现下一处实际配置缺口：confirmedLiveFruitCount 仍从可变 settings 生成聚类配置、使用默认 FusionExperimentConfig，并且没有应用最终估产使用的目标品类过滤。本轮只迁移其输入类型，下一轮用独立失败回归证明配置/异类干扰影响后修复，保留实时计数更严格的最少两帧与 0.85 置信度门槛。

## 迭代 18：实时确认计数使用扫描计划

- 修复 confirmedLiveFruitCount：置信度、最少观测数、稳定时间窗、聚类配置和目标品类来自 activeFruitConfiguration；融合距离/视锥参数来自 activeScanPlan.experimentConfiguration.fusion。未建立扫描配置的兼容路径仍使用传入检测配置和设置。
- 稳定性与最近窗口先对全部对齐观测计算，再复用 ScanFusionCategoryFilter 筛选目标品类，避免其他品类进入目标实时果数，也避免筛掉新异类帧后把旧目标轨迹误当近期证据。
- 保留实时最少两帧、最低 0.85、原持续时间要求、ROI 深度准入与仅 fused 计数。实时窗口与最终全扫描计数仍有各自范围，不要求二者数值相同。
- 新增 6 项真实调用回归。修复前 5 项探针中 **4 项失败、1 项通过，退出码 65**：异类混入得到 2 而非 1；计划置信度、尺寸限制和融合距离未生效均得到 1 而非 0。设置变更用例随后改用受支持的葡萄品类并断言设置确实改变，补充新异类帧使旧目标证据过期的边界测试。
- 修复后融合、计数、生命周期和存档回放定向 **206 项通过、0 失败/跳过，退出码 0**。测试清理闭包随后改为只传递隔离域名称，消除新增的 UserDefaults 非 Sendable 捕获警告；全量 **980 项通过、0 失败/跳过，退出码 0**，模拟器与设备 SDK 未签名 Release 均成功，退出码 0。最新测试构建只有既有 XCTest 最低链接版本提示，两份 Release 日志没有编译警告。

## 迭代 19：分离运行配置与历史校准字段

- 先固定独立的历史 JSON 夹具：默认配置、高/中/低质量预设、捕获后设置变化、不同历史融合球形度不得复用校准。迁移前校准基线 **30 项通过、0 失败/跳过，退出码 0**。
- FruitScanConfig 移除无运行消费者的 sphericityThreshold，保留实际执行的 5 项配置。FruitScanConfig 与 ClusterConfig 移入 Domain/ScanConfiguration；ClusterConfig.sphericityThreshold 的实际聚类用途与默认值保留。
- SettingsStore 单独计算 legacyFusionSphericityThreshold；ScanFruitConfigurationSnapshot 在捕获配置时保存它，仅用于生成校准上下文，不再随运行配置传入检测、融合与估产。高/低预设原来的 max/min 规则保持不变。
- YieldCalibrationContext 显式接收兼容值，重建旧 fusion.sphericityThreshold；历史 experiment.fusion 的 0.5 默认种子也由校准编码负责。标量继续经过 JSONEncoder，避免直接桥接 Float 后改变小数字节。旧上下文不归一化，严格匹配范围不放宽。
- 本轮包含内部源码接口迁移：删除 21 个构造点中无效的默认 0.5 参数；需要构建历史校准上下文的调用显式提供兼容值或复用已冻结的 calibrationContext。没有计划的旧估算输入使用历史默认；非默认旧校准输入须显式传入 ScanCalibrationIdentity。
- 初次定向 **144 通过、2 失败，退出码 65**：两处旧测试只用运行配置重建上下文，遗漏已分离兼容值，导致 0.8 校准系数被拒绝并返回中性 1.0。已改为使用完整冻结上下文，同时将底层兼容参数改为必填，避免未来静默遗漏。固定 JSON 字节夹具始终通过，未调整 0.8 的预期。

补齐调用后定向 **189 项通过、0 失败/跳过，退出码 0**；全量 **983 项通过、0 失败/跳过，退出码 0**；模拟器与设备 SDK 未签名 Release 均成功，退出码 0。本轮没有修改可靠水果准入、真实聚类球形度、估产公式、持久化 schema 或既有校准文件。

## 迭代 20：多果实质量回放与候选关联精简

- 新增两项完整回放，每项分别运行正序与逆序观测：两个中心相距 11 cm、不同尺寸和置信度的苹果；以及与小苹果重叠、置信度更高的梨干扰。两条交叉候选边在默认 15 cm 门槛内，正确关联仍应保留各自中心与质量。链路覆盖 Observation 捕获、冻结、估算、仓储提交、校验读取及研究 JSON 批量导出。
- 期望值按针孔投影、9×9 网格、既有尺寸先验与球体公式独立计算：直径 6.714045208/9.071067812 cm，质量 134.7008485/332.1947685 g，置信度权重 0.855/0.81，可见产量 0.384246988 kg，K=2.999，最终产量 1.152356717 kg。逐果质量同时检查自己的置信度，避免仅比较总质量而漏过交换关联。
- 新增两项质量关联边界：显式来源不存在或品类不兼容时不借用附近候选；相同候选 ID 只消费一次，显式关联先于旧空间入口，重复候选/重复来源 ID 不放大质量，显式来源耗尽后保留品类均值回退。原有融合准入和 fallback 质量评级不变。
- 初次基线 **48 通过、2 失败，退出码 65**，失败均为新测试的存档格式假设：过滤数量在 recognitionDiagnostics；JSONSerialization 与 JSONEncoder 的 Float 小数字符表示不同。已按实际 schema 读取并用原值类型解码后比较，保留存档与批量导出原始行的逐字节相等断言；全部果数/尺寸/质量期望未变。修正后重构前基线 **52 项通过、0 失败/跳过，退出码 0**。
- ScanYieldEstimateHelpers 用单次遍历选择最近可用候选，移除每果实的候选数组、距离元组数组和第二轮筛选数组。保留原候选顺序、等距 UUID 决胜、显式源成员限制、单次消费、品类过滤、严格小于 10 cm 的旧空间回退，以及所有质量公式。时间复杂度仍为果实数×候选数，没有宣称吞吐或真机内存提升。

重构后定向 **345 项通过、0 失败/跳过，退出码 0**；全量模拟器 **987 项通过、0 失败/跳过，退出码 0**；模拟器和设备 SDK 未签名 Release 均成功，退出码 0。最后三份增量验证日志没有编译警告，定向构建仍见既有 XCTest 最低链接版本提示。本轮四项新增测试均为合成证据；真实多果实遮挡、点云/ROI 混合几何质量与强制重分配路径的完整回放仍需补充。

## 迭代 21：候选合并使用轨迹几何值

- 新建 CandidateCombinerTests，增加 6 项合并契约回归：空/单候选身份、点数与球形度加权的中心/直径/颜色/深度支持、最近可合并轨迹、等距保留先生成轨迹、独立点云取得类别后隔离异类、采样上限与原顺序前缀。迁移前基线 **52 项通过、0 失败/跳过，退出码 0**。
- CandidateCombiner 从 Core/ScanFusionPipelines 移入 Domain/Fusion。Core 保留点云、ROI、融合编排和 ReliableYieldEvidence 的 fileprivate 准入构造；现有外部接口不变，Xcode App 和 XCTest 仍使用原目标。
- 合并判定直接读取 CandidateTrack 的类别、加权中心与加权直径，保留原 safeWeight 归一化，不再为每次比较创建 FruitCandidate 和 UUID。匹配轨迹用单次遍历记录最近值，去掉临时索引数组，严格小于比较保持等距时原轨迹顺序。最终才为输出轨迹构造候选；空/单候选继续原值返回。
- 逐段核对确认公开入口、CandidateTrack 累积/输出实现均与迁移前一致；Core 管线部分除移走算法和删除不再使用的 simd 导入外字节一致。阈值、类别、点数权重、点集前缀、独立点云标记、ROI 深度支持以及可靠产量准入没有改动。

迁移后定向 **351 项通过、0 失败/跳过，退出码 0**；全量模拟器 **993 项通过、0 失败/跳过，退出码 0**，模拟器和设备 SDK 未签名 Release 均成功，退出码 0。定向重新编译显示未修改的 DashboardSummaryTests 中 3 处 RunLoop.run 异步调用的 Swift 6 模式警告，以及既有 XCTest 最低链接版本提示；本项目仍使用 Swift 5，最后三份增量验证日志没有警告。此次迁移属于领域职责收敛，不代表已经建立独立 Swift 模块，也未测量设备性能增益。

## 迭代 22：融合评分与决策只依赖值输入

- 先新增 3 项原生观测调用回归，固定拒绝距离配置捕获、拒绝候选的检测框扩展、拒绝证据不跨品类或独立点云来源传播。迁移前基线 **85 项通过、0 失败/跳过，退出码 0**。
- CandidateMatcher 移入 Domain/Fusion/FusionCandidateMatcher，只保存 FruitScanConfig 和 FusionExperimentConfig，不再反向持有 FusionValidator。原验证器扩展的匹配评分、视锥支持计算与拒绝候选检查归入同一个值服务；原生验证流程直接使用该服务，旧缓冲适配和 validate 入口不变。
- FusionValidationPolicy 汇集投影上下文/结果、投影服务、决策值与置信度策略。删除 decide 中未消费的 detection 参数；fusedConfidence 继续读取原观测和候选。相关值和无状态服务使用 checked Sendable，不引入像素缓冲或 unchecked 标记。
- FusionAssignment 单独移入 Domain/Fusion，最大匹配/最小代价实现已与原文逐字节核对一致。保留候选 ID 去重、匹配优先级、深度拒绝与诊断回退、置信度公式和默认阈值。
- 删除原 Core/FusionValidatorMatching、FusionValidatorServices 两个文件并更新 App 编译引用。两处直接检查匹配评分的测试改为调用 CandidateMatcher，使用相同配置与原断言；未增加只为测试保留的门面转发。ReliableYieldEvidence 的受限构造仍在原融合准入文件。

迁移后融合、去重、产量、实时果数及导出定向 **360 项通过、0 失败/跳过，退出码 0**；全量模拟器 **996 项通过、0 失败/跳过，退出码 0**；模拟器和设备 SDK 未签名 Release 均成功，退出码 0。当前仍是一个 App target 内的职责分离，领域品类、颜色与部分配置尚未完成归属收敛，不能据此宣称独立模块已经成立。

## 迭代 23：混合几何与必须重分配的完整回放

- ScanObservationReplayTests 新增混合点云/ROI 场景，沿实际捕获—冻结—估算—仓储提交—校验读取—批量 JSON 导出执行，并比较观测正序与逆序的规范化输出。30 个轴向点与两帧 9×9 可靠 ROI 合并后，192 点继续使用实测三维椭球路径；不能退回纯 ROI 平面直径或默认球体质量。
- 独立固定期望来自点位、分位跨度和原公式：x/y 跨度 4.266666667 cm，z 退回原始范围 6 cm，椭球体积 57.190948929 cm³，苹果密度 0.85 得 48.61230659 g；可见质量 0.043751076 kg，遮挡修正后 0.131231352 kg、果数 3。保留 ellipsoid 和 usingEllipsoidBaseline 诊断。
- 第二项回放使用 60 个点形成 x=0 和 x=0.16 m 两个独立点云候选。观测位置 x=0.04 m 可连两者且左候选分数更低，x=-0.06 m 只能连左候选；必须把第一项重新分配给右候选才能保留两枚果实。正序与逆序均固定左侧置信度 0.85、右侧 0.9、2 fused、0 ROI 候选及空零产量原因。
- 每候选球拟合后仍按原苹果直径先验取 6 cm，每枚质量固定 96.1327352 g，可见质量固定 0.168232287 kg。该场景的最终遮挡修正结果只验证真实输出的存档/读取一致性，未把它宣称为独立准确率基准；匹配关系和可见质量使用独立期望。
- 两项回放核对源 PLY 摘要、质量行与融合果实身份及批量导出来源计数。这些是合成证据，不能替代物理 LiDAR 精度。未改生产算法、阈值或存档 schema。

混合几何定向 **59 项通过**。首次重分配定向 **253 项通过** 后，夹具进一步收紧为上述“第一项左边分数最低”的场景；最终夹具由全量模拟器 **998 项通过、0 失败/跳过、退出码 0** 验证。本轮只改测试，不重跑生产 Release；沿用第 22 轮的两项 Release 成功记录并明确其历史性质。

## 迭代 24：品类规则分层与融合子集独立编译

- 先单独编译原数值融合源集。编译器报告 FruitModels 中 4 处找不到 DetectedFruit，退出码 1；这是隔离依赖探针，原 App 构建未失败。品类先验和展示/旧检测入口仍混在同一文件，不能把移入 Domain 目录当成独立性证明。
- 拆出 Domain/FruitCategory 和 FruitCategoryVerification，分别保存品类编码/物理先验及扫描品类策略/原生 Observation 核对。displayName 移至 Core/FruitCategoryPresentation；原 26 个中文名称不变。旧 DetectedFruit 重载保留在 Infrastructure/Detection/FruitCategoryVerificationLegacyInput，只复制品类、时间和置信度，不读取或采样深度缓冲。
- FruitCategoryObservation 改为 checked Sendable 值；标量构造及品类证据入口在模块内供适配层使用。未扩大 ReliableYieldEvidence 的受限构造。支持品类列表、逐帧最大置信度、最少 3 帧/平均 0.75、竞争排序与不匹配策略保留原实现。
- FruitColorModels 和 FruitScanExperimentConfig 按原文迁入 Domain。迁移前后逐字节核对颜色/实验配置、品类物理先验、展示名称及证据排名实现一致；未改变默认阈值、字段或校准 JSON。删除旧 Core/FruitModels 文件，更新 App 源引用，仍使用原 App/XCTest target。
- 增加 tools/validate_fusion_domain.sh 和工具说明。16 个源文件仅来自品类、颜色、实验/运行配置、观测/保留策略及 Domain/Fusion，实际生成独立 Swift 模块，使用 iOS 16 模拟器 SDK、Swift 5；不包含 App/Core、展示名称、DetectedFruit 或像素缓冲源文件，临时产物自动清理。独立编译退出码 0。
- 这个门禁只证明数值融合子集的源依赖；ScanPlan、ScanSession、ScanEvidenceIdentity 尚未纳入，生产应用也未改为框架或包。没有声称整个 Domain、生命周期并发或设备精度已经验收。

迁移后定向 **346 项通过**；全量模拟器 **998 项通过、0 失败/跳过**；模拟器和设备 SDK 未签名 Release 均成功，所有退出码为 0。工程结构、脚本语法与差异检查通过。定向构建重编译时仍报告未修改的 DashboardSummaryTests 中 3 处异步 RunLoop 的 Swift 6 未来限制，以及 XCTest 最低系统版本链接警告；本轮不混入这些测试的修改。完整结果及两项 Release 没有新增警告记录。

## 迭代 25：扫描计划值与设置捕获分离

- 将 ScanPlan/ScanSession 纳入隔离编译探针，先确认 5 类外部值的 8 处缺失引用：Season、RendererScanSettings、FruitVarietyParams、YieldCalibrationCorrection、YieldAlgorithmRevision。探针退出码 1；这是数值/计划边界检查，不是 App 编译失败。
- 迁移前新增 2 项渲染设置捕获回归：三个质量预设、粒子容量与设置上限、深度置信度底线、邻居数及体素边界，且设置和实验值在捕获后变化不能改变已绑定值。另用固定 JSON schema 夹具检查品类参数 ID、定制标记和校准字段的编解码。
- 首次基线 52 项通过、1 个新增参数夹具失败，原因是预期值经 JSONSerialization 重编码使浮点文本膨胀。改为固定原编码格式字节，未改产品编码或数值期望；迁移前重试 53 项通过、0 失败/跳过，退出码 0。首次失败日志还记录模拟器诊断收集的 simctl 查找失败，实际测试已经执行；重试和后续全量均成功，不据此改变全局 Xcode 选择。
- Domain/RendererScanSettings 只保留不可变值与可靠置信度下限；原 init(store:particleCapacity:depthConfiguration:) 入口保留在 Application/RendererScanSettingsCapture。应用层读取设置并按原公式构造值，未引入额外读取、主线程重采样或改变渲染阈值。原体素公式按字节核对一致。
- FruitVarietyParams 迁入 Domain，字段、Codable、ID 创建和品类先验不变；displayName 移至现有 Core/FruitCategoryPresentation 扩展。FruitParametersStore 的完整存储主体按字节核对未变，保留快速连续保存、旧代次拒绝和损坏数据保护。
- Season 迁入 Domain/ScanConfiguration；校准修正值与算法修订常量迁入 Domain/ScanCalibration。校准消费者、修正值、修订字符串、ScanPlan、ScanSession 均按字节核对未变；结果/诊断模型主体也未变，仅移走 Season 并处理文件末尾空行。App/XCTest target、调用接口与校准上下文字节保持。
- tools/validate_fusion_domain.sh 扩大为 21 个数值、计划和生命周期源文件，独立生成 iOS 16/Swift 5 模块成功，退出码 0；不包含设置存储、应用捕获、展示或旧缓冲源。ScanSession 独立编译仅证明源依赖，生命周期/迟到证据行为由定向及全量回归另外验证。
- 对当前整个 Domain 的 22 个源文件另做下一轮探针，仍因 ScanEvidenceIdentity 中 ScanEstimate 的 YieldResult 依赖退出码 1。结果值和质量模型尚未完成归属收敛，不能宣称整个 Domain 已独立。

迁移后计划、生命周期、校准、参数存储、点云、冻结流程及回放定向 **264 项通过**；全量模拟器 **1001 项通过、0 失败/跳过**；模拟器和设备 SDK 未签名 Release 均成功，所有退出码为 0。工程结构、脚本语法与差异检查通过。定向重编译仍有前述未修改的 DashboardSummaryTests/异步 RunLoop 和 XCTest 版本警告；全量及两项 Release 没有新增警告记录。未修改融合算法、存档 schema、可靠证据构造权限或物理验收状态。

## 迭代 26：结果与质量值归属收敛，整个 Domain 独立编译

- 对迁移前整个 Domain 的 22 个源文件执行隔离编译，复现 ScanEstimate 找不到 YieldResult，退出码 1；原 App 编译未失败。冻结身份只有在结果值一并收敛后才能真正摆脱 Core 源依赖。
- 全仓消费者搜索确认 shortStatus 只有声明，FruitInfo 仅由 LegacyYieldEstimator 测试支持使用。删除无消费者的内部展示辅助属性，将 FruitInfo 按原文移入现有测试支持文件；生产目标不再包含这项旧研究中间值。实际诊断文案和展示消费者未改。
- YieldResult、ScanYieldDiagnostics 移入 Domain/YieldEstimateModels，结果/诊断声明、字段与默认值按迁移前删除上述两项后的原文字节核对一致。FruitMassEstimate 及形状/警告枚举按原文移入 Domain，Codable、质量字段和时间/ID 均不变。
- ScanEvidenceIdentity、ScanEstimate 和可靠证据构造权限保持；未修改融合、质量、遮挡、校准公式或元数据编码。工程源引用只调整文件所属组，保留 App/XCTest target、iOS 16 与 Swift 5。
- 独立编译脚本改为递归发现整个 Domain 的 Swift 源，包括隐藏及忽略路径中的源文件，取消手工子集清单。当前 24 个文件与独立文件系统清点一致，实际生成 iOS 16/Swift 5 模块成功，退出码 0。没有加入 App/Core、设置存储、检测缓冲或展示源来补齐编译。
- 当前编译门禁证明整个领域源树的依赖闭合；生产仍在原 App target 中，尚未建立跨生产模块的公开 API。并发、证据准入、存档兼容和物理质量各自仍需行为证据。

结果/几何、导出、融合、诊断、冻结及回放定向 **395 项通过**；全量模拟器 **1001 项通过、0 失败/跳过**；模拟器和设备 SDK 未签名 Release 均成功，所有退出码为 0。迁移内容、工程结构、脚本语法与差异检查通过。本轮未新增镜像实现的数值测试，继续使用已有固定质量/匹配/诊断/存档回放和兼容夹具。真实设备性能与估产误差未验证。

## 迭代 27：持续构建接入与工具失败传播

- 检查现有 iOS Build 工作流，确认原先仅对 main 推送和手动运行执行模拟器编译，未运行领域依赖门禁。本轮增加面向 main 的 pull request 触发，两个路径过滤同时纳入 Domain 门禁与构建工具；在模拟器编译前运行完整 Domain 检查。工作流保留 macos-15 runner 和只读仓库权限。
- CI 通过 job 环境使用 runner 当前选择的 Xcode；所有脚本步骤显式使用 Bash，未修改机器的全局 Xcode 选择。Xcode 选择结果先独立赋值，再写入环境，避免命令替换失败被 printf/export 的成功状态覆盖。实际失败夹具原先返回 0 且继续构建，修正后工作流步骤与本地 helper 均返回原退出码 72，未写入空环境或继续构建。
- 原完整 Domain 脚本在缺少 rg 的系统 PATH 下复现退出码 1。本轮保留 rg 优先发现，同时增加系统 find 的 NUL 分隔递归发现；两条路径实际独立编译 24 个源文件均成功。外部隔离副本中加入隐藏、被忽略目录下的 DetectedFruit 反向依赖，两条路径均发现并以退出码 1 拒绝；未修改真实 Domain 源。
- 将 CI 模拟器编译提取为 tools/ci_simulator_build.sh，构建日志与 DerivedData 放在 runner/系统临时目录，支持显式外部输出路径。保留实际编译退出码，摘要限制最多 30 行错误和 10 行警告；删除不参与后续步骤的模拟器列表和 App 路径发现。没有修改 App、XCTest 或工程源引用。
- 在本机 Bash 3.2 下，初版否定分组重定向未捕获摘要路径为目录的写入失败：编译成功时错误返回 0。改为正向分组判断并串联摘要命令，修正后编译成功/摘要失败返回 1，编译失败/摘要失败仍返回原编译退出码 65。6 个工具替身场景验证成功、编译失败、工具不可用、两种报告失败及 runner Xcode；这些是脚本故障验证，不是 XCTest 或实际编译。
- 最终脚本另核对显式 Xcode、runner Xcode 和工作流选择成功路径；实测指定本地 Xcode 的通用 iOS 模拟器 Debug 未签名构建成功，退出码 0。工作流结构、脚本语法和差异检查通过。本轮只有工具/工作流/文档改动，未重复运行应用 XCTest；最新应用全量证据仍为第 26 轮的 1001 项和两项 Release。

持续构建的配置和本地失败传播已完成。本轮验证时尚未提交、推送或触发远程 GitHub Actions，不能声称 runner 上通过；后续本地提交见下方检查点。模拟器编译不证明 XCTest、签名 IPA 或物理 LiDAR 质量。领域值、融合可靠来源、诊断、默认阈值及旧存档编码保持。

## 迭代 28：完整档案消费者走查与工作台状态修复

以下第 28–30 轮的“未提交、未推送”表示各轮结束时的状态；用户随后授权的提交见下方“后续修复提交检查点”。

隔离模拟器 `FruitTreeScanner-ArchitectureUI-20261001` 中使用两条 schema 3 完整档案、一条缺失结果档案及一条损坏 JSON 档案。源 PLY 和元数据摘要均按当前协议生成，校准上下文明确标为 `synthetic-ui-only-20261001`；这些数据不证明真实采集质量或估产精度。

- 历史页正确显示完整、待恢复、结果损坏状态；工作台每日汇总只计入两条完整档案。
- 实际工作台的最近扫描卡片却给缺失结果档案显示成功勾选、0 个果实及 0.0 kg。根因是卡片直接消费 `ScanFileRecord` 的兼容数值，忽略 `persistenceState`。新增回归使用 `UIHostingController` 读取实际 SwiftUI 辅助阅读内容，修改前退出 65，确认缺失结果被呈现为零产量。
- 最近扫描卡片改为消费已有 `ScanHistoryRecordPresentation` 的可选数值；状态标题和图标集中于该展示模型，历史页复用相同规则。完整零产量仍显示 0；未完成及损坏结果隐藏数值。外层按钮显式携带状态值，修复按钮标签覆盖读屏内容的问题，点云查看入口保持。
- 四项新增回归覆盖缺失结果、损坏记录的紧凑卡片、有效零产量及外层按钮。第一次补充测试存在缺失参数的编译错误，修正后另发现按钮状态缺失，均已修复。最终 `ui full` 实际执行 **1005 项通过、0 失败/跳过/预期失败，退出 0**，59 个 XCTest 类均执行；完整 Domain 编译和 unsigned Release 模拟器构建退出 0。开始/结束工作区摘要一致。
- 校准 UI 从 A 档案导入并保存 6 个、0.42 kg 的未校准基线；保存 JSON 的算法版本、合成上下文、品类和日期已核对。批量导出深链接入口实际选择两条完整记录，排除另两条；CSV 为 7 + 11 = 18 个、汇总 3.93 kg，分享面板取消后文件可继续使用。
- 收起导出结果后，临时 CSV 仍在会话目录内，暴露下一轮清理边界缺陷：`BatchExportView.clearExportedFile` 的旧根目录检查与服务的会话目录不一致。保留失败现场，下一轮先建立生产 UI action 回归，再让服务统一判断所有权。

本轮证据位于 `/private/tmp/fruit-iteration28/`，最终自动门禁报告为 `fruit-code-improvement-y4dguri6/report.json`。初始夹具和历史截图仍在仓库外的原验收日志目录。独立复审未发现估产、存档格式、导航或参数变化；保留既有工作流 dirty work。Mac 解锁后已安装最新验证版本，`recent-state-after.png` 确认未完整记录显示“待恢复／果数与产量不可用”，两条完整记录数值保持。删除确认说明已显示，取消后 9 个夹具文件摘要未变；实际永久删除待用户确认。卡片状态修复本身无阻塞发现，结论为 **mergeable**；完整 UI 与物理 LiDAR 验收仍待补，整体为 **needs changes**。本轮未提交、未推送。

### 第二十九轮：导出文件所有权统一由服务检查

- 真实 UI 收起完成面板后，CSV 仍留在 `tmp/FruitTreeScannerBatchExports/<session>/`。根因是 `BatchExportView.clearExportedFile` 的旧检查要求父目录等于临时根目录，而服务已经使用会话子目录；生产 action 回归在原实现失败，其他所有者文件保护回归通过，退出 65。
- 删除 UI 的两行过时检查，调用现有 `BatchExportService.removeTemporaryExport`。服务只接受当前会话目录中的文件，拒绝其他会话与无关临时文件；未修改清理策略、分享取消、导出生成检查或存档文件。
- `storage ui full` 在最后一次源码修改后实际执行 **1007 项通过、0 失败/跳过/预期失败，退出 0**，59 个测试类均执行；两个关键回归通过。Domain 24 源独立编译及 unsigned Release 模拟器构建退出 0；验证开始/结束摘要一致。6 个原有工作流文件摘要保持。
- 隔离模拟器安装这份 Debug 构建后，实际 UI 生成 CSV、研究 JSON、Excel XML；逐个读取产物，与固定夹具核对两条完整记录、18 个果实及格式对应的产量/诊断/身份，排除未完整和损坏记录。分享取消保留产物；CSV 收起、JSON 格式切换、Excel 页面关闭分别清理对应文件。9 个源与伴随夹具文件摘要未变。

证据在 `/private/tmp/fruit-iteration29/`：失败回归 `cleanup-before.xcresult`，最终报告 `fruit-code-improvement-jp19bunp/report.json`，人工证据 `ui-cleanup-after.json`、`ui-formats-validation.json`、`cleanup-after.png` 及三种导出副本。独立复审未发现阻塞项，结论 **mergeable**；整体设备验收仍未完成。本轮未提交、未推送。下一轮候选来自真实页面：固定深色背景上的批量导出标题和未选分组文字继承浅色系统样式，呈现黑色文字，需核对颜色环境与平台控件的实际渲染。

### 第三十轮：在实际呈现边界声明深色外观

- UI 走查确认批量导出标题与未选分组文字为黑色，背景为固定深色。调用链为 Dashboard 的 SwiftUI sheet → `BatchExportView` → 标题及系统分组控件；原代码只声明导航栏为深色，内容继承系统方案。此前渲染测试主动注入深色，遗漏浅色系统入口。
- 新增回归在前台场景的浅色窗口中，通过 SwiftUI sheet 呈现实际生产页面，检查四个分组、默认选择及系统控件外观并保存渲染附件。最初夹具使用无前台场景窗口，随后改为 UIKit 直接呈现；这些条件与实际路由不一致，保留失败日志并修正夹具。最终真实 sheet 基线仍为浅色控件，1 项失败、退出 65；增加页面级 `.preferredColorScheme(.dark)` 后同一回归通过、退出 0。沿用其他固定深色页面的本地模式，未修改系统设置或全局 `UIAppearance`。
- 最后一次源码修改后的 `ui full` 为 **1008 项通过、0 失败/跳过/预期失败，退出 0**；59 个测试类均执行，关键颜色回归与第 28/29 轮回归均通过。Domain 编译、unsigned Release 模拟器构建成功，开始/结束工作区摘要一致。
- 实际模拟器页面确认标题与所有分组文字清晰显示，分享页采用深色外观且可正常取消、关闭。CSV 与第 29 轮产物逐字节一致；取消保留文件，关闭页面删除临时文件。9 个源与伴随文件摘要保持，已保存校准记录的所有字段与此前副本相同；此前副本为格式化 JSON，不能将空白差异报告为数据变化。

证据在 `/private/tmp/fruit-iteration30/`：`appearance-sheet-before.xcresult`、`appearance-sheet-after.xcresult`、`appearance-after.png`、`ui-appearance-validation.json`；最终报告 `fruit-code-improvement-1xa5prr5/report.json`。独立复审未发现阻塞项，结论 **mergeable**。本轮未提交、未推送；原有工作流文件与前两轮修复保留。下一步补齐已准备的合成完整记录永久删除验收：确认/取消已核对，实际删除等待用户在操作时确认。完整物理采集、结束/重试、资源与人工果数证据仍缺操作者，整体为 **needs changes**，目标继续 active。

### 2026-10-01 远程合并核对

此前 125 项架构改动已按用户要求分为 `be3de463`、`ec782e82`、`fe19a165` 三个提交，推送至 `codex/scan-architecture-refactor`。PR #10 已合并，远端 main 为 `3b4c65a9`，其代码树与此前验证分支相同。GitHub Actions run `36801712785` 成功，日志确认 Domain 24 源独立编译和通用模拟器编译成功；合并前本地全量 1001 项通过。该远程证据不覆盖本轮未提交的 UI 修复。

后续第 28–30 轮已按用户第二次要求推送并合并 [PR #11](https://github.com/Hkai29/FruitTreeScanner/pull/11)，合并提交为 `b60363c5`。run `36827532091` 成功，日志确认 Xcode 16.4 下 Domain 24 源独立编译及通用模拟器编译退出 0；合并代码树与已核对的 `d3a5b8e1` 完全一致。该证据不覆盖下面第 31 轮新改动。

### 2026-10-01 后续修复提交检查点

用户再次要求推送并合并后，第 28–30 轮按根因分别提交：

- `f9eb6aa6`：最近记录展示档案完整性，包含四项实际渲染/读屏回归。
- `d9f91c8d`：临时导出清理由服务统一检查所有权，包含管理文件删除及无关文件保护回归。
- `d6e81362`：批量导出在实际呈现边界声明深色外观，包含浅色系统 sheet 回归。

六个源码/测试文件的 SHA-256 与第三十轮最终全量报告逐项一致，1008 项测试、Domain 编译及 Release 模拟器构建证据适用于这些提交。提交前重新执行 preflight 和差异检查，并核对远端 main 与 PR #10 合并树一致。推送后的远程 CI 与合并状态需另行在 GitHub 核对；本地测试不替代远程结果。

既有 `AGENTS.md`、两个 README、工作流文档、runner 及 runner 测试共六个改动继续保留在本地，不纳入本次提交。永久删除人工验收及物理 LiDAR 验收仍待补齐；本次三个修复无阻塞项，结论 **mergeable**，整体重构验收仍为 **needs changes**。

## 第三十一轮：仓储查询与历史刷新由根依赖统一装配

按蓝图重新核对真实调用链，发现 `AppDependencies` 已为扫描保存注入 `ScanRepository`，但历史读取仍固定使用默认目录，生产结束操作的刷新仍默认落到 `ScanHistoryStore.shared`。这是尚未贯通的依赖边界，不将默认目录上的现有用户流程描述为已复现故障。本轮采用依赖重构基线：修改前 `full` 实际 **1008 项通过、0 失败/跳过/预期失败，Domain / Release 退出 0**。

- 目录枚举及读取错误处理迁入 `ScanRepository.loadHistoryRecords`，查询遵循同一仓储的目录配置。保留按条消费、隐藏/子目录过滤、autoreleasepool、取消检查及日期排序；缺失目录返回空记录且不创建目录，读取失败仍为失败。
- `ScanHistoryStore` 通过同一仓储加载和删除；后台工作、generation、失败保留上次快照、残留文件与通知规则保持。原静态查询/删除入口继续作为兼容转发，不新增另一套副作用实现。
- `AppDependencies` 拥有对应历史实例及生产结束操作的装配方法。`ScanView` 使用该方法，保存后的刷新落到同一实例；App 根入口、工作台、历史 sheet、历史删除控制器及批量列表接入该实例。
- 六项集成/边界验证覆盖实际配置目录、只读查询、读取失败、删除后重载与其他根保护、实际结束保存后的自动刷新，以及从工作台路由到真实历史/批量 sheet。硬件边界只替换成单点合成采集，冻结、估算、事务提交和刷新均使用生产操作。
- 首次定向为 5 通过 / 1 失败：历史行按产品原有规则显示文件名，夹具错误期待树 ID；修正为每条路由对应的唯一身份，并等待真实转场结束后释放窗口。另修正新增默认参数引用 MainActor 实例的编译警告。重跑六项全部通过、退出 0；失败包保留。独立查看两张附件，历史显示完整记录及 2 个 / 0.4 kg，批量页选择同一记录。数据仅用于 UI 兼容验证。
- 最后一次源码修改后的 `storage lifecycle ui full` 为 **1014 项通过、0 失败/跳过/预期失败，退出 0**，59 个 XCTest 类均执行；结果树逐项确认六个新方法通过。Domain 24 源独立编译及 unsigned Release 模拟器构建成功；开始/结束快照一致。日志仍有其他旧 UI 夹具的转场警告，与修改前基线相同；本轮新增工作台夹具没有该警告，不把日志警告与 xcresult 的空 `runtimeWarnings` 混为一谈。
- 隔离模拟器安装本轮 Debug 构建，9 个档案文件及校准记录共 10 个摘要保持；工作台实际显示 4 条记录、2 次完整扫描、约 3.9 kg。Device Hub 的原生坐标点击在刷新句柄、Raise 及切回主窗口后仍返回 `noWindowsAvailable`，未完成这一轮原生点击走查；不把 XCTest 导航与渲染证据冒充原生点击验收，也未执行待确认的永久删除。

证据在 `/private/tmp/fruit-iteration31/`：基线报告 `fruit-code-improvement-kc5x7vvs/report.json`，定向 `targeted.xcresult` / `targeted-repaired.xcresult`，最终报告 `fruit-code-improvement-kk75926j/report.json`，渲染附件 `attachments/`，安装保护 `ui-install-preservation.json`。独立 diff 复审未发现读取、取消、事务、导航及估产边界的阻塞变化，六个原有工作流文件摘要保持。代码与受测导航范围结论 **mergeable**；原生点击、永久删除和物理 LiDAR 验收未完成，整体 **needs changes**。实现完成时尚未提交、未推送。

### 2026-10-01 第三十一轮提交检查点

用户随后要求推送并合并，源码和测试已提交为 `0c3ec81c`（`refactor(history): bind archive queries and refresh to root dependencies`），架构记录提交为 `6ff3dda2`。提交前重新运行 preflight，并逐项核对暂存的 11 个文件与上述 1014 项通过的最终源码摘要一致；最终验证开始/结束快照一致，不以此前 1008 项基线代替本轮证据。六个原有工作流改动继续留在本地。

上述两个提交已通过 [PR #12](https://github.com/Hkai29/FruitTreeScanner/pull/12) 推送，远程 [CI 36833185872](https://github.com/Hkai29/FruitTreeScanner/actions/runs/36833185872) 成功，日志确认 Xcode 16.4 的 Domain 独立编译及模拟器编译退出 0；远程 CI 没有执行 XCTest 或签名 IPA。匹配 PR head 后于 2026-10-02 02:31:51 UTC 合并，合并提交为 `f440f587bcf20c24ad38e89d237d5e0cc3ba6e7a`，GitHub 与远端 main 均已核对；合并树与受测提交树相同。发布证据在 `/private/tmp/fruit-push-merge-iteration31-20261001/merge-result.json`。合并不代表永久删除或物理 LiDAR 验收已完成。

## 第三十二轮：导入与历史刷新遵循同一根仓储

根因已复现：`ScanRepository.importPointCloud` 忽略自己的目录配置，`ImportFileView` 固定调用共享仓储并刷新共享历史，工作台导入路由也未装配根依赖。新增唯一 UUID 文件回归在修复前实际失败（1 个测试失败，退出 65）：文件写到默认档案，配置目录没有记录。回归只清理它拥有且字节匹配的 UUID 文件，不触碰其他档案。

- 仓储向原 `PLYImportService` 传递目录配置；服务的安全作用域、1 MiB 分块复制、有界解析、独占 rename、冲突重试、共享每路径事务锁和取消清理均保持。
- 新增 `ScanImportOperations`，将阻塞导入与 MainActor 历史刷新配对，由 `AppDependencies` 装配并经工作台真实导入路由传入页面。页面仍在可取消后台任务导入，通过已有取消与视图活跃守卫后更新成功状态并刷新对应历史。默认 `ImportFileView()` 兼容入口保留，生产路由显式注入。
- 三项新增测试覆盖配置目录及源字节保护、真实根装配后的后台导入和历史刷新，以及提前取消不发布文件。原始 PLY 导入保持 incomplete，不生成可靠果数、产量或 companion。
- 首次修复构建暴露跨文件扩展无法访问 private 环境对象，改为工作台只读装配属性，未放宽原属性可见性；重跑三个方法全部通过、退出 0。随后尝试扩展深链接测试时发现 `AppNavigation` 没有 importFile 枚举；撤回这一项错误夹具扩展并恢复该测试文件原样，真实导入入口通过原生点击走查，没有为测试新增产品深链接。失败日志均保留。
- 最后一次源码修改后执行 `storage ui full`：**1017 项通过，0 失败/跳过/预期失败，59 个类，退出 0**；结果树逐项确认三个新方法 Passed。Domain 24 源独立编译及 unsigned Release 模拟器构建成功，全部步骤退出 0，开始/结束快照一致；复审时所有源码/测试摘要仍与该报告一致。此后仅补本文档。
- 隔离 iOS 模拟器安装该受测 Debug App 后，原生坐标点击恢复可用。实际走通工作台导入 → 系统文件选择 → 取消 → 空闲 → 关闭，以及分享合成 A 点云并保存到“我的 iPhone” → 选择该 PLY → 导入成功 → 关闭 → 工作台记录数 4→5 → 历史新增 incomplete 记录。同名导入生成新文件，不覆盖原档案；两条原完整记录仍显示 7 个 / 1.2 kg 与 11 个 / 2.7 kg，原损坏结果警告仍在。夹具日期为前一天，当日指标为 0，不将其当成当日可靠产量。
- 走查后核对原 9 个档案文件和校准记录共 10 个 SHA-256 均保持；唯一新增文件与合成 A 源的原始字节一致，没有附加 result/manifest。原记录及新增合成导入均保留，未执行待确认的永久删除。

证据：`/private/tmp/fruit-iteration32/` 的 `before.xcresult`、`after-repaired.xcresult`，最终 `fruit-code-improvement-d402qz6f/report.json` / `test-tree.log`，`ui-install-preservation.json`、`ui-validation.json` 和 `final-review.json`。单独复审目录传递、实际路由、线程隔离、取消/错误分支、App target 引用和关键结果树，无阻塞发现。六个原有工作流文件摘要保持；融合准入、诊断、校准公式、schema 1–3、原始摘要及事务规则均未修改。本轮结论 **mergeable**；实现与文档尚未提交、未推送。其他消费者的根装配、永久删除人工验收及物理 LiDAR 验收仍未完成，整体目标保持 **needs changes**。

## 第三十三轮：校准最近记录与原始基线使用同一根来源

真实调用链仍是工作台默认校准页 → 默认新增记录页，最近记录和基线读取固定调用全局实例。本轮属于依赖重构，不把默认目录上的正常用户流程描述为已复现数据故障。改动前先执行 complete 准入、仓储原始基线/未知来源拒绝、校准记录独立存储三个既有方法，**3 通过，退出 0**。

- 新增 `CalibrationScanSource`，由 `AppDependencies` 配对根历史与仓储基线读取，工作台真实校准路由及新增记录 sheet 传递同一来源；默认 `CalibrationView()`、注入记录控制器及 `AddCalibrationRecordView(onSave:)` 的调用形式兼容。
- 删除视图内重复的 `ImportedCalibrationMetadata` 包装，直接消费仓储原有 `CalibrationScanBaseline`。基线仍在 detached utility 读取，MainActor 应用，读取失败保持原有 nil 语义；重新选择 token、字段签名及保存时 revision/context 身份核对均未修改。校准控制器、校准记录持久化、参数提交和校准公式不并入扫描仓储。
- 新增根装配集成测试：真实提交的摘要为 12 个 / 3.45 kg，读回原始未校准基线为 10 个 / 2.5 kg；完整记录准入、后台读取、原始字节保护、过期摘要拒绝和源 SHA 不匹配拒绝均覆盖。新增实际表单渲染测试，配置根中仅有 incomplete 记录时不显示最近扫描选择器，完整记录存在时显示。
- 初次定向 5 通过，初次 full 1019 通过，但复审发现测试的 `Thread.isMainThread` 位于 async 上下文，新增校准检查及上一轮导入检查均改为同步 Sendable 检查闭包，保留后台线程断言，重跑 6 项通过。另修正新增渲染夹具的窗口安装/捕获时机，最终使用同一前台窗口与独立视图身份；重跑渲染方法通过，单独核对原尺寸完整/incomplete 附件的页首与选择器。旧包保留，不将初次通过汇总替代修正后的证据。
- 最后源码和测试修改后 `storage ui full` 为 **1019 项通过、0 失败/跳过/预期失败，59 个类，退出 0**；关键结果树逐项确认两个新增方法及受影响导入刷新方法 Passed。Domain 24 源及 unsigned Release 模拟器构建成功，所有步骤退出 0，开始/结束快照一致。新 Swift 文件实际进入 App Sources；本轮线程检查警告已消除，其他既有测试的 RunLoop 警告仍存在。此后仅补文档和仓库外证据。
- 隔离 iOS 模拟器安装最终受测 Debug App，实际走通工作台校准 → 新增 → 最近扫描菜单，仅出现完整 A/B，未出现原始导入/incomplete/损坏记录。选择 B 后表单带入 10 个 / 2.0 kg 原始基线，改选 A 后为 6 个 / 0.42 kg，与各自元数据一致；菜单仍显示记录摘要 11 个 / 2.7 kg 和 7 个 / 1.2 kg。取消输入并关闭校准返回工作台，记录数仍为 5。没有保存校准或调整参数。
- 安装和走查后原有 10 个文件与上一轮新增合成 PLY 共 11 个 SHA-256 均保持，档案文件无新增/删除。元数据迟到及字段编辑分支的 token/signature 守卫通过独立差异复审保留；本轮重新选择走查不等于强制延迟回调的并发实验。

证据在 `/private/tmp/fruit-iteration33/`：`baseline.xcresult`、`targeted.xcresult`、`targeted-repaired.xcresult`、`render-repaired.xcresult`、`attachments-final/`、最终 `fruit-code-improvement-cv8_573x/report.json` / `test-tree.log`、`ui-install-preservation.json`、`ui-validation.json` 和 `final-review.json`。独立复审装配、原始基线映射、异步守卫、兼容入口与 App target，无阻塞发现；六个原有工作流文件摘要保持。本轮 **mergeable**，第 32/33 轮均尚未提交、未推送；剩余消费者和物理验收未完成，整体目标仍 **needs changes**。

## 第三十四轮：预览继承根历史与外层关闭动作

真实工作台和历史页预览都进入 `PointCloudSheet`，但列表、空态及刷新仍观察 shared。新增实际工作台 sheet 工厂渲染回归：隔离仓储仅有新建 A 记录时，修复前却显示全局目录中的 NORTH/SOUTH 两条记录，**编译成功、1 项失败、退出 65**；结果树确认关键方法确实 Failed，没有清空或改写全局档案来制造失败。

- `PointCloudSheet` 增加兼容默认入口的历史参数，工作台及历史页嵌套预览传递各自已注入实例。现有初始选取、搜索、文件变更后的回退、PLY 加载和采样函数保持。
- 回归在真实渲染中确认根记录可见和 selected trait；加入较新记录仍保留显式选择，移除仅测试拥有的源后回退到同一根，清空临时根后显示新扫描/导入动作。原始 PLY 字节在各次读取和保留刷新后核对不变；附件单独按原尺寸检查。此测试调用实际 sheet 工厂，未冒充原生点击打开整个路由。
- 第一阶段定向 **3 项通过**、第一次 `storage ui full` **1020 项通过**。随后在专用模拟器实际打开工作台预览，切换 B → 导入 A 成功，但可见关闭按钮点击及后续稳定截图都仍停在预览。读取实际按钮链确认它消费内层 NavigationView 的 dismiss，没有外层 sheet 的关闭动作。这项人工失败记录在 `native-close-before.json`，与自动化历史来源回归分开。
- 修复该走查发现：`PointCloudSheet` 将外层 dismiss 显式传给 `PointCloudView`；后者通过可选回调关闭，独立默认入口仍使用原 dismiss 回退。点云解析、异步加载、SceneKit、测量、导出、融合与校准均未改动。
- 关闭修复后先重新定向 **4 项通过，退出 0**，完整验证为 1020 通过。Mac 持续锁定期间，继续补真实呈现 `PointCloudSheet` 的关闭回归：用既有无障碍标签与按钮 trait 定位并激活可见控件，确认外层 presented controller 消失、回到测试宿主及点云原字节保持。初始夹具的 NSObject 标识访问编译失败、随后协议标识定位失败均保留；改用真实标签并检查实际呈现附件后通过，不把夹具问题算作产品回归。
- 为证明新回归有效，仅临时撤去本轮的一行外层关闭绑定。按钮激活成功，但外层 sheet 仍存在，**1 项在关闭断言失败、退出 65**；恢复完全相同的绑定后，**5 项定向通过、退出 0**，生产源码和六个原有改动摘要逐项核对。该测试证明真实生产预览的模态关闭动作，不冒充工作台/历史页的原生点击。
- 最后测试修改后最终 `storage ui full` 为 **1021 项通过、0 失败/跳过/预期失败，59 个类，所有 9 步退出 0**；Domain 24 源和 unsigned Release 模拟器构建成功，开始/结束快照一致。结果树确认新增关闭方法及原 7 个关键方法共 8 项 Passed；实际关闭附件按原尺寸检查。此前两份 1020 包保留为阶段证据，不替代最终 1021 包。
- 最终受测 App 安装到专用模拟器后曾因 Mac 锁定中断原生验收。2026-10-02 原生操作恢复，实际走通工作台点云入口 → 关闭 → 首页，以及历史页 B 记录预览 → 关闭仅返回历史页 → 完成返回首页；记录数保持 5，原完整、incomplete 和损坏状态均保留。走查后原有 11 个档案/校准文件 SHA-256 全部保持，档案目录无新增或删除。未执行永久删除或物理采集。

证据在 `/private/tmp/fruit-iteration34/`：来源失败 `regression-before.xcresult`、关闭失败 `close-binding-before.xcresult`、最终定向 `close-binding-restored.xcresult`、`close-regression-evidence.json`、`attachments-targeted/` 和 `attachments-close-restored/`、最终 `fruit-code-improvement-pg3hgd63/report.json` / `test-tree.log`、`final-critical-methods.json`、`native-close-before.json`、`ui-install-preservation.json` 和 `ui-validation.json`。独立差异复审检查根实例、观察生命周期、两条生产调用链、选取回退、关闭动作归属、实际控件回归及默认 API，没有源码阻塞发现；最终运行日志有内部 QoS 警告，未将其写成实测性能收益。六个原有工作流改动摘要保持，第 32/33 轮内容除必要追加处外保持。本轮 **mergeable**；第 32–34 轮尚未提交、未推送，剩余消费者和物理验收使整体目标仍 **needs changes**。

### 下一轮构思与提示词：报告与趋势接入根历史

第 34 轮人工关卡已补齐，下一项是 `DashboardAnalyticsSheets` 中仍固定观察 shared 的 `YieldReportSheet` 与 `TrendsSheet`。两者的数据模型已经过滤 incomplete/invalid；报告按每树最新完整记录汇总，趋势保留完整时间序列，这些语义保持。先验证隔离根和真实工作台工厂，再传递根历史，不为消除重复而合并不同聚合规则。地图、对比及设置保留为后续范围。

```text
继续按代码改进工作流推进根依赖装配，保留六个原有工作流 dirty work。
第三十一轮已由 PR #12 合并；第三十二至三十四轮尚未提交，最新最终全量 1021 项通过。
第 34 轮工作台关闭、历史页嵌套预览关闭和返回首页已实际核对，不重做该修复。
原 11 个隔离模拟器档案/校准文件保持，永久删除和物理采集不包含在该关卡。
再 preflight，追踪 Dashboard → YieldReportSheet/TrendsSheet → 各自数据模型与历史刷新。
用隔离根建立真实 sheet 工厂的失败回归或移动基线，向两个生产入口传递根历史。
保留默认 API、complete-only 准入、报告每树最新完整记录和趋势完整时间序列。
不改聚合数学、融合准入、校准公式、schema、摘要、点云解析或资源上限。
验证空根、可靠零值、损坏/未完成排除、同树重复及刷新后的实际渲染；不动态生成期望值。
按 storage ui full 验证，最后源码修改后核对关键方法执行，独立复审并走查实际入口和关闭。
不重做已完成的历史/导入/校准/预览装配，不自动提交或推送。
```

## 第三十五轮：报告与趋势使用根历史并响应刷新

根因：工作台已经持有根历史，但报告与趋势固定观察 `ScanHistoryStore.shared`；趋势入口还缺少冷启动加载。两个生产 sheet 工厂用独立目录的冷历史渲染，修复前均显示空态，新增方法实际失败，退出 65。

- 两个页面接收根历史，工作台真实路由传入同一实例；默认构造兼容保留。趋势入口请求加载，报告已有加载保持。没有改动两种数据模型、聚合数学、筛选或展示布局。
- 实际 SwiftUI 回归覆盖冷启动、根刷新和完整结果消失后的空态：报告保留同树最新完整零产量，趋势保留两次完整记录；原始 PLY、损坏 companion 和 incomplete 不进入汇总。夹具修改及删除仅发生在 UUID 测试目录，四份 PLY 字节保持。
- 最终 5 项定向通过、退出 0。六张初始/刷新/空态附件逐张检查，未把工厂渲染写成工作台原生点击。
- 最后源码修改后的 `storage ui full` 为 **1022 项通过、0 失败/跳过/预期失败，59 个类，全部 9 步退出 0**；Domain 24 源独立编译及 unsigned Release 模拟器构建成功，开始/结束快照一致。关键方法在结果树中实际 Passed。预览测试的两条内部 QoS 警告继续保留，没有实测性能改善结论。
- 最终受测 Debug App 已安装到专用模拟器，11 份既有档案/校准文件摘要保持。合并前尝试原生入口走查时 Mac 再次锁定，电脑操作工具无法读取窗口；已请求手动解锁。本轮原生点击尚未完成，已有模拟器测试与附件不替代这项记录。

证据位于 `/private/tmp/fruit-iteration35/`：`before.xcresult`、`after.xcresult`、`attachments/`、`fruit-code-improvement-54l195dt/report.json` / `test-tree.log` 和 `ui-install-preservation.json`。独立复审确认生产入口注入、观察生命周期、默认 API、完整零值及原有聚合规则保持，未发现代码阻塞问题；代码与已执行模拟器验证范围为 **mergeable**。原生点击、永久删除和物理 LiDAR 验收仍单独待完成，整体目标保持 **needs changes**。

### 2026-10-02 第三十二至三十五轮交付检查点

用户再次明确要求“推送并合并”。第 32–35 轮根依赖装配、预览关闭修复及对应回归已提交为 `c2499a74`（`refactor(app): bind scan consumers to root dependencies`），19 个源码/测试文件；本执行记录单独提交。提交前 preflight 通过，暂存源码及测试逐项匹配上述最终 1022 项通过的快照；架构记录只在验证结束后补充实际证据。原有六项工作流改动保持本地未提交；构建产物和合成数据均不纳入提交。远程推送、CI 与合并结果以随后核对的 GitHub PR 和仓库外发布证据为准。

### 下一轮构思与提示词：剩余根历史消费者

```text
继续读取 AGENTS.md 与本记录并执行 preflight。第 31–35 轮已完成历史、导入、
校准扫描来源、预览、报告与趋势的根装配，不重复这些迁移。
先核对交付 PR 的实际状态，再补第 35 轮因 Mac 锁定尚未完成的报告/趋势原生点击。
追踪 Dashboard → 地图/历史对比 → 历史数据来源，逐项选取有证据的 shared 依赖问题。
用隔离根建立失败回归或移动基线，保留每个页面不同的筛选与聚合规则及默认 API。
设置消费者另行核对，不合并不同存储所有权，不新增无消费者抽象或测试专用产品路由。
保留 complete-only、可靠零值、.fused、拒绝原因、校准上下文、旧 schema 与摘要校验。
使用相关风险验证、最后源码修改后的全量结果树与独立差异复审，记录真实验收限制。
保护六项原有 dirty work 和专用模拟器 11 份档案；永久删除仍需对应确认。
物理采集、人工果数和资源测量独立验收。更新下一步提示词，不自动提交或推送。
```

## 验证记录

日志与 xcresult 位于 `/Users/reece24/Library/Logs/FruitTreeScanner/architecture-reassessment-20260927/`。

| 验证 | 文件 | 结果 |
|---|---|---|
| 第一轮定向 | iteration-01.xcresult / iteration-01.log | 120 通过，0 失败，退出码 0 |
| 第二轮定向 | iteration-02.xcresult / iteration-02.log | 164 通过，0 失败，退出码 0 |
| 第二轮全量模拟器（历史） | iteration-02-full.xcresult / iteration-02-full.log | 922 通过，0 失败、0 跳过，退出码 0 |
| 第二轮 Release 模拟器构建（历史） | iteration-02-release.log | 成功，退出码 0 |
| 第三轮资源/队列 | iteration-03-lifetime.xcresult / iteration-03-lifetime.log | 63 通过，0 失败，退出码 0 |
| 第三轮导出与流程 | iteration-03-export.xcresult / iteration-03-export.log | 311 通过，0 失败，退出码 0 |
| 第四轮全量模拟器 | iteration-04-full.xcresult / iteration-04-full.log | 934 通过，0 失败、0 跳过，退出码 0 |
| 第四轮 Release 模拟器构建 | iteration-04-release.log | 成功，退出码 0 |
| 第五轮契约迁移 | iteration-05-contract-build.xcresult / iteration-05-contract-build.log | 127 通过，退出码 0 |
| 第五轮绑定凭证 | iteration-05-bound-evidence.xcresult / iteration-05-bound-evidence.log | 167 通过，退出码 0 |
| 第五轮全量模拟器 | iteration-05-full.xcresult / iteration-05-full.log | xcresult 确认 939 通过，0 失败/跳过；终端退出码未取回 |
| 第五轮兼容入口 | iteration-05-compatibility.xcresult / iteration-05-compatibility.log / iteration-05-compatibility.status | 127 通过，退出码 0 |
| 第六轮初次构建（已修复） | iteration-06-repository.log / iteration-06-repository.status | 缺少 MainActor 回调隔离，退出码 65 |
| 第六轮定向重试（已修复） | iteration-06-repository-retry.xcresult / iteration-06-repository-retry.log | 129 通过、1 个新夹具 URL 断言失败，退出码 65 |
| 第六轮全量模拟器 | iteration-06-full.xcresult / iteration-06-full.log / iteration-06-full.status | 942 通过，0 失败/跳过，退出码 0 |
| 第六轮 Release 模拟器 | iteration-06-release.log / iteration-06-release.status | 成功，退出码 0 |
| 第七轮初次定向（夹具已修复） | iteration-07-configuration.xcresult / .log / .status | 179 通过、1 个新增夹具断言失败，退出码 65 |
| 第七轮夹具修正后 | iteration-07-configuration-retry.xcresult / .log / .status | 1 通过，退出码 0 |
| 第七轮全量模拟器 | iteration-07-full.xcresult / .log / .status | 951 通过，0 失败/跳过，退出码 0 |
| 第八轮全量模拟器 | iteration-08-domain-full.xcresult / .log / .status | 951 通过，0 失败/跳过，退出码 0 |
| 第八轮 Release 模拟器 | iteration-08-release.log / .status | 成功，退出码 0 |
| 第八轮设备 SDK Release 构建 | iteration-08-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第九轮全量模拟器 | iteration-09-calibration-full.xcresult / .log / .status | 952 通过，0 失败/跳过，退出码 0 |
| 第九轮 Release 模拟器 | iteration-09-release.log / .status | 成功，退出码 0 |
| 第九轮设备 SDK Release 构建 | iteration-09-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十轮故障复现 | iteration-10-camera-probe.xcresult / .log / .status | 2 个新增回归失败，退出码 65；之后已修复 |
| 第十轮首次定向构建 | iteration-10-camera-targeted.log / .status | private 方法跨文件访问失败，退出码 65；之后已修复 |
| 第十轮定向重试 | iteration-10-camera-targeted-retry.xcresult / .log / .status | 41 通过，退出码 0 |
| 第十轮全量模拟器 | iteration-10-camera-full.xcresult / .log / .status | 957 通过，0 失败/跳过，退出码 0 |
| 第十一轮配置契约 | iteration-11-config-contract.xcresult / .log / .status | 72 通过，退出码 0 |
| 第十一轮全量模拟器 | iteration-11-full.xcresult / .log / .status | 958 通过，0 失败/跳过，退出码 0 |
| 第十一轮 Release 模拟器 | iteration-11-release.log / .status | 成功，退出码 0 |
| 第十一轮设备 SDK Release 构建 | iteration-11-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十二轮初次回放（夹具已修正） | iteration-12-replay.xcresult / .log / .status | 4 通过、1 个投影采样数断言失败，退出码 65 |
| 第十二轮首次全量（夹具已修正） | iteration-12-full.xcresult / .log / .status | 962 通过、1 个手算期望遗漏置信度加权，退出码 65 |
| 第十二轮全量模拟器 | iteration-12-full-retry.xcresult / .log / .status | 963 通过，0 失败/跳过，退出码 0 |
| 第十二轮 Release 模拟器 | iteration-12-release.log / .status | 成功，退出码 0 |
| 第十二轮设备 SDK Release 构建 | iteration-12-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十三轮迁移定向 | iteration-13-model-identity.xcresult / .log / .status | 42 通过，退出码 0 |
| 第十三轮故障注入构建（已修复） | iteration-13-traversal-probe.log / .status | Foundation extension 方法不能覆盖，退出码 65；未执行测试 |
| 第十三轮定向重试 | iteration-13-model-identity-retry.xcresult / .log / .status | 43 通过，退出码 0 |
| 第十三轮全量模拟器 | iteration-13-full.xcresult / .log / .status | 968 通过，0 失败/跳过，退出码 0 |
| 第十三轮 Release 模拟器 | iteration-13-release.log / .status | 成功，退出码 0 |
| 第十三轮设备 SDK Release 构建 | iteration-13-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十四轮全量模拟器 | iteration-14-full.xcresult / .log / .status | 968 通过，0 失败/跳过，退出码 0 |
| 第十四轮 Release 模拟器 | iteration-14-release.log / .status | 成功，退出码 0 |
| 第十四轮设备 SDK Release 构建 | iteration-14-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十四轮测试警告清理 | iteration-14-warning-cleanup.xcresult / .log / .status | 27 通过，0 失败/跳过，退出码 0 |
| 第十五轮投影迁移定向 | iteration-15-projection.xcresult / .log / .status | 178 通过，0 失败/跳过，退出码 0 |
| 第十五轮全量模拟器 | iteration-15-full.xcresult / .log / .status | 968 通过，0 失败/跳过，退出码 0 |
| 第十五轮 Release 模拟器 | iteration-15-release.log / .status | 成功，退出码 0 |
| 第十五轮设备 SDK Release 构建 | iteration-15-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十六轮观测去重定向 | iteration16-dedup.xcresult / .log / .status | 316 通过，0 失败/跳过，退出码 0 |
| 第十六轮全量模拟器 | iteration16-full.xcresult / .log / .status | 971 通过，0 失败/跳过，退出码 0 |
| 第十六轮 Release 模拟器 | iteration16-release.log / .status | 成功，退出码 0 |
| 第十六轮设备 SDK Release 构建 | iteration16-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十七轮观测链路定向 | iteration17-observations.xcresult / .log / .status | 292 通过，0 失败/跳过，退出码 0 |
| 第十七轮全量模拟器 | iteration17-full.xcresult / .log / .status | 974 通过，0 失败/跳过，退出码 0 |
| 第十七轮 Release 模拟器 | iteration17-release.log / .status | 成功，退出码 0 |
| 第十七轮设备 SDK Release 构建 | iteration17-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十八轮修复前实时计数探针 | iteration18-live-count-probe.xcresult / .log / .status | 1 通过、4 个预期回归失败，退出码 65 |
| 第十八轮修复后定向 | iteration18-live-count.xcresult / .log / .status | 206 通过，0 失败/跳过，退出码 0 |
| 第十八轮全量模拟器 | iteration18-full.xcresult / .log / .status | 980 通过，0 失败/跳过，退出码 0 |
| 第十八轮 Release 模拟器 | iteration18-release.log / .status | 成功，退出码 0 |
| 第十八轮设备 SDK Release 构建 | iteration18-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第十九轮迁移前校准基线 | iteration19-calibration-baseline.xcresult / .log / .status | 30 通过，0 失败/跳过，退出码 0 |
| 第十九轮首次配置迁移 | iteration19-config-separation.xcresult / .log / .status | 144 通过、2 个遗漏兼容值的旧调用失败，退出码 65 |
| 第十九轮补齐调用定向 | iteration19-config-retry.xcresult / .log / .status | 189 通过，0 失败/跳过，退出码 0 |
| 第十九轮全量模拟器 | iteration19-full.xcresult / .log / .status | 983 通过，0 失败/跳过，退出码 0 |
| 第十九轮 Release 模拟器 | iteration19-release.log / .status | 成功，退出码 0 |
| 第十九轮设备 SDK Release 构建 | iteration19-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十轮初次多果实夹具 | iteration20-multifruit-baseline.xcresult / .log / .status | 48 通过、2 个夹具格式假设失败，退出码 65 |
| 第二十轮修正夹具基线 | iteration20-multifruit-retry.xcresult / .log / .status | 52 通过，0 失败/跳过，退出码 0 |
| 第二十轮质量关联定向 | iteration20-mass-association.xcresult / .log / .status | 345 通过，0 失败/跳过，退出码 0 |
| 第二十轮全量模拟器 | iteration20-full.xcresult / .log / .status | 987 通过，0 失败/跳过，退出码 0 |
| 第二十轮 Release 模拟器 | iteration20-release.log / .status | 成功，退出码 0 |
| 第二十轮设备 SDK Release 构建 | iteration20-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十一轮迁移前合并基线 | iteration21-combiner-baseline.xcresult / .log / .status | 52 通过，0 失败/跳过，退出码 0 |
| 第二十一轮领域合并定向 | iteration21-combiner-domain.xcresult / .log / .status | 351 通过，0 失败/跳过，退出码 0 |
| 第二十一轮全量模拟器 | iteration21-full.xcresult / .log / .status | 993 通过，0 失败/跳过，退出码 0 |
| 第二十一轮 Release 模拟器 | iteration21-release.log / .status | 成功，退出码 0 |
| 第二十一轮设备 SDK Release 构建 | iteration21-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十二轮迁移前决策基线 | iteration22-policy-baseline.xcresult / .log / .status | 85 通过，0 失败/跳过，退出码 0 |
| 第二十二轮值决策定向 | iteration22-policy-domain.xcresult / .log / .status | 360 通过，0 失败/跳过，退出码 0 |
| 第二十二轮全量模拟器 | iteration22-full.xcresult / .log / .status | 996 通过，0 失败/跳过，退出码 0 |
| 第二十二轮 Release 模拟器 | iteration22-release.log / .status | 成功，退出码 0 |
| 第二十二轮设备 SDK Release 构建 | iteration22-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十三轮混合几何回放 | iteration23-mixed-replay.xcresult / .log / .status | 59 通过，0 失败/跳过，退出码 0 |
| 第二十三轮初版重分配回放 | iteration23-reassignment-replay.xcresult / .log / .status | 253 通过，0 失败/跳过，退出码 0；最终夹具再收紧，由全量验证 |
| 第二十三轮全量模拟器 | iteration23-full.xcresult / .log / .status | 998 通过，0 失败/跳过，退出码 0 |
| 第二十四轮隔离依赖探针 | iteration24-domain-baseline.log / .status | 4 处旧检测类型依赖，预期退出码 1；迁移后消除 |
| 第二十四轮独立融合编译 | iteration24-fusion-module.log / .status | 16 个源文件独立生成模块成功，退出码 0 |
| 第二十四轮品类/校准/融合定向 | iteration24-category-domain.xcresult / .log / .status | 346 通过，0 失败/跳过，退出码 0 |
| 第二十四轮全量模拟器 | iteration24-full.xcresult / .log / .status | 998 通过，0 失败/跳过，退出码 0 |
| 第二十四轮 Release 模拟器 | iteration24-release.log / .status | 成功，退出码 0 |
| 第二十四轮设备 SDK Release 构建 | iteration24-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十五轮计划依赖探针 | iteration25-plan-baseline.log / .status | 5 类外部值的 8 处引用，预期退出码 1；迁移后消除 |
| 第二十五轮初次捕获基线 | iteration25-capture-baseline.xcresult / .log / .status | 52 通过、1 个新增夹具失败，退出码 65；后已修正 |
| 第二十五轮捕获基线重试 | iteration25-capture-baseline-retry.xcresult / .log / .status | 53 通过，0 失败/跳过，退出码 0 |
| 第二十五轮独立计划/融合编译 | iteration25-plan-module.log / .status | 21 个源文件独立生成模块成功，退出码 0 |
| 第二十五轮迁移内容核对 | iteration25-move-content-check.json | 存储、校准、计划/会话主体和迁移值核对通过 |
| 第二十五轮迁移后定向 | iteration25-plan-domain.xcresult / .log / .status | 264 通过，0 失败/跳过，退出码 0 |
| 第二十五轮下一轮依赖探针 | iteration25-full-domain-next-probe.log / .status | 整个 Domain 仍缺 YieldResult，预期退出码 1；尚待下一轮 |
| 第二十五轮全量模拟器 | iteration25-full.xcresult / .log / .status | 1001 通过，0 失败/跳过，退出码 0 |
| 第二十五轮 Release 模拟器 | iteration25-release.log / .status | 成功，退出码 0 |
| 第二十五轮设备 SDK Release 构建 | iteration25-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十六轮领域基线探针 | iteration26-domain-baseline.log / .status | 22 个源文件仍缺 YieldResult，预期退出码 1；迁移后消除 |
| 第二十六轮整个领域编译 | iteration26-domain-module.log / .status | 24 个源文件独立生成模块成功，退出码 0 |
| 第二十六轮完整递归发现 | iteration26-domain-module-discovery.log / .status | 隐藏/忽略路径一并发现；24 文件与独立清点一致，编译成功，退出码 0 |
| 第二十六轮迁移内容核对 | iteration26-move-content-check.json | 结果/诊断、质量、旧中间值和冻结身份核对通过 |
| 第二十六轮结果/导出/融合定向 | iteration26-result-domain.xcresult / .log / .status | 395 通过，0 失败/跳过，退出码 0 |
| 第二十六轮全量模拟器 | iteration26-full.xcresult / .log / .status | 1001 通过，0 失败/跳过，退出码 0 |
| 第二十六轮 Release 模拟器 | iteration26-release.log / .status | 成功，退出码 0 |
| 第二十六轮设备 SDK Release 构建 | iteration26-device-build.log / .status | 未签名编译成功，退出码 0；不是设备运行证据 |
| 第二十七轮无 rg 基线 | iteration27-no-rg-baseline.log / .status | 原脚本工具不可用，退出码 1；已增加发现后备路径 |
| 第二十七轮领域编译 | iteration27-rg-domain.log / .status；iteration27-no-rg-domain.log / .status | 两种环境均实际编译 24 源文件成功，退出码 0 |
| 第二十七轮隐藏反向依赖 | iteration27-hidden-dependency-probe.json；iteration27-hidden-dependency-with_rg / without_rg.log / .status | 两条路径均拒绝外部夹具的 Core 类型依赖，预期退出码 1 |
| 第二十七轮工具故障矩阵 | iteration27-ci-failure-matrix.json | 6 个替身场景通过；不是实际 Xcode 编译或 XCTest |
| 第二十七轮 Xcode 选择故障 | iteration27-selection-failure-baseline.json / iteration27-selection-failure-retry.json | 初版覆盖失败状态；修正后两个入口返回 72、构建未启动 |
| 第二十七轮最终选择/结构核对 | iteration27-final-selection-check.json | 显式 Xcode、runner Xcode、工作流选择及结构均通过 |
| 第二十七轮最终本地 CI 构建 | iteration27-real-ci-build-final.log / .status；iteration27-real-ci-final-summary.md | 通用 iOS 模拟器 Debug 未签名构建成功，退出码 0；非远程 CI |
| 提交前全量模拟器复核 | commit-20261001-full.xcresult / .log / .status | 1001 通过，0 失败/跳过，退出码 0 |
| 提交前完整 Domain 复核 | commit-20261001-domain.log / .status | 24 源文件独立编译成功，退出码 0 |
| 提交内容核对 | commit-20261001-before.json；commit-20261001-content-check.json | 125 个原有改动路径清点；源码与测试暂存内容逐项核对，验证后只删除一处尾空行 |
| 第二十八轮 UI / full | /private/tmp/fruit-iteration28/fruit-code-improvement-y4dguri6/report.json | 1005 通过，0 失败/跳过/预期失败，退出 0；Domain / Release 成功 |
| 第二十九轮 storage / UI / full | /private/tmp/fruit-iteration29/fruit-code-improvement-jp19bunp/report.json | 1007 通过，0 失败/跳过/预期失败，退出 0；Domain / Release 成功 |
| 第三十轮 UI / full | /private/tmp/fruit-iteration30/fruit-code-improvement-1xa5prr5/report.json | 1008 通过，0 失败/跳过/预期失败，退出 0；Domain / Release 成功 |
| 第三十一轮迁移前 full | /private/tmp/fruit-iteration31/fruit-code-improvement-kc5x7vvs/report.json | 1008 通过，0 失败/跳过/预期失败，退出 0；Domain / Release 成功 |
| 第三十一轮 storage / lifecycle / UI / full | /private/tmp/fruit-iteration31/fruit-code-improvement-kk75926j/report.json | 1014 通过，0 失败/跳过/预期失败，退出 0；59 类和六个新方法执行，Domain / Release 成功 |
| 第三十二轮配置目录失败回归（修复前） | /private/tmp/fruit-iteration32/before.xcresult / before.status | 1 个测试失败，退出 65；确认错误默认目录发布 |
| 第三十二轮修复后定向 | /private/tmp/fruit-iteration32/after-repaired.xcresult / after-repaired.status | 3 通过，0 失败，退出 0 |
| 第三十二轮 storage / UI / full | /private/tmp/fruit-iteration32/fruit-code-improvement-d402qz6f/report.json | 1017 通过，0 失败/跳过/预期失败，退出 0；59 类和三个新方法执行，Domain / Release 成功 |
| 第三十二轮原生导入与保护 | /private/tmp/fruit-iteration32/ui-validation.json | 取消及实际成功/历史刷新走通；原 10 文件摘要保持，新增合成 PLY 字节一致且 incomplete |
| 第三十三轮移动前基线 | /private/tmp/fruit-iteration33/baseline.xcresult | 3 通过，退出 0；complete 准入、原始基线/未知来源拒绝、校准独立存储 |
| 第三十三轮修正后定向与渲染 | /private/tmp/fruit-iteration33/targeted-repaired.xcresult / render-repaired.xcresult | 6 项定向通过；最终渲染方法通过，原尺寸附件复核 |
| 第三十三轮 storage / UI / full（最新源码） | /private/tmp/fruit-iteration33/fruit-code-improvement-cv8_573x/report.json | 1019 通过，0 失败/跳过/预期失败，退出 0；59 类与关键方法执行，Domain / Release 成功 |
| 第三十三轮原生校准与保护 | /private/tmp/fruit-iteration33/ui-validation.json | 完整记录选择、B/A 原始基线、取消/返回走通；原 11 文件摘要保持 |
| 差异检查 | git diff --check | 通过 |

本地工作区的默认验证入口（runner 尚未纳入本次提交；需要保留的本地工作流文件，证据自动保存在仓库外）：

```sh
python3 tools/code_improvement_workflow.py preflight
python3 tools/code_improvement_workflow.py ui full
```

此前手工验证命令（日志目录沿用创建日期；重新运行须使用新结果包名称）：

```sh
bash tools/validate_fusion_domain.sh

DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
bash tools/ci_simulator_build.sh

DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -quiet -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -resultBundlePath /Users/reece24/Library/Logs/FruitTreeScanner/architecture-reassessment-20260927/iteration26-full.xcresult

DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild build -quiet -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

git diff --check
```

首次验证已生成上述 xcresult；重跑时需使用新的结果包名称。测试数由 xcresulttool summary 核对，成功以 xcodebuild 终端退出码为准。当前全量继续覆盖跨服务同源串行、不同源并行、历史删除等待提交、失败回滚不覆盖后续修订，以及融合、校准和旧记录解析。

本轮保留 `.fused` 唯一可靠来源、低置信度拒绝、默认融合阈值、zeroYieldReasons、默认校准上下文和存档 schema。自定义实验或预算必须匹配自己的校准上下文。没有对真实用户扫描目录做故障注入。第 1–27 轮已按用户后续要求提交、推送并合并 PR #10；第 28–30 轮后续提交见上方检查点，既有工作流 dirty work 继续保留在本地。

2026-09-28 设备查询确认一台 iPhone 17 Pro 物理设备已配对、可连接且开启开发者模式；另一台 iPad Pro 当前不可用。尚未执行实际树冠采集或测量真机内存。本轮已询问操作者能否提供同一棵树的绕拍及人工果数，待回复；设备可连接不代表精度验收已通过。

## 2026-10-01：本地提交检查点

用户明确要求“对此前进行提交”后，按此前清点的架构改动分组提交：

1. `be3de463` — `refactor(scan): isolate scan evidence, lifecycle and archive ownership`：生产架构、工程引用、旧研究路径隔离与回归测试。文件迁移和消费者相互依赖，作为同一可编译检查点提交。
2. `ec782e82` — `ci(ios): enforce Domain isolation before simulator compilation`：工作流、两个工具脚本及工具说明，独立于产品行为提交。
3. `docs(architecture): record redesign, validation and iteration checkpoints`：原设计材料、重判读/探针快照、基线、实施与第 1–27 轮记录及本检查点。

提交前重新执行全量模拟器 XCTest，1001 项通过、0 失败/跳过、退出码 0；完整 Domain 独立编译成功。暂存检查首次发现原未跟踪 FruitEvidence.swift 的一处文件尾空行，删除后通过；内容核对确认测试后没有其他源码或测试变化。此前模拟器/设备 SDK Release 和本地 CI 工具验证仍分别保留其证据，不写成此次重新运行。

所有提交留在本地 `codex/scan-architecture-refactor`，没有推送、合并或远程 CI 运行。检查期间新出现的 `tools/code_improvement_workflow.py`、配套 `docs/implementation/CODE_IMPROVEMENT_WORKFLOW.md` 及两份 README 中的新工作流说明不属于此前改动清单，保持未提交；没有将这些新增内容混入本检查点。提交存档不代表整体验收完成，完整 UI、物理设备与后续迭代范围继续保留，整体决策仍为 **needs changes**。

## 下一轮构思与待实施项

根据当前代码，前述扫描/仓储边界、观测链路、质量关联、融合值服务、回放、品类/设置分层和结果/质量/诊断值归属已实施；整个 Domain 的 24 个源文件已通过独立 iOS 模块编译，门禁已接入 CI 并验证本地失败传播。接下来补齐运行证据：

1. **继续贯通根依赖装配。** 第 31–34 轮已接入历史查询/删除、完成刷新、工作台/历史/批量列表、导入、校准扫描来源和预览；第 34 轮关闭/返回原生走查已补齐。下一项处理报表/趋势，随后地图、对比和设置消费者；具体提示词见第 34 轮。不以默认目录相同或测试通过替代真实生产装配。
2. **补齐完整记录删除流程的剩余证据。** 隔离夹具的历史读取、三种批量格式、取消/清理、校准基线导入及保存已实际核对；第 28–30 轮发现的状态、临时目录所有权和颜色问题已修复。删除确认与取消通过，永久删除尚待用户在操作时确认；得到具体确认后只操作 UI-FIXTURE-B，核对 PLY/结果 JSON/完成清单消失、其他源摘要保持及历史刷新。Device Hub 原生操作当前可用。物理完成/重试仍需另行验收，不用模拟器无 LiDAR 的页面替代。
3. **设备回放与物理验收。** 混合几何和必须重分配的合成回放已完成，不重复。下一步设计有采样上限和脱敏规则的真实观测基线，并标明人工果数、采集条件及模型/配置身份。已发现可连接 LiDAR iPhone；实际 30/60/120 秒绕拍需要操作者与场景基准。分别记录物理内存、采集/结束耗时、深度拒绝诊断和人工果数误差，不能用模拟器通过代替。
4. **持续构建远程验收与模块收益评估。** Domain 门禁及模拟器编译已在 PR #10 的 run `36801712785`、PR #11 的 run `36827532091` 实测成功，覆盖第 1–30 轮；第 31 轮经 PR #12 的 run `36833185872` 成功后合并为 `f440f587`。第 32–34 轮尚未提交、未推送。当前只有 App/XCTest 两个 target；Domain 类型仍使用模块内可见性。framework/package 需要按消费者定义公开 API，只有能减少实际依赖复杂度时才启动该迁移。当前维持单 App target 与完整 Domain 编译门禁，保留模型/shader 归属及 ReliableYieldEvidence 准入权限。

这些事项尚未完成，不能用当前定向或全量 XCTest 代替它们的实现与设备验收。目标继续保持 active。

## 下一轮执行提示词

```text
继续 FruitTreeScanner 的整体架构重构。先读取 AGENTS.md 和本执行记录，
核对真实工作区，不重做已完成的 25 ms 轮询移除、导出 async 迁移或事务解环。

配置消费者、资源预算和相机规格请求已贯通，Plan 值/工厂/展示模型已分开，
重复实验默认种子已移除，默认校准上下文字节有固定夹具验证。
基础观测回放和模型指纹文件边界已经完成；目录读取失败不可生成部分指纹。
先核对本记录中最后一次验证结果，完成尚未结束的步骤。
投影/ROI 核心已经移至 Domain/Fusion，像素采样和旧缓冲输入位于
Infrastructure/Detection。候选/结果值和观测去重也已迁移，最终融合已去除两轮门面往返。
协调器的活动证据、归档、HUD 输入、品类核对及最终冻结现已贯通为 Observation。
实时确认计数的计划聚类/融合参数和目标品类过滤也已修复，4 项失败探针及后续回归
已证明原问题与修复效果，不重做。保留先计算全体对齐观测的最近窗口再筛选目标品类，
保持最少两帧、最低 0.85；实时计数与全扫描估产无需数量相等。
保留原 FrameID/观测身份/拒绝原因和 checked Sendable；旧缓冲采样只放在边界，
避免引入主线程重采样，保留后台归档修订与生命周期迟到结果拒绝。
品类先验、颜色与实验规则已经归入 Domain；旧品类检测入口只留在检测边界，
生产调用迁移后才删除无实际消费者的兼容转发。
Observation 和 Input 的 checked Sendable 约束应保留；不能把平台缓冲重新带进快照。
保留模型相对路径排序、摘要字节、不可用状态及一次性缓存，不重复迁移已完成代码。
FruitScanConfig 的无效球形度字段已分离，实际运行配置已经移入 Domain。
legacyFusionSphericityThreshold 只在设置捕获与校准编码边界保留；底层编码要求显式提供。
高/中/低预设及默认历史字节已固定，不能重做迁移、删除兼容键或放宽上下文匹配。
整个 Domain 的 24 个源文件已独立编译为 iOS 16/Swift 5 模块；
tools/validate_fusion_domain.sh 是当前门禁，不能把 App/Core/UI 来源加入它来掩盖依赖。
脚本递归发现整个源树，包括隐藏/忽略路径中的 Swift 文件；不维护绕过依赖的子集清单。
结果、质量、诊断值与冻结身份已经纳入；生产仍使用原 App/XCTest target。
独立编译不代替并发、证据准入、UI 或物理设备验收。
ReliableYieldEvidence 构造权限仍须受限。
多果实不同尺寸/置信度、重叠异类干扰现已通过冻结—估算—存档—批量导出回放，
显式质量来源缺失/耗尽不得借用附近候选，重复来源/候选 ID 不得放大质量。
质量关联已移除每果实的三组中间数组，仍按原顺序单次遍历，保留等距 UUID 决胜与
旧空间入口严格小于 10 cm 的回退，不重复此项重构或声称已测得性能提升。
CandidateCombiner 已迁入 Domain/Fusion，比较直接使用轨迹几何值；原最近匹配、
等距顺序、权重、阈值、采样上限和混合点云标记有固定回归，仅最终输出创建候选。
不重复此项迁移。CandidateMatcher 已只持有运行/实验配置，评分和拒绝检查均在领域层；
FusionValidationPolicy 仅接收实际使用的值，FusionAssignment 已按原文迁移。
保持 checked Sendable、匹配优先级、可靠深度拒绝、置信度公式与 legacy 缓冲适配。
点云与 ROI 混合几何、必须重分配才能保留两枚果实的完整回放也已完成。
混合场景固定 48.61230659 g 椭球质量和 0.131231352 kg 最终产量；
重分配场景固定左侧置信度 0.85、右侧 0.9 和 0.168232287 kg 可见质量。
这些合成基线不得用当前输出更新，也不能代替物理 LiDAR 验收。
FruitCategory.swift 保存编码和物理先验，FruitCategoryPresentation 保留原名称，
FruitCategoryVerification 只接收标量/Observation，legacy 适配不采样深度。
颜色与实验配置迁移按原文字节核对，不重复上述迁移。

ScanPlan 的五类外部值依赖已收敛：RendererScanSettings、FruitVarietyParams、Season、
YieldCalibrationCorrection 和 YieldAlgorithmRevision 均在 Domain。
渲染设置的 MainActor 捕获留在 Application/RendererScanSettingsCapture；
参数存储主体未变，displayName 留在 Core/FruitCategoryPresentation。
三个质量预设的捕获、深度/体素边界、设置变化后的冻结及参数固定 JSON 夹具已验证。
不重复这些迁移，保留品类参数 Codable 字段/ID、资源上限、相机请求、校准身份及历史字节。
YieldResult、ScanYieldDiagnostics 和 FruitMassEstimate 已按原字段/默认值归入 Domain；
ScanEvidenceIdentity/ScanEstimate 依赖已闭合，相关结果、质量和身份原文字节有核对记录。
shortStatus 无消费者已删除；FruitInfo 仅供旧研究测试，已隔离至 LegacyYieldEstimator。
不重复这些迁移，不恢复未使用辅助代码，保留 schema、摘要和可靠证据构造权限。
第 27 轮已将 Domain 门禁接入 .github/workflows/build-ipa.yml，
增加 main PR 和工具变更触发；rg/find 两条路径均实际编译成功且拒绝隐藏反向依赖。
CI helper 保留编译退出码、限制报告行数；报告失败和 Xcode 选择失败有修正后夹具。
PR #10/#11/#12 的远程 CI 已实测通过并合并，覆盖第 1–31 轮。不重做该集成，不冒充 XCTest 或 IPA 签名；第 32–35 轮按本次用户要求准备提交、推送及合并，状态见最新交付检查点。
第 28 轮已修复最近记录默认 0 被呈现为可靠结果的问题，第 29 轮已移除 UI 过时临时目录检查，由导出服务统一判断所有权。第 30 轮在实际 SwiftUI sheet 边界声明深色方案，修复固定深色背景上的黑色标题与分组文字；浅色系统入口有失败回归与修复后证据。最新最终全量 1022 项通过；真实 UI 已核对三种批量产物与取消、收起、切换格式及页面关闭后的清理。不要重做这些修复或把合成夹具当真实精度证据。
完整历史读取、校准未校准基线导入和删除确认/取消已有证据；永久删除尚待用户确认，物理验收仍缺操作者采集。下一步在已确认授权后完成隔离模拟器 UI-FIXTURE-B 的删除，检查关联文件与历史刷新并保护其他夹具。未收到确认时保留该记录；继续补充真实设备采集条件、人工果数及资源测量，不制造无关重构来代替尚缺的证据。
第 31–34 轮已贯通仓储历史查询/删除、生产完成刷新、工作台/历史/批量列表、导入、校准扫描来源和预览。
第 34 轮关闭/返回原生走查已补齐，第 35 轮报告与趋势根历史装配和最终 1022 项全量已完成。
第 35 轮原生点击因 Mac 再次锁定尚待补齐；下一项为地图/历史对比，见第 35 轮提示词。
保护真实数据，不新增闲置生产测试路径。
完成/重试已有代码回归；单独说明模拟器无 LiDAR 的 UI 范围与尚缺的物理证据。
Domain 仍使用模块内访问；framework/package 需另行定义公开 API 并迁移消费者。
按原蓝图维持当前单 App target，保持模型/shader 归属，评估正式模块的实际收益。
继续核对完成/重试、完整历史记录、批量导出及校准导入 UI，分别报告证据层级。
期望值不能通过调用被测算法动态生成。保持自定义配置、入队帧配置
不漂移和校准隔离的回归；不能降低可靠深度与 confidenceMap 的底线。

不要重做已经完成的冻结绑定、仓储注入和研究 JSON codec 迁移；
保留跨扫描/计划/观测/源拒绝、原绑定重试和 legacy 活跃草稿保护测试。
保留 .fused 唯一可靠来源、拒绝原因、诊断、阈值与旧 schema 1–3 字节兼容。
manifest.scanID 仍是历史文件基名，不能偷换为逻辑 ScanID。

保持研究 JSON 的未知诊断字段、旧记录兼容、字节摘要及批量导出前后验证；
避免为类型化新增多轮大 JSON 序列化或复制。阶段通过后继续底层职责收敛与回放。
每阶段更新执行记录和下一轮构思，不以局部通过代替整个目标完成。
保留其他未提交改动，使用项目指定 iOS 模拟器；高风险阶段跑全量和 Release。
真机 LiDAR 验收单独报告，最终给出 mergeable / needs changes / do not merge。
```

整体重构仍有上述必需实施和验收范围，整体决策为 **needs changes**，尚不宣告整个目标完成。
