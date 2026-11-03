# 重构迭代执行记录

创建：2026-09-27；更新：2026-10-06。初始分支：`codex/scan-architecture-refactor`，基于 `81f49a6ec3d5` 及已有未提交迁移继续实施；后续分支与交付见各轮记录。

用户目标：进行重构，完成后继续构思下一轮并迭代。当前目标保持进行中；本文件区分已实施、待验证与下一轮范围，不把整个架构迁移宣称为已完成。

最新检查点（2026-10-13）：第 71 轮修复历史刷新动作的归属与捕获边界。刷新只属于纵向记录列表，并直接捕获同一 history store；保留唯一加载 owner、取消和代次保护。新增真实生产 sheet 的悬挂加载回归，原实现失败，最终定向 1/1 与 full 1196/1196、59 类、Domain 45 源、Release 均通过，原 1195 方法保留、编译告警集合及两条旧 QoS 保持。同一最终源码回放 fixture 1 / 原生 2 / golden 1 通过；309 文件身份 `897a49c36f4a80c07945a3c6592240693297abc1c7800a6d8e4a8ec699e85907` 与 Debug/Release/回放/实际安装主程序及代码 dylib 核对一致。用户确认第一次直接下拉出现读取失败；代理取图时已回首页，后续失败截图明确来自同会话重开历史页。目录可逆修复后，用户确认第二次同页直接下拉清除横幅、仍有 2 条记录；代理随即核对恢复现场，两条 Result Complete 及 7 fruits/1.2 kg、2 fruits/0.5 kg 保持，十六原件及外部备份 SHA 相同。原生恢复门槛完成，最终独立复审另记。全部删除、多记录失败子集的原生验收、其他本机门禁、真机输入/资源/精度、最低系统及 Git 交付仍开放；未暂存、提交、推送或合并。下文历史百分比不作为当前量化进度，整体仍 needs changes / active。

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

上述源码提交及文档提交 `40951e29` 已通过 [PR #13](https://github.com/Hkai29/FruitTreeScanner/pull/13) 推送并于 2026-10-02 04:40:35 UTC 合并，合并提交 `76e15a99a9daff5feddd0dea22699e1268bd878b`。[远程 CI 36965233999](https://github.com/Hkai29/FruitTreeScanner/actions/runs/36965233999) 成功：Xcode 16.4 实际独立编译 Domain 24 源，iOS 16/Swift 5，并确认模拟器编译退出 0；没有远程 XCTest 或签名 IPA。远端 main 包含两个提交且合并树与受测提交树相同；原有六项改动保持。发布证据为 `/private/tmp/fruit-iteration35/merge-result.json`，未把合并写成原生点击或物理验收完成。

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

## 第三十六轮：历史对比接入根历史并加载冷入口

根因：`HistoricalCompareView` 固定观察共享历史，工作台的对比路由没有传入根实例，页面也没有入口加载。新回归使用唯一临时目录的四份 PLY，直接构造工作台生产 sheet 工厂；修复前冷历史始终没有加载，**1 项失败、退出 65**。Xcode 在失败后另有诊断收集 `simctl` 不可用（72）日志，结果树仍明确记录此方法的断言失败；该额外日志保留，不把诊断错误写成产品根因。

- 比较页接收根历史，工作台传入同一实例，并在出现时请求原有后台加载。默认构造兼容保留，没有新增生产服务或修改比较数据模型。
- 新方法激活实际无障碍选择控件，打开两次真实选择器并返回；完整零记录可选，原始和损坏记录排除，另一槽位的记录不可再次选择。零基线仍显示变化不可用，根刷新将 0→1.5 kg、与 3.0 kg 的比较更新为固定期望 +100.0%。
- 仅移除测试拥有的 B companion 后进入一条完整记录空态；重新生成该 companion 后 A 选择保持、B 仍未选择，不恢复失效前的旧选择。最后只有 incomplete/invalid 时显示零条完整记录空态，四份 PLY 字节始终保持。没有执行产品永久删除。
- 新方法与原有七项完整准入、未知值、零基线、刷新、清理及重复选择回归 **8 项通过，退出 0**。八张入口、选择器、零值、刷新、清理和空态附件逐张复核；390 pt 夹具中原有日期/单位和百分号换行保留，不称为 UI 布局重做或全部设备验收。
- 最后源码修改后 `storage ui full` 为 **1023 项通过、0 失败/跳过/预期失败，59 个类，9 步全部退出 0**；Domain 24 源及 unsigned Release 模拟器构建成功，开始/结束快照一致。结果树逐项确认上述八个方法 Passed。两条既有内部 QoS 警告保留，没有真机性能结论。
- 最终受测 Debug App 安装到专用模拟器，11 份档案/校准文件摘要保持。安装后再次尝试原生走查，Mac 仍锁定，工具无法访问窗口；第 35/36 轮工作台原生点击尚未完成，真实 SwiftUI 工厂与控件测试单独记录。

证据在 `/private/tmp/fruit-iteration36/`：`task-card.md`、`before.xcresult` / `before-summary.json` / `before-tree.json`、`after.xcresult` / `after-tree.json`、`attachments/`、`fruit-code-improvement-jlizdi4n/report.json` / `test-tree.log`、`critical-methods.json` 和 `ui-install-preservation.json`。独立复审确认两个生产改动的根装配、观察生命周期和后台加载，以及现有比较公式、选择策略和默认 API；六项原有改动保持，未发现代码阻塞问题。代码与已执行模拟器范围 **mergeable**，本轮没有提交或推送；原生操作、地图/设置消费者与物理验收使整体仍为 **needs changes**。本目标回合分类为 progress，不是仅重复锁定状态，也未到无法继续实施的 blocked 条件。

### 下一轮构思与提示词：地图的根来源和选中记录刷新

实际调用链为 `Dashboard → MapSheet → OrchardMapView → OrchardMapData`。中间包装没有传入根，地图固定观察 shared；数据模型按每树最新带定位完整记录聚合。页面持有 `selectedTree` 值，历史变化目前只重设地图范围；选中详情是否保持旧值必须通过下一轮回归判定，不能仅凭静态代码宣称已复现。地图仍需保持 iOS 17 条件、GPS/完整准入、树聚合、相机范围、原有产量等级和选择/筛选语义。

```text
继续 FruitTreeScanner 的整体架构重构，先读取 AGENTS.md 和本记录并 preflight。
第 1–35 轮已通过 PR #10–13 合并；第 36 轮历史对比根装配与真实选择控件回归已完成，
最终全量 1023 项通过，改动仍在本地。保护六项原有工作流 dirty work，不自动提交或推送。
Mac 锁定时不重复无效点击；解锁后补第 35/36 轮报告、趋势和对比的原生入口及关闭。
先追踪 Dashboard → MapSheet → OrchardMapView → OrchardMapData 和选中详情的真实数据链。
对隔离冷根建立失败回归，传递同一根历史，保留默认 API、iOS 17 条件与现有后台加载。
核对完整带定位记录准入、同树最新记录与可靠零值，损坏/incomplete/无定位记录不能进入地图。
通过实际标记选择和根刷新验证详情是否更新，记录失效或筛选后是否清理选择；
仅在真实失败证明根因后修复选中值生命周期，不改变 TreeAnnotation 身份或静默更改聚合规则。
保留坐标、相机范围、产量等级阈值、融合/校准/schema/摘要和全部采样限制。
运行相关定向及 storage ui full；最后源码修改后核对结果树、快照、附件和独立差异审查。
专用模拟器 11 份档案/校准文件保持；永久删除仍需要对应确认，真机采集和资源测量单独验收。
完成后核对 SettingsView 与根 settings 的真实消费者，制定下一轮；不要引入未使用抽象。
```

## 第三十七轮：地图根历史与选中详情的单一来源

根因由两个独立失败阶段证明。真实 `Dashboard → MapSheet → OrchardMapView` 入口在隔离冷根下没有加载六条历史，`before-repaired.xcresult` 为 **1 项失败、退出 65**。只接入根历史后，实际 MapKit 标记可选择，根记录也已刷新为 1.5 kg／6 个，但详情仍显示原来的 0.0 kg／0 个；`root-after-proven.xcresult` 再次 **1 项失败、退出 65**。最早 `before.xcresult` 的测试括号编译错误已修正并保留，不能把它算作产品失败回归。

- 工作台、地图包装和地图页传入同一个历史实例，保留默认构造兼容和原有后台入口加载。
- 页面仅保存选中记录 ID，由当前筛选后的根历史生成详情。MapKit 的 `TreeAnnotation` tag、ID/hash、坐标、同树最新完整记录规则和相机范围策略未变。历史失效或筛选排除选中记录时清除 ID；解除筛选或恢复完整记录不会恢复旧选择。
- 回归操作真实生产 MapKit annotation 的公共选择控制，并激活实际筛选控件；覆盖最新完整零值、旧同树记录回退、根刷新、筛选清理、记录失效、恢复后不重选和 incomplete-only 空态。六份测试自有 PLY 字节保持，未操作用户永久删除。
- 最后测试修改加强等待条件，直接检查实际地图标记、筛选按钮和 MapKit 当前选择，不以不变的总树数代替筛选完成。新方法及七项原有地图准入、定位、聚合、零值和筛选方法 **8 项通过，退出 0**。最终七张附件逐张核对，详情确实从 0.0 kg／0 个更新为 1.5 kg／6 个；390 pt 原有摘要单位换行和详情日期挤排仍存在。地图背景有未加载瓦片/网格，不能据此声称完整底图或网络性能验收。
- 最后源码/测试修改后的 `storage ui full` 为 **1024 项通过，0 失败/跳过/预期失败，59 个类，9 步全部退出 0**；Domain 24 源和 unsigned Release 模拟器构建成功，开始/结束快照一致。结果树逐项确认上述八个方法及第 36 轮真实对比方法 Passed。两条既有内部 QoS 警告和非阻塞 `IOSurfaceClientSetSurfaceNotify` 日志保留，不作真机性能结论。
- 最终受测 Debug App 安装到专用模拟器。安装前后及原生操作后，11 份档案/校准文件 SHA-256 和扫描目录文件集合完全保持。第 36 轮源码与回归内容逐字保持，六项原有工作流 dirty work 保持，暂存区为空。

Mac 本轮已可操作，使用 CUA 在 Device Hub 的专用模拟器补实际入口。历史页完整/待恢复/损坏状态及关闭返回成功；趋势页显示完整 A/B（1.2／2.7 kg、7／11 个），关闭返回成功；地图页在原有 GPS 均为零的夹具下显示无定位空态，关闭返回成功。对比选择器仅列完整记录，第二槽位排除已选 A，实际比较 A/B 显示 1.2／2.7 kg、7／11 个、未知直径不可用。文件原值 A=1.234567、B=2.7，对应显示 +118.7%，没有按一位小数展示值重算期望。对比页没有显式关闭控件，两次下拉尝试未验证返回；这是待调查的原生导航风险，尚不能分辨产品行为与 Device Hub 手势转发限制。报告页本轮未补走查；不能继续把全部原生入口写成通过，也不再把当前缺口全部归因于 Mac 锁定。地图带 GPS 标记选择/刷新证据来自生产控件 XCTest，单独于上述原生空态入口记录。

证据在 `/private/tmp/fruit-iteration37/`：`task-card.md`、`before-repaired-summary.json` / `before-repaired-tree.json`、`root-after-proven-summary.json` / `root-after-proven-tree.json`、`after-final.xcresult` / `after-final-tree.json`、`attachments-final/`、`fruit-code-improvement-pi77w0zy/report.json` / `test-tree.log`、`critical-methods.json`、`ui-install-preservation.json`、`ui-validation.json` 和 `final-review.json`。独立只读复审确认根装配、观察生命周期、默认 API、MapKit tag 与当前历史/筛选对齐；没有源码阻塞发现。保留融合准入、拒绝诊断、阈值、schema、摘要、校准身份及采样限制。地图代码与已执行模拟器范围 **mergeable**；第 36–37 轮仍未提交/推送。原生导航、设置消费者、窄屏展示和物理验收使整体仍为 **needs changes**。本回合有实际实现、失败证明、验证和原生进展，目标保持 active。

### 下一轮构思与提示词：对比返回与设置消费者

```text
继续 FruitTreeScanner 整体架构重构。先读 AGENTS.md、本记录并 preflight。
第 1–35 轮已通过 PR #10–13 合并；第 36–37 轮对比/地图根装配已完成，
最新全量 1024 项通过，改动仍在本地，不自动提交/推送。
保护六项原有 dirty work、第 36–37 轮内容和专用模拟器 11 份档案。
先调查对比页返回：原生入口及两次实际选择成功，但页面无显式关闭控件，
Device Hub 下拉未验证返回。检查真实 Dashboard sheet 呈现、dismiss 与
destination 生命周期，建立真实呈现下的关闭/返回回归；区分工具手势限制与产品缺口。
若确认缺陷，采用现有设计系统的最小关闭控件，验证返回根页面和再次打开；
不重做比较公式、筛选、选择 reconciliation 或整个 UI。
补报告原生入口及关闭；趋势、地图空态和历史关闭本轮已有实际证据。
地图带 GPS 标记刷新已有生产 MapKit 控件回归，不重复这项修复；
保留 selectedTreeID 单一状态、TreeAnnotation ID/hash、完整/GPS 聚合、坐标和相机规则。
随后追踪 AppDependencies.settings → Dashboard 设置路由 → SettingsView →
CameraSettingsView（以及品种入口的实际消费者），当前这些视图仍固定 shared。
先在真实生产装配和隔离 UserDefaults 下建立失败回归，再传递同一根设置。
保留 sliders 草稿/提交时机、设置正规化、相机规格、冻结 ScanPlan 与校准隔离；
不把品种参数/校准存储错误并入 settings，不引入闲置抽象或测试专用产品路由。
最后改动后运行对应配置/UI定向及必要全量/Release，核对逐方法结果树、
快照、实际附件与独立差异审查；原生操作和真机证据分别记录。
390 pt 地图摘要/日期和对比日期存在既有挤排，列入单独展示修复，勿称为已验收。
保持 .fused、拒绝原因、schema 1–3、摘要和校准身份；永久删除仍需对应确认。
物理 LiDAR 采集、人工果数和资源测量仍需独立验收。更新下一轮构思，不宣告整体完成。
```

## 第三十八轮：对比页关闭边界与实际返回

第 37 轮原生走查发现对比页没有显式关闭控件；Device Hub 下拉没有验证返回。本轮通过真实 `Dashboard` 的生产 QuickAction 呈现 sheet，确认缺口是 `HistoricalCompareView` 没有自己的导航容器和 dismiss 动作。`before.xcresult` 的新回归实际呈现成功后，在可见关闭控件断言处 **1 项失败、退出 65**；不能把此前的手势转发限制、xcresult 读取权限或 Xcode 失败诊断中的 simctl 错误算作产品回归。

- 对比页自己拥有 `NavigationStack`，在原设计系统导航栏中增加已有 `common.done` 的“完成”按钮，由当前 sheet 的 `dismiss` 返回。中英文资源已有“完成”／“Done”，没有新增文案或改动翻译文件。嵌套选择器保留自己的取消和选择动作。
- 原 `ZStack` 比较内容、选择策略、计算与其后全部辅助方法同 HEAD 逐字核对保持。第 36 轮根历史注入、后台入口加载、选择 reconciliation 及空态开始扫描回调保持；第 37 轮地图、包装和路由三个文件及此前回归内容的 SHA-256 保持。
- 新回归挂载真实工作台和根依赖，激活生产入口，在两条完整记录和少于两条完整记录时，分别验证关闭返回、再次打开和窗口恢复。变更完整性的操作仅移除并恢复 UUID 临时目录内测试自有元数据，最终四份源文件字节保持；没有操作专用模拟器的删除或修改产品测试路由。
- 最后源码/测试修改后的定向验证为 **9 项通过、退出 0**，全量 `ui full` 为 **1025 项通过，0 失败/跳过/预期失败，59 个类、9 步全部退出 0**。Domain 24 源检查和 unsigned Release 模拟器构建成功，验证开始/结束快照一致。结果树逐项确认定向九个方法，以及全量中的第 37 轮地图真实入口方法均 Passed。
- 定向十二张附件已逐张核对：新回归完整页／返回根页面／少于两条记录空态／再次返回四张，加上第 36 轮实际选择器、零值、刷新、失效清理和空态八张。新增关闭控件在完整页和空态均可见；390 pt 原有日期挤排及部分单位换行仍存在，没有宣称整个展示已验收。

最终受测 Debug App 安装到专用模拟器后，通过 CUA 在 Device Hub 及其独立预览窗口操作实际入口：对比页“完成”返回工作台，重新打开成功；第一选择器取消只关闭选择器，对比页仍保持；选中完整 A 后，第二选择器仅显示 B。最终 A/B 比较显示 **1.2／2.7 kg、7／11 个、+118.7%** 和未知直径不可用，结果页“完成”实际返回工作台。固定文件原值为 A=1.234567、B=2.7，变化率没有按展示值重算。第 35/37 轮仍缺的报告入口和关闭也已补齐：实际报告仅统计两条完整记录，显示总产量 **3.9 kg**、平均 **2.0 kg**、共 **18 个**，关闭返回工作台。

原生操作期间 Device Hub 滚轮/拖动多次没有移动或产生大幅惯性滚动，切换独立预览窗口后从实际可见入口完成走查；一次 `noWindowsAvailable` 刷新应用和截图后重试关闭，最终确实返回。保留这些工具限制，不据此改写产品手势规则。专用模拟器始终有两条完整记录，少于两条记录的关闭/重新打开证据来自测试自有档案的生产控件 XCTest，不能写成原生 CUA 空态走查。GPS 地图标记选择/刷新同样保留第 37 轮 XCTest 证据层级。最终恢复 Device Hub 窗口，专用模拟器选中，键盘捕获关闭、缩放 Fit、工作台可见。

安装前后及本轮原生走查后，专用模拟器 **11 份档案/校准文件 SHA-256 和扫描目录文件集合完全一致**；没有永久删除、偏好或校准写入。融合准入、`.fused` 唯一可靠来源、拒绝原因、诊断、阈值、schema 1–3、摘要、校准身份和采样限制均未改动。六项原有工作流 dirty work 保持，暂存区为空。最终受测五个生产/测试文件与当前内容一致；验证后仅更新本执行记录。

证据在 `/private/tmp/fruit-iteration38/`：`task-card.md`、`before.xcresult` / `before-summary.json` / `before-tree.json`、`after.xcresult` / `after-summary.json` / `after-tree.json`、`attachments-after/`、`fruit-code-improvement-79k32971/report.json` / `test-tree.log`、`critical-methods.json`、`ui-install-preservation.json`、`ui-validation.json` 和 `final-review.json`。独立只读复审没有新增关闭边界的阻塞发现。新方法没有内部 QoS 警告，全量两条既有警告分别来自两个点云入口/关闭方法；既有异步 RunLoop 的 Swift 6 兼容警告、XCTest framework iOS 17 与 App 最低 iOS 16 提示及非阻塞 IOSurface 日志保留，不能声称真机性能和最低版本运行验收。

本轮代码与已执行模拟器范围 **mergeable**；第 36–38 轮仍在本地、未提交/推送。PR #13 已交付第 32–35 轮，不把其合并状态套用到之后的改动。设置消费者、窄屏展示和物理 LiDAR／人工果数／资源验收使整体仍为 **needs changes**。本回合有失败证明、实现、最终验证、复审和原生导航闭合，目标保持 active。

### 下一轮构思与提示词：设置到扫描计划的同一根配置

现有 `AppDependencies` 已将根 `settings` 传给 `ScanPlanFactory`；工作台设置路由仍创建 `SettingsView()`，设置页、嵌套 `CameraSettingsView` 以及 `VarietyDatabaseView` 的当前品类读取仍固定 `SettingsStore.shared`。这是下一处需要实际装配失败证据的候选，尚未实施。品种参数数据库本身由 `FruitParametersStore` 管理，不能将其或校准存储合并进 SettingsStore。

```text
继续 FruitTreeScanner 整体架构重构，先读 AGENTS.md、本记录并 preflight。
第 1–35 轮已通过 PR #10–13 合并；第 36–38 轮在本地、未提交/推送，
最新全量 1025 项通过。保护六项原有工作流 dirty work 和专用模拟器 11 份档案。
第 36–37 轮对比/地图根装配与选择生命周期，第 38 轮对比关闭/重开及
报告实际入口/返回已完成，不重复修复或把原生报告走查写成仍待补齐。
追踪 AppDependencies.settings → Dashboard 实际设置 sheet → SettingsView →
CameraSettingsView，以及 VarietyDatabaseView 当前品类的 settings 消费者；
对照 ScanPlanFactory、Renderer 预览和新计划的根配置捕获。
用隔离 UserDefaults、测试自有历史目录和真实挂载的 Dashboard 建立行为失败回归。
必须先挂载 .environmentObject(root) 再操作设置入口，避免在环境未解析时
直接调用 sheetView 造成假失败。固定根设置与 shared 不同的值，验证实际显示、
实际控件修改写入同一根、关闭/重新打开持久化与新 ScanPlan 捕获；不写标准偏好。
只在真实失败证明后传递同一根 SettingsStore，保留默认构造兼容和观察生命周期。
保留 slider 草稿、结束拖动/离开页面提交、舍入和 setIfChanged、质量预设、
相机规格正规化、品类归一及当前 ScanPlan 不随之后设置修改而漂移的既有回归。
品种页当前品类与根一致，但 FruitParametersStore 的参数/ID/Codable/编辑职责
及校准身份仍独立；不合并存储、不引入闲置抽象或测试专用产品入口。
在最后源码/测试修改后运行配置/UI 定向和必要全量/Release，逐方法核对结果树、
快照、实际附件和独立差异审查；源文件与六项 dirty work 的保护分别核验。
原生只在隔离偏好可恢复且不改用户数据时补走查，并区分 XCTest、CUA 和物理设备证据。
390 pt 地图/对比日期及单位挤排列入后续独立展示修复，不混入本轮设置装配。
保持 .fused、可靠深度和 confidenceMap 拒绝、诊断、schema 1–3、摘要及全部资源上限。
物理 LiDAR 采集、人工果数、30/60/120 秒资源测量仍需独立验收；
永久删除仍需对应确认。完成一轮后更新构思与下一步提示词，不宣告整体完成。
```

## 第三十九轮：设置消费者与冻结计划共用根配置

真实挂载 `Dashboard` 并注入独立 `AppDependencies.settings` 后，设置路由及两层子页仍分别读取 `SettingsStore.shared`。先后保留三阶段产品失败：`before-proven.xcresult` 显示苹果而根配置为梨；只修复设置入口后的 `root-after.xcresult` 相机仍显示 1080p/60fps，而根请求为 4K/120fps；相机修复后的 `camera-navigation-fixed.xcresult` 品种页当前品类仍与根不符。三次均为新方法 1 项失败、退出 65。早期滚动定位、iOS 27 重复 Picker 标签、不存在的本地化常量、系统菜单/返回 accessibility 激活和导航过渡时机等测试工具失败分别保留，不能计为产品缺陷。

- Dashboard 从已有根依赖提供 `settingsStore`，生产设置路由传递同一对象；`SettingsView`、`CameraSettingsView` 和 `VarietyDatabaseView` 的当前品类观察同一 `SettingsStore`。默认构造仍兼容，品种参数继续由独立的 `FruitParametersStore` 管理。
- 页面内容、slider 草稿与结束拖动/离开提交、舍入、setIfChanged、相机规格正规化及品种编辑/重置实现保持。没有改动融合准入、阈值、拒绝原因、诊断、schema 1–3、摘要、校准身份或采样限制。
- 新回归使用 UUID 隔离偏好与空历史目录、真实工作台入口和实际生产控件。点数从 140 万草稿变为 150 万，拖动结束前根保持旧值；精度从 1.7 cm 草稿变为 1.8 cm，导航离开后提交。实际 toggle、相机菜单动作和品种“使用”写入同一根；返回、关闭/重开及重新读取隔离偏好保持新值。
- 菜单动作采用 UIKit 公共 `UIButton.sendAction(UIAction)`，返回使用真实导航控制器的公共 pop API；没有私有 API 或测试专用生产入口。这些属于集成 XCTest 控件证据。原冻结 ScanPlan 仍保留原品类、相机、CSV 与点数，新计划捕获更新值；尚未证明 Start/QuickScan 全链路品类提交，留给下一轮。
- 最后源码/测试改动后的定向 **14 项通过**；全量 `ui full` **1026 项通过、0 失败/跳过/预期失败、59 个测试类、9 步全部退出 0**，Domain 24 源检查及 unsigned Release 模拟器构建成功。开始/结束快照完全一致，14 个定向及 17 个全量关键方法逐项 Passed，包含此前比较关闭、历史刷新和地图选择回归。
- 七张定向 PNG 与对应 accessibility 文本已逐张核对。菜单阶段的 XCTest PNG 尚未显示弹出菜单，不能据此宣称选项视觉验收；其控件动作有结果断言，实际原生菜单另行验证。390 pt 品种条目既有换行及地图/比较日期、单位挤排没有在本轮重写。

最终受测 Debug App 安装到专用 iOS 27 模拟器，通过 CUA 操作实际设置入口：原配置苹果、CSV 关闭、高质量和 100 万点保持；相机显示 1080p/60fps，分辨率菜单实际显示 720p、选中的 1080p、4K，帧率菜单显示 30、选中的 60、120。两菜单点外部取消；实际返回回到设置，品种页显示当前苹果、自定义 0 和原参数，未选择使用/编辑/重置。品种返回、设置“完成”返回工作台、再次打开及再次关闭均已核对。最终恢复完整 Device Hub，专用模拟器选中、键盘捕获关闭、缩放 Fit、工作台可见。

安装前后和原生走查后 **11 份档案/校准文件 SHA-256、扫描文件集合及 21 项保护设置的值/缺失状态一致**。六项原有工作流 dirty work 未改动；第 36–38 轮生产文件及此前测试内容保持。最终受测生产/测试源码与当前一致，之后仅更新文档。全量两条内部 QoS 提示、既有异步 RunLoop 兼容提示、XCTest framework 最低版本提示及 IOSurface 日志保留；未以测试通过代替性能或最低 iOS 16 运行验收。

证据位于 `/private/tmp/fruit-iteration39/`：三阶段失败结果、`after-final.xcresult` / summary / tree、`attachments-after-final/`、`fruit-code-improvement-pmkxk4s6/report.json`、`critical-methods.json`、`ui-install-preservation.json`、`ui-validation.json` 和 `final-review.json`。单独只读复审没有交付范围内的阻塞发现。本批代码 **mergeable**；整体目标因启动/不匹配品类消费者、窄屏展示和物理验收仍为 **needs changes**。本次用户明确要求推送并合并，交付范围为第 36–39 轮；第 32–35 轮此前已由 PR #13 合并。

### 下一轮构思与提示词：启动与品类不匹配的根配置边界

实际消费者仍包括 `StartView`、`QuickScanView` 的品类草稿初始化与 deliver 对 shared 的写入，以及 `ScanView` 品类不匹配停止/切换动作的 shared 写入。下一轮应先验证真实根装配下的失败，保留用户选择草稿与已创建请求/计划的冻结语义。

```text
继续 FruitTreeScanner 重构，读取 AGENTS.md、本记录并 preflight。
第 36–39 轮历史/地图/比较关闭及设置根消费者已完成，最新全量 1026 项通过；
先核对实际 Git/PR 状态，保护六项原有工作流 dirty work、专用模拟器档案和设置。
追踪 Dashboard 的实际 fullScreenCover → StartView/QuickScanView →
ScanLaunchRequest → ScanPlanFactory，以及 ScanView 品类不匹配停止/切换动作。
用隔离 UserDefaults、测试自有目录和实际挂载环境的 Dashboard 先建立失败回归；
不能在环境未解析时直接调用依赖环境对象的路由，也不新增产品测试入口。
证明初始品类读取同一根，实际选择/确认写入该根，标准偏好保持原值。
保留每次页面创建后的选择草稿；后续根变动不能改写用户草稿、旧请求或旧 ScanPlan。
只修复有失败证明的消费者；保持默认构造兼容，品种参数与校准存储仍独立。
保留 launchGate 恰好一次提交、快速双击、取消/重启和扫描 identity/epoch 边界；
不匹配切换须针对实际当前扫描动作建立回归，不能通过放宽融合规则消除提示。
最后修改后运行配置、启动、生命周期/UI 定向和必要 full/Release，逐方法核对结果树、
快照及附件，单独审查差异；原生导航、XCTest 控件和物理设备证据分别说明。
保持 .fused 唯一可靠来源、深度/confidenceMap 拒绝、诊断、schema、摘要及资源上限。
窄屏日期/单位展示另轮处理；物理 LiDAR、人工果数和 30/60/120 秒资源验收仍缺。
更新下一轮构思，不以一轮完成宣告整体目标完成；提交/推送按当前明确授权执行。
```

## 第四十轮：启动品类与不匹配动作的根配置和扫描边界

2026-10-03 自动目标续轮。第 36–39 轮已通过 [PR #14](https://github.com/Hkai29/FruitTreeScanner/pull/14) 推送并合并，远端状态重新核实为 MERGED，合并提交 `196c5f73724836b316c934a6a16d1a3bc4cebd5d`。本轮基线 HEAD `5d977e59` 的文件树与该合并提交一致；第 40 轮仍是本地未提交、未推送改动。

实际 Dashboard 根装配下，Start/QuickScan 品类草稿及提交仍使用 shared 配置；ScanView 不匹配停止/切换也写 shared。`before-proven.xcresult` 中两条启动路由显示苹果而独立根为梨，`before-mismatch-proven.xcresult` 中实际 ScanView 绑定的停止/切换未更新根，均保留退出 65 的产品失败。早期控件定位、呈现层遍历、Picker 合并标签和单位测试上下文不能使用 XCUIApplication 等工具失败另列；最终测试没有这些无效调用，也没有私有 API 或新增生产测试入口。

- Dashboard 的真实 fullScreen 路由传递根 SettingsStore；StartView/QuickScanView 的默认构造兼容，每次创建从根初始化本地选择草稿，确认时按冻结请求写回该根。后续根变化不覆盖现有草稿、旧请求或 ScanPlan，launchGate 仍恰好一次提交。
- 不匹配提示由 ScanCategoryMismatchPresentationController 持有当前选择，绑定根设置及实际 cancelScan。选择凭证带 presentation ID、scan identity 与绑定 identity；继续仅清除选择，停止先消费凭证，再在提示/偏好发布前后核对绑定和扫描，离开释放绑定。UIKit 呈现 binding 已清空时，已捕获的有效动作仍可完成；旧动作、旧扫描、重绑定及同步重入不会取消替换后的扫描。
- `before-reentrant.xcresult` 证明偏好同步观察者替换扫描后旧动作仍会取消；`before-owner.xcresult` 证明同步重入会重复取消；`before-system-dismissal.xcresult` 证明只依赖呈现 binding 会丢失有效切换。修复后的专门回归覆盖这三类边界、同 scan ID 重绑定、凭证替换与释放。
- 首次全量执行 **1033 项，其中 1032 通过、1 失败**，暴露品种“使用”后返回设置仍显示旧梨的问题；`after-render.xcresult` 再次复现。SettingsView 移除重复品类 State，以观察根的 Binding 显示/写入；第 39 轮既有回归保持原断言，点数/精度草稿、舍入、拖动结束与离开提交保持。
- 新增 8 个回归方法。Dashboard 实际入口、取消/重开和根草稿用隔离偏好及空目录验证；独立实际 Start 五步与 QuickScan 控件选择葡萄、快速重复提交只交付一次，标准设置/参数/标签保持。实际 ScanView 装配回调、继续与停止意图验证当前计划、根切换、实际取消和关闭；没有运行 AR 采集或创建档案。
- 最后源码修改后定向 **22 项通过**；`lifecycle ui full` **1034 项通过、0 失败/跳过/预期失败、59 个测试类、9 步全部退出 0**。Domain 24 源检查与 unsigned Release 模拟器构建通过，验证开始/结束源码快照相同。22 个定向方法及全量 37 个关键方法逐项 Passed；当前 7 个生产文件和测试文件摘要与最终受测源码一致，随后只更新本记录。
- 26 张最终 PNG 及配对 accessibility 文本已检查。新启动截图等待 350ms 避免 AX 已更新但动画尚未绘制；早期过时截图保留。最终第一张 mismatch-continue PNG 仍是黑色背景，不能证明第一次提示的视觉呈现；第二张 mismatch-stop 显示完整消息及两个按钮，关闭截图显示测试宿主页。提示选择通过 controller 意图调用，继续后以 UIKit 公共 dismiss 模拟系统收起，**不能表述为已自动点击系统 Alert 按钮**。相机菜单阶段 PNG 未绘制菜单，不据此宣称选项视觉验收。既有 390pt 确认提示换行、可滚动 GPS 行及品种参数换行另轮处理。

最终受测 Debug App 安装到专用 iOS 27 模拟器。原生 CUA 走查实际工作台 → QuickScan，首次定位提示选择“不允许”；苹果、有效自动树编号、未锁定 GPS 提示及六类菜单已核对，菜单点外部取消。关闭/重开 QuickScan 后编号更新；新建扫描两次打开均为空编号、步骤 1/5、下一步禁用，取消返回工作台。最后恢复完整 Device Hub，选中专用模拟器、键盘捕获关闭、Fit 缩放、工作台可见。未在原生走查中提交扫描、改变品类或授权定位。

安装前后及走查后 **11 份档案/校准 SHA-256、扫描文件集合与本轮 25 项保护设置的值/缺失状态一致**。安装前有两项相对第 39 轮的既有差异：maxPointCount 已为 300 万、scanPrecision 已为 0.05，记录后使用本轮实际基线，未重置。六项原有工作流 dirty work 摘要不变；算法、`.fused` 唯一可靠来源、深度/confidenceMap 拒绝、诊断、阈值、schema 1–3、摘要、校准身份及资源限制保持。

证据位于 `/private/tmp/fruit-iteration40/`：产品失败结果、`after-reviewed.xcresult`、`attachments-after-reviewed/`、`fruit-code-improvement-x1r37xf2/report.json`、`critical-methods.json`、`render-review.json`、`native-preflight-drift.json`、`ui-install-preservation.json`、`native-final-preservation.json`、`ui-validation.json`、`final-source-preservation.json` 和 `final-review.json`。单独只读差异复审无本轮阻塞发现，代码 **mergeable**。既有 QoS/异步 RunLoop/XCTest 最低版本/IOSurface 提示仍保留，不据此宣称性能或最低 iOS 16 运行验收。

实际 Dashboard 提交仍会写 shared TagStore，本轮路由集成测试停在取消/重开，实际启动控件的请求交付另测，不能合称 Dashboard 提交全链路已验收。launchRescan 仍读取 shared 设置和分类。分类根所有权、窄屏展示及物理 30/60/120 秒采集、人工果数和资源测量仍待完成，整体为 **needs changes**，目标保持 active。

### 下一轮构思与提示词：分类根所有权及实际启动/重新扫描

```text
继续 FruitTreeScanner 重构，读取 AGENTS.md、本记录并 preflight。
第 40 轮启动/不匹配根配置及动作凭证已完成，最终全量 1034 项通过；
PR #14 已合并第 36–39 轮，第 40 轮本地未提交；先核对实际 Git/PR 状态。
保护六项原有工作流 dirty work、已受测第 40 轮、专用模拟器档案和实际设置。
追踪 AppDependencies → Dashboard activateScan/launchRescan → ScanLaunchRequest/ScanPlan，
以及 StartView 的地块/标签草稿、添加入口和 TagStore.shared 消费者。
根当前未持有 TagStore，activateScan 写 shared，launchRescan 读取 shared 设置/分类；
先建立隔离根下实际路由失败回归，再按证据引入必要根依赖，保留默认构造兼容。
测试使用自有偏好、目录与分类，不能提交到标准 TagStore 或改真实档案。
证明 actual fullScreen dismissal → 请求激活、新树、取消/重开及重复提交的行为，
保留已冻结请求/计划的水果、地块与标签，不让后续编辑或新根覆盖旧扫描。
保留 TagStore v1 snapshot、三项 legacy key、Codable ID/状态及失效地块/标签协调，
核对异步待保存、发布重入和绑定替换；不随注入迁移修改格式或丢弃恢复数据。
只修复有失败证据的消费者，保持单 App target 和模型/shader 归属。
最后源码改动后运行对应配置/分类/启动/生命周期/UI及必要 storage/full/Release，
逐项检查结果树和快照，单独复审差异，再进行保护数据的原生导航验收。
区分真实系统控件点击、XCTest 公共控件动作、controller 意图和物理设备证据。
保持 .fused、深度/confidenceMap 拒绝、诊断、阈值、schema、摘要、校准与资源上限。
窄屏展示和物理 LiDAR/人工果数/30/60/120 秒资源验收分别处理。
完成后更新下一轮构思；提交、推送和合并按当前明确授权执行。
```

## 第四十一轮：分类根所有权与实际启动、重新扫描

2026-10-03。基线包含已受测的第 40 轮及六项原有工作流 dirty work。PR #14 已合并第 36–39 轮；本次按用户“推送并合并”授权交付第 40–41 轮，第 40 轮源码提交 `06f36359`，第 41 轮源码提交 `afabc468`。前文“本地未提交”描述的是各轮结束时的历史状态，远端交付终态以本次 PR 为准。

实际 Dashboard 的 Start/TagManagement、activateScan 和 launchRescan 仍使用 shared 分类，导致独立根配置下读写另一套地块、标签和归属。`before-root-fixture.xcresult` 的两条实际路由读回归均失败；guard 在缺失根地块时停止，未继续写标准分类。迁移激活写入后，`before-rescan.xcresult` 又证明实际历史复扫读取 shared，清空了根 assignment 的地块/标签。早期测试的异步断言、夹具初始化、覆盖页面控件、光标位置和编辑器关闭时机问题单独保留，不归为产品回归。

- AppDependencies 持有 TagStore，保留 `.shared` 默认构造；Dashboard 传递同一根到 StartView、TagManagementView，activateScan 在该根写入并保留既有状态。TagStore 自身的校验、失效引用协调、异步保存、v1 snapshot 和三项 legacy key 未改动。
- 根 `rescanRequest(treeID:)` 先标准化并校验编号，再冻结根品类、地块和标签；不创建 assignment。每个请求拥有新 ID/GPS，后续根配置/分类编辑不改变旧请求或 ScanPlan。实际历史复扫及取消保持原 assignment ID、地块、标签、状态和原始 PLY 字节。
- 新增 5 个方法。实际 Dashboard → Start 五步中的添加地块、添加标签、选择、确认、source dismissal 后激活，QuickScan 激活、取消/重开，以及历史复扫均在自有偏好与目录中运行。快速重复控件激活结合原 launchGate 回归验证单次交付；assignment 数量为 1 本身不被当作保存调用次数计数。6 项标准偏好值/缺失状态及自有目录字节均核对。
- 测试遍历只读取最上层实际呈现页面，排除覆盖层保留的旧编辑控件，防止添加标签时编辑已关闭的地块字段。第 40 轮及更早方法的正文/断言保持；相关旧方法随本轮再次执行。
- 首次定向 47 项和全量 1039 项已通过，但渲染复审发现浅色入口下分类页白色行底与白色文字不可读。`before-management-appearance.xcresult` 在测试自有浅色窗口复现；分类页局部声明深色方案，系统 segmented control/行与既有深色背景一致，不改变全局或持久偏好。
- 最后源码修改后，定向 **47 项通过**；`storage lifecycle ui full` **1039 项通过、0 失败/跳过/预期失败、59 个测试类、9 步全部退出 0**。Domain 24 源检查与 unsigned Release 模拟器构建通过；开始/结束快照一致，11 个变更源码/测试文件仍与最终受测摘要一致。47 个定向方法及全量 62 个关键方法逐项 Passed。
- 最终 35 张 PNG、33 份 accessibility 附件均检查，加载根地块的深色行已可读。此轮 continue/stop 两张不匹配提示均实际绘制，但动作仍是 controller 意图调用加 UIKit 公共 dismiss，不能称为自动点击系统 Alert。相机菜单阶段未绘制选项；390pt 确认页换行和 AX5 保存按钮在截屏底缘之外仍保留证据限制。

最终 Debug App 安装到专用 iOS 27 模拟器。原生 CUA 核对工作台 → 地块标签 → 地块/标签/状态三个分页、实际添加标签表单的取消、状态空态 → 新建扫描的源页面关闭交接、空编号 1/5 与禁用下一步、取消、分类页重开复位及实际完成返回。滚动动画中的一次点击打开批量导出，只查看后关闭，未导出。未编辑分类、提交扫描、改变设置或授予定位权限；第 2 步及实际提交由隔离挂载的 XCTest 控件验证，不合称本轮原生验证。第 40 轮原生 QuickScan 证据仍单独保留。

安装前后及走查后 **11 份档案/校准 SHA-256、扫描文件集合及 25 项设置的值/缺失状态一致**。最终完整 Device Hub 选中专用模拟器，键盘捕获关闭、Fit 缩放、工作台顶部可见。六项原有工作流改动摘要不变且未包含在本次提交；算法、`.fused` 唯一可靠来源、深度/confidenceMap 拒绝、诊断、阈值、schema、摘要、校准身份和资源上限保持。

证据在 `/private/tmp/fruit-iteration41/`：产品失败结果、`after-final.xcresult`、`attachments-after-final/`、`fruit-code-improvement-pgumnfa6/report.json`、`critical-methods.json`、`render-review.json`、`native-final-preservation.json`、`ui-validation.json`、`final-source-preservation.json` 和 `final-review.json`。独立只读差异复审没有本轮阻塞发现，提交范围 **mergeable**。既有 QoS 等运行提示仍存在，无实测性能、最低 iOS 16 运行或物理 LiDAR 验收声明。

此轮完成启动/分类生产者及激活/复扫；历史筛选与复核写入、结果快速标记、批量导出分类名称仍有 shared 消费者。分类消费者迁移及物理 30/60/120 秒采集、人工果数和资源测量待完成，整体仍为 **needs changes**，目标保持 active。

### 下一轮构思与提示词：分类消费者的根装配

```text
继续 FruitTreeScanner 重构，读取 AGENTS.md、本记录并 preflight。
第 40–41 轮启动/不匹配根配置、分类生产者及 Dashboard 激活/复扫已完成；
最新全量 1039 项、定向 47 项与 Release 构建通过，先核对本次实际 Git/PR 终态。
保护六项原有工作流 dirty work、已受测源码、专用模拟器 11 份档案及 25 项实际设置。
追踪 Dashboard → HistorySheetView → ScanHistoryView 的地块/状态筛选及复核写入，
ScanView → ScanScannerInterfaceLayer → ScanResultLayer → ResultView → QuickTaggingCard，
以及 Dashboard → BatchExportView 的分类名称读取和导出映射。
先用隔离根、偏好和自有文件证明实际读取/写入失败；只迁移有证据的必要消费者。
不能在失败旧实现上继续写入标准 TagStore，也不能新增闲置产品测试路径。
逐个保留默认构造兼容，实际筛选、复核、结果保存和导出调用必须使用同一根。
TreeFilterView 当前未找到生产调用，先重新核对真实用途，不能虚构已接入的路径。
保持请求/计划冻结、归属 ID/状态、删除引用协调、TagStore v1/legacy keys 与待保存语义，
保持原始 PLY、结果/manifest 摘要及批量导出前后校验；不要随注入变更格式。
最后源码修改后运行分类/历史/结果/导出定向及必要 storage/lifecycle/ui/full/Release，
逐方法核对结果树、源码快照和渲染附件，独立复审，再完成保护数据的原生导航。
区分 CUA 系统操作、XCTest 公共控件、controller 意图及物理设备证据。
保持 .fused 唯一可靠来源、拒绝原因/诊断、阈值、schema、校准身份和资源上限。
窄屏展示与物理 LiDAR/人工果数/30/60/120 秒资源验收另列，不以本轮通过代替整体完成。
完成后记录下一轮构思；提交、推送与合并按当前明确授权执行。
```

## 第四十二轮：历史、结果标记与批量导出的分类根装配

2026-10-04。第 40–41 轮已由 [PR #15](https://github.com/Hkai29/FruitTreeScanner/pull/15) 合并，主分支提交 `c17ed022` 与本轮基线 `c6d084c2` 文件树一致。六项原有工作流 dirty work 继续保留。本次用户明确要求推送并合并，第 42 轮使用独立分支 `codex/root-classification-consumers` 交付，远端终态以对应 PR 为准。

根因是分类生产者已使用 AppDependencies 持有的 TagStore，但历史、扫描结果与批量导出仍从 shared 读取或写入另一套分类。最终夹具与全部八个原生产文件匹配基线摘要时，`before-final.xcresult` 的三项产品回归均失败、退出 65：实际历史菜单缺失根地块，实际 ScanView 结果未恢复根归属，实际 CSV 未包含根地块分组。历史和结果在缺失根数据时 guard 终止，未继续保存标准分类。早期菜单 accessibility 定位及系统呈现夹具失败另列，不冒充产品证据。

- Dashboard → HistorySheetView → ScanHistoryView 传递同一根，筛选与复核写入继续执行原逻辑。
- ScanView → ScanScannerInterfaceLayer → ScanResultLayer → ResultView → QuickTaggingCard 传递同一根，结果恢复、草稿与保存继续执行原逻辑；根发布更新不覆盖用户尚未保存的本地草稿。
- Dashboard → BatchExportView 传入已有可注入的 TagStore，CSV 按地块映射使用根名称；没有改变导出服务或文件格式。
- 默认构造保持 `.shared` 兼容。assignment ID、地块/标签、复核状态、reviewing 恢复为 scanned 草稿的既有语义、v1/legacy 编码、待保存语义及存档字节保持。TreeFilterView 再次核对没有生产调用，本轮未迁移或移除。
- 三项实际 UI 链回归分别验证地块/状态筛选与复核刷新、结果恢复/选择/根发布后草稿保留/保存、真实按地块 CSV；核对新建 TagStore 读回、标准偏好值与缺失状态、自有存档完整字节。菜单夹具用公共 UIContextMenuInteraction.updateVisibleMenu 读取实际菜单并原样返回，通过公共 UIButton.sendAction 派发原 UIAction；不称作系统菜单物理点击。
- 最后源码修改后的 `after-final.xcresult` **3 项通过，0 失败/跳过/预期失败，退出 0**。`storage lifecycle ui full` **1042 项通过、59 类、9 步全部退出 0**；三项关键方法逐项 Passed，Domain 检查与 unsigned Release 模拟器构建通过。开始/结束快照一致，九个 Swift 文件摘要仍与受测版本一致。
- 七张 PNG、七份 accessibility 附件及一份 CSV 均复核；根地块、筛选后的 A 记录、结果已保存与 CSV `ROOT41 PLOT,BATCH42,7,1.25` 符合预期。390×844 的既有批量选项/标题占用列表空间，首行只能部分显示；该布局不属于本轮改动，后续紧凑布局验收仍需处理。

最终受测 Debug App 安装到专用 iOS 27 模拟器。原生 CUA 实际走查工作台 → 历史地块菜单打开/取消、已扫描状态筛选空态、恢复全部状态、完成返回；工作台 → 批量导出显示 2/2 条完整记录、18 个果实与 3.9 kg、排除三条无效/未完整记录，选择按地块、关闭/重开恢复默认不分组，再关闭返回。原生未修改归属、复核、删除或导出分享；相应写入和 CSV 由隔离真实 UI XCTest 验证。Device Hub 最终为完整窗口、专用模拟器、键盘捕获关闭、Fit 缩放、工作台可见。

安装前后及走查后 **11 份档案/校准文件集合与 SHA-256、全部 7 项实际持久偏好完全一致**；本轮实际 plist 项目计数与前轮包含默认值/缺失状态的 25 项检查范围分别记录。六项工作流文件摘要不变。算法、`.fused` 唯一可靠来源、深度/confidenceMap 拒绝、诊断、阈值、schema、摘要、校准身份和资源上限保持。

证据在 `/private/tmp/fruit-iteration42/`：`before-final.xcresult`、`after-final.xcresult`、`attachments-after-final/`、`fruit-code-improvement-x10y53r0/report.json`、`critical-methods.json`、`render-review.json`、`ui-validation.json`、`native-final-preservation.json`、`final-source-preservation.json` 与 `final-review.json`。独立只读复审无本轮阻塞发现，结论 **mergeable**。全量报告保留两条系统 QoS 提示，不宣称性能收益、最低 iOS 运行或物理 LiDAR 验收。整体目标因校准参数所有权、紧凑布局及真实设备验收仍为 **needs changes**。

### 下一轮构思与提示词：校准和扫描计划的参数所有权

真实代码仍显示 CalibrationView 的草稿初始化、onAppear 与提交写入使用 SettingsStore.shared/FruitParametersStore.shared；CalibrationParametersCard 的 HSV 显示读取 shared；ScanPlanFactory 的快照捕获直接读取 FruitParametersStore.shared，VarietyDatabaseView 同样持有 shared 参数。下一轮先核对这些路径与根装配，不能仅以去掉 shared 字样判定完成。

```text
继续 FruitTreeScanner 重构，读取 AGENTS.md、本记录并 preflight。
第 42 轮分类消费者已完成，最终全量 1042 项与 Release 通过；先核对实际 Git/PR 终态。
保护六项工作流 dirty work、已受测源码、专用模拟器 11 份档案和全部实际持久偏好。
追踪 AppDependencies、Dashboard → CalibrationView → CalibrationParametersCard，
Settings → VarietyDatabaseView，以及 ScanPlanFactory 的参数快照捕获。
先用独立根、偏好和参数证明实际读写/计划冻结缺口，建立失败回归或迁移基线。
按证据确定 FruitParametersStore 的根所有权及必要消费者，保留旧默认构造兼容。
校准草稿、当前品类、设置提交、品种参数与新计划快照应使用同一根；
后续参数编辑不得改变活动 ScanPlan，不能在失败旧实现上继续写标准参数。
不改变默认阈值、校准签名/身份、参数编码、可靠融合准入、诊断或资源上限。
最后源码修改后运行参数/计划/校准定向与必要 storage/lifecycle/ui/full/Release，
核对关键方法结果树、快照、渲染，独立复审并完成保护数据的原生关闭/重开走查。
区分实际 CUA 操作、XCTest 公共控件与物理 LiDAR/人工果数/资源测量证据。
完成后记录下一轮构思；提交、推送与合并按当前明确授权执行。
```

## 第四十三轮：校准、品种编辑与扫描计划共用根参数

2026-10-04。第 42 轮已由 [PR #16](https://github.com/Hkai29/FruitTreeScanner/pull/16) 合并，远端主分支提交为 `75c85cc4`；本轮本地基线为该 PR 的 `ddedf7da`。本轮改动仍在本地，未提交、推送或合并；六项原有工作流改动保持原摘要。

根因是 AppDependencies 已持有根设置，却未持有果实参数库；校准、品种编辑和计划捕获仍独立访问全局参数。`before-executed.xcresult` 的根计划回归失败、退出 65：根梨参数为最大直径 0.145 m、221 g，计划却读取默认的 0.15 m、180 g。为使回归可编译，失败前仅添加保存参数库的默认构造参数，所有生产消费者和工厂仍保持旧实现；该构造接缝不作为修复证据。没有在失败旧实现中继续执行参数写入。

- AppDependencies 持有 FruitParametersStore，ScanPlanFactory 捕获该根的完整参数快照。Dashboard 校准与设置路由、Settings → VarietyDatabaseView 传递同一根；旧默认构造继续解析 `.shared`。
- CalibrationView 的初始化、显示和提交使用根设置及参数；HSV 卡片观察同一根。校准草稿保存打开时的品类，其他消费者改变下一次扫描品类不会将梨草稿写入苹果。已创建计划的参数、聚类配置及校准上下文保持冻结。
- 三项 DashboardSummaryTests 验证完整参数捕获与冻结、真实校准控件提交/关闭/重开及草稿品类、嵌套品种编辑的取消/保存/重开和持久化读回。独立偏好与目录隔离，保护标准偏好值及缺失状态。重置确认不通过私有 action 或生产测试入口派发，另由原生 UI 测试执行。
- 新增独立 FruitTreeScannerUITests target、FruitTreeScannerUI scheme 和原生验证入口。默认单元测试 scheme 保持；UI target 的 iOS 17 最低版本匹配 XCTest 框架要求，App 与原单元测试的 iOS 16 声明保持。入口只新建、操作和删除自己的模拟器，测试启动应用前核对设备 UUID 与名称；失败结果包也解析和保存，缺少明确计数、关键方法所属 target/class、退出码、源码稳定或设备清理证据均不能通过。
- 原生测试实际保存苹果 1 g、梨 2000 g，打开真实重置确认框，取消保留 2000 g，确认重置后梨恢复 180 g，苹果仍为 1 g，重启后梨仍为 180 g。截图逐张核对。早期触摸定位失败及 Slider.adjust best effort 产生 1996 g 的失败现场保留；最终等待公共控件可点击且呈现生产 44×44 pt 大小，并通过公共触摸拖到滑轨端点，继续要求精确 2000 g，没有放宽断言或按调试文本猜坐标倍率。

最终定向 **3 项通过、退出 0**；`storage lifecycle ui full` **1045 项、59/59 类通过，9 步全部退出 0**，包含 Domain 独立编译和 unsigned Release 模拟器构建。三项关键方法逐项 Passed，开始/结束快照一致。最终独立原生 UI 测试 **1 项通过、退出 0**，失败/跳过/预期失败均为 0，自有模拟器删除成功；验证入口的 **4 项反例测试通过**。全量之后只有独立 UI 驱动修正，App、单元测试、工程和 scheme 摘要与全量受测版本一致，最终 UI 驱动/入口摘要与最终原生结果一致；随后仅补执行文档。

最终全量 Debug App 安装到专用 iOS 27 模拟器，原生 CUA 核对实际工作台 → 校准参数 → 关闭 → 重开 → 关闭，最小点数 5、最大直径 0.150 m、球形度 0.50、HSV 330…25/S30/V30 显示正常。安装前后及最终关闭后 **11 份档案/校准文件集合和字节、全部 7 项实际持久偏好保持**。最后恢复完整 Device Hub、专用模拟器、键盘捕获关闭、Fit 缩放、工作台可见。独立根 UI 控件、原生 XCTest 确认框与 CUA 只读走查分别记录，不合称为物理 LiDAR 验收。

参数编码、默认阈值、校准签名/身份、模型身份、存档 schema、资源上限、`.fused` 唯一可靠来源、深度/confidenceMap 拒绝及各类诊断保持。全量仍有两条系统 QoS 提示；没有宣称性能收益、最低 iOS 运行或真实估产精度。独立只读复审及最终截图复核未发现本轮阻塞问题，结论 **mergeable**。整体目标仍有多窗口草稿冲突、紧凑布局及真实设备验收，整体为 **needs changes**。

证据在 `/private/tmp/fruit-iteration43/`：`before-executed.xcresult`、`final-targeted.xcresult`、`fruit-code-improvement-mg68ubl1/report.json`、`fruit-native-ui-2aik_on_/report.json`、两组最终附件、`critical-methods.json`、`render-review.json`、`ui-validation.json`、`native-final-preservation.json`、`final-source-preservation.json` 与 `final-review.json`。原生验证步骤见 [NATIVE_UI_TESTS](../validation/NATIVE_UI_TESTS.md)。

### 下一轮构思与提示词：旧校准草稿关闭时保护较新参数

现有 Info.plist 支持多窗口，App 的根供 WindowGroup 使用。CalibrationView 在 `.onDisappear` 无条件提交，提交方法以当前存储与旧草稿比较，尚未区分用户编辑和外部更新。相同品类被其他消费者更新后，未编辑旧页面的关闭可能覆盖较新值；这是已有调用链风险，下一轮须建立失败回归，不能以静态检查宣称已经复现。第 43 轮品类冻结解决了写错品类，尚未解决同一品类的旧值覆盖。

```text
继续 FruitTreeScanner 整体重构，读取 AGENTS.md、本记录并 preflight。
第 43 轮根参数所有权已完成：全量 1045 项、59 类、Release 和独立原生 UI 已通过。
核对 Git/PR 状态，保护六项工作流 dirty work、当前受测源码、11 份原生文件及实际持久偏好。
追踪 CalibrationView 的草稿加载、Slider 提交、onDisappear 与同根其他消费者。
先建立同一品类的新值更新后关闭未编辑旧页面的失败回归；
再覆盖已提交滑块后发生外部更新、尚未提交的用户编辑以及下一次扫描品类变化。
明确草稿基线、字段编辑状态及提交后基线推进，关闭未编辑页面应不写参数。
只提交用户实际修改的字段，保留其他消费者的较新字段；同字段冲突按真实交互确定策略。
保持根参数所有权、打开时的草稿品类、旧 ScanPlan/校准上下文冻结及默认 API 兼容。
不改默认阈值、参数编码、摘要身份、可靠融合准入、诊断或资源上限，不引入闲置抽象。
最后源码修改后运行校准/参数/计划定向、必要 storage/lifecycle/ui/full/Release，
核对关键方法结果树、源码摘要、渲染和数据保护，独立复审并完成可行原生走查。
区分单元公共控件、原生触摸、CUA 和物理 LiDAR/人工果数/资源证据。
记录下一轮构思；提交、推送与合并按当前明确授权执行，不宣告整体目标完成。
```

## 第四十四轮：校准草稿按字段提交并保护较新参数

2026-10-04。基线包含第 43 轮受测内容及六项原有工作流 dirty work。原生多窗口共享 App 根，同品类的另一个消费者可以在旧校准页面仍打开时更新参数。旧实现在关闭时重交全部草稿，未区分未编辑、已提交和外部更新，导致新值被覆盖。

- `before-executed.xcresult` 在第 43 轮生产实现上执行四项回归，全部 Failed、退出 65：关闭未编辑旧页面将点数 24 覆盖为 19，已提交旧页面会重写旧最大直径，手势结束和待提交草稿关闭均可覆盖较新值。早期测试夹具的异步断言编译失败单独保留，不作为产品回归证据。
- 每个字段保存自己的已接纳值及设置/参数来源基线。未编辑不写；有实际编辑且来源未变才提交；同字段来源变化则保留较新值，显示“参数已在其他页面更新，已保留最新值。请重新调整。”。成功、未编辑和冲突都刷新该字段基线，下一次编辑可重试，独立字段仍可正常保存。
- 首次全量 1050 项通过后复审发现关联下界缺口：下降最大直径会夹紧其他消费者刚保存的最小直径。补充参数库和设置两侧的失败回归，`bounds-before.xcresult` 为两项 Failed、原有夹紧兼容项 Passed。最大直径草稿同时捕获两侧下界；仅当下界已变化且拟提交值会夹紧它时拒绝，安全的新下界可以合并，无并发时保持原夹紧规则。参数侧按 Float 比较匹配实际写入。循环回归等待实际两侧存储值和页面值，避免仅等已存在的草稿显示而误报成功。
- 最终新增八项产品回归，连同第 43 轮三项共 **11 项定向 Passed、退出 0**；`storage lifecycle ui full` 为 **1053/1053 项、59/59 类 Passed，9 步全部退出 0**，失败/跳过/预期失败均为 0，包含 Domain 独立编译和 unsigned Release。11 项关键方法在定向及全量结果树逐一 Passed，开始/结束快照一致，最后源码摘要完全匹配。
- 最终定向六张截图及可访问性附件逐项复核，冲突说明可读，新值重开为 24/0.165 m/0.64。安装最终全量 Debug App 后，原生 CUA 实际完成工作台 → 校准 → 关闭 → 重开 → 关闭，默认参数 5/0.150 m/0.50、HSV 330…25/S30/V30 正常；安装前后及最后关闭后 **11 份文件集合与字节、整份 7 项实际持久偏好保持**。最后回到完整 Device Hub、专用模拟器、键盘捕获关闭、Fit 缩放、工作台。第 43 轮独立原生 UI XCTest 的 1 项证据单列，本轮没有重新执行该确认框测试。

独立只读复审确认字段冲突、两侧关联下界、安全合并、原有夹紧、源码摘要与最终界面/数据保护，无本轮阻塞项，结论 **mergeable**。第 43 轮根所有权、打开时品类、已捕获计划与校准上下文冻结保持；步长和原 0.0001 容差、编码、校准/模型身份、默认阈值、schema、资源上限、`.fused` 唯一可靠来源、深度/confidenceMap 拒绝及诊断保持。19 份范围外轮前改动（含六项原有工作流）在本轮修复期间摘要保持。全量两条系统 QoS 提示保留；最低运行版本和真实 LiDAR/人工果数/物理资源未验收，整体目标继续 **needs changes**。

证据在 `/private/tmp/fruit-iteration44/`：`before-executed.xcresult`、`bounds-before.xcresult`、`final-proof.xcresult`、`attachments-final/`、`fruit-code-improvement-f5wcthiv/report.json`、`critical-methods.json`、`render-review.json`、`ui-validation.json`、`native-final-preservation-after-bounds.json`、`final-source-preservation.json` 与 `final-review.json`。记录在最终验证后补充。本次用户明确要求“推送并合并”，交付范围为第 43/44 轮 app、测试、原生 UI 验证入口及执行记录；六项原有工作流改动继续排除，构建产物与模拟器数据保留仓库外。实际提交与远端结果见随后交付检查点。

### 下一轮构思与提示词：品种编辑按实际修改字段保存

`VarietyEditView` 打开时保存六项参数，`normalizedParams` 保存时重写全部字段，`VarietyDatabaseView` 的回调也覆盖全部六项。只改重量的旧页面可能覆盖另一个校准消费者刚保存的直径/球形度；这是现有调用链候选，本轮未实现，也未将静态检查写成失败复现。

```text
继续 FruitTreeScanner 重构，先读取 AGENTS.md、本记录并 preflight，核对实际 Git/PR 状态。
第 43/44 轮根参数与校准字段冲突已完成，最新 1053 项、59 类、Release 通过。
追踪真实 Dashboard → Settings → VarietyDatabaseView → VarietyEditView 的加载、保存、取消及重置。
先建立旧品种页面仅改重量、同根校准消费者更新直径/球形度后保存的失败回归，
再验证未编辑保存、待提交同字段冲突、成功后重开、取消与显式重置。
按实际修改字段及来源基线提交，保护未编辑字段的较新值；检查直径上下限联动。
冲突反馈须可见且允许重新编辑，保留显式重置确认与取消、根所有权、品类、默认 API、
参数编码、校准身份、已捕获计划冻结和现有归一化约束，不增加闲置抽象或生产测试入口。
最后编辑后完成定向、storage/lifecycle/ui/full/Release、关键方法结果树及渲染，
独立复审并按实际改变的 UI 路径补原生验收，保护六项工作流 dirty work、11 文件及实际偏好。
真实 LiDAR、人工果数和资源证据另列；更新下一轮构思，不宣告整体目标完成。
提交、推送与合并按当前明确授权执行。
```

### 第 43/44 轮交付检查点

2026-10-04，用户明确要求“推送并合并”。已在 `codex/calibration-parameter-ownership` 上拆分提交：`cf285b61`（第 43 轮根参数装配及对应单元/原生 UI 入口，15 个文件）和 `4943b9b8`（第 44 轮草稿并发保护及回归，5 个文件）。第一项的暂存字节匹配第 43 轮受测版本，第二项逐文件匹配最终 1053 项受测快照；执行记录在测试后单独提交。前文各轮“未提交、未推送”描述该轮结束时的历史状态。

创建分支前已核对远端 main 为 `75c85cc4`，其文件树与本地第 42 轮基线相同。本次仅提交第 43/44 轮 19 个路径，六项原有工作流改动保持原摘要并留在本地；没有纳入构建输出、合成数据或模拟器状态。推送使用上述分支并经 PR 合并，远端 CI、PR 及 main 的实际终态以随后核验的交付结果为准。提交范围 **mergeable**，真实设备与下一轮候选仍独立保留。

第 43/44 轮远端终态已于第 45 轮开始时核验：[PR #17](https://github.com/Hkai29/FruitTreeScanner/pull/17) 为 MERGED，合并提交 `f8d6811b`；分支头 `edf44739` 与该 main 提交文件树相同。远端 run `37199955431` 的 Domain 与模拟器构建成功，此 CI 不代替本地 XCTest 或物理验收。

## 第四十五轮：品种编辑原子合并实际修改字段

2026-10-05。调用链为 Dashboard → Settings → VarietyDatabaseView → VarietyEditView → App 根参数库 → 后续 ScanPlan。页面重建能收到较新参数，但六项 State 草稿仍保存打开时的旧值；旧保存回调重写全部六项并直接关闭，覆盖其他消费者的更新。基线是已合并第 43/44 轮的分支头及六项原有工作流 dirty work。

- 改动前 `before-repaired.xcresult` 的三项真实页面回归全部 Failed、退出 65：仅改重量覆盖较新直径等五字段；未编辑保存重写参数并发布；同字段冲突后直接关闭。生产源码与轮前副本一致。此前 UISlider 可访问性包装对象的夹具错误、后续归一化输入和默认密度未产生编辑的夹具错误分别保存，未作为产品故障或通过证据。
- `FruitParametersStore.commitEdits` 在一个同步 MainActor 操作内比较实际修改字段与打开时基线，先检查品类、参数 UUID、全部字段冲突和合并后的直径上下界，再发布一次并保存。任何冲突整次拒绝，不做部分写入；空编辑不发布、不标记自定义、不安排保存。同数值重置产生的新 UUID 也拒绝旧编辑。
- VarietyDatabaseView 只调用该提交入口；VarietyEditView 的基线与草稿共同保存在 State 中。成功才关闭；冲突保留页面，载入全部最新值并显示中英文说明，重新编辑可提交。保留旧 onSave 初始化签名、显式重置确认与取消、滑块范围/步长和原直径联动，未增加独立生产测试入口。
- 最后编辑后的 `verified-targeted.xcresult` 为 **15/15 Passed、退出 0**：六项存储回归、六项品种并发页面回归及三项既有根参数/计划回归。`storage lifecycle ui full` 为 **1065/1065 项、59/59 类 Passed、9 步全部退出 0**，包含整个 Domain 独立编译与 unsigned Release；失败/跳过/预期失败均为 0。15 项精确方法在定向与全量结果树逐项通过，开始/结束快照一致，最终源码摘要相等。
- 七张最终定向截图及可访问性附件已逐项检查：冲突说明可读，重载重量 333 g、重置后 180 g；合并重开保留 40/165 mm、222 g、密度 0.93、球形度 0.64。独立原生 UI XCTest 在自有 iPhone SE 临时模拟器上 **1 项 Passed、退出 0**，实际触摸验证取消重置、确认重置、其他品种保持与重新启动读取；三张原生测试截图可读。脚本四项证据门禁回归通过，自有模拟器已清理，源码未变化。
- 安装同一受测源码的定向 Debug App 后，CUA 原生完成工作台 → 设置 → 品种库 → 梨编辑 → 未编辑保存 → 重开 → 取消 → 返回 → 完成 → 工作台。安装前后、未编辑保存后及最终关闭后，**11 份档案文件集合与字节、整份 7 项实际持久偏好保持**；自定义品种仍为 0。与隔离夹具的原生重置测试分列，未重置现有走查数据。

独立只读复审未发现本轮生产阻塞。保持根参数所有权、打开时品类、其他品种与较新未编辑字段、已捕获计划/校准上下文冻结、参数编码/身份、默认阈值、schema、资源上限、`.fused` 唯一可靠来源、低置信度拒绝和诊断。六项原有工作流改动保持原摘要并排除提交；本轮 App、测试与执行记录共九个路径按用户“推送并合并”授权交付，远端终态单独核验。

证据目录 `/private/tmp/fruit-iteration45/`：`before-repaired.xcresult`、`verified-targeted.xcresult`、`critical-methods.json`、`fruit-code-improvement-y123yag3/report.json`、`fruit-native-ui-ute3ps_i/report.json`、`attachments-verified/`、`native-test-attachments/`、`render-review.json`、`ui-validation.json`、`native-after-native-xctest.json` 和 `final-source-preservation.json`。测试后仅补充本执行记录，App/测试八个路径未动；文档测试前摘要仍留在验证快照中。全量保留两条系统 QoS 提示及已有编译警告；最低运行版本、物理 LiDAR/人工果数和实际资源仍未验收。本轮决定 **mergeable**，整体目标仍 **needs changes**。

### 下一轮构思与提示词：校准草稿的重置身份边界

静态检查发现 CalibrationParameterDraft 仍只比较设置/参数数值与关联下界，没有捕获参数 UUID。同品类被重置为相同数值时，旧待提交手势可能通过数值比较；这是下一轮候选，尚未建立失败回归，不宣称已修复。另有已经观察到的显示候选：Float 滑块回写 `0.14999999 m` 被现有 Int 截断呈现为 149 mm。本轮仅对应数值断言使用 1e-6 精度，其余字段/身份/零写入仍精确比较，并检查上下界；未修改展示舍入规则。

```text
继续 FruitTreeScanner 整体重构，读取 AGENTS.md、本记录并 preflight，核对实际 Git/PR 状态。
第 45 轮品种编辑原子字段合并已完成：15 项定向、1065 项/59 类全量、Release、
独立原生 UI 1 项与原生未编辑保存/取消均通过；保护六项工作流改动及11文件/整份偏好。
优先追踪 CalibrationParameterDraft 和同根参数 resetToDefault/resetAll 的身份变化。
先建立旧校准待提交手势遇到同数值重置的失败回归，再决定是否需要捕获来源 UUID。
覆盖关闭、手势结束、同品类/其他品类重置、未编辑零写入和拒绝后新编辑重试。
保留字段级提交、两侧下界、安全合并、打开时品类及扫描计划/校准上下文冻结。
若该候选无法复现，不制造改动；随后单独复现毫米显示截断，明确展示舍入规则，
不要为修正显示改写物理参数或旧存档编码。两项根因分轮实施和验证。
不重做根所有权迁移，不改变阈值、可靠融合准入、诊断、schema或资源上限。
最后源码修改后运行定向、对应风险关卡、可行全量/Release与原生走查，独立复审。
分别报告模拟器、原生控件与物理设备证据，记录下一轮构思；整体目标保持 active。
提交、推送和合并按当时明确授权执行，保护范围外改动。
```

## 第四十六轮：校准草稿绑定重置来源身份

2026-10-05。第 45 轮已通过 [PR #18](https://github.com/Hkai29/FruitTreeScanner/pull/18) 合并为 `eb807eac`，CI run `37258382617` 的 Domain 与模拟器构建成功；远端 main 与受测分支头 `33984237` 文件树相同。本轮从该头继续，只修改校准页面、根 UI 回归及本执行记录，六项原有工作流改动继续保留。

- 根因：CalibrationParameterDraft 只记录设置/参数数值和关联下界；resetToDefault/resetAll 会创建新的参数 UUID，即使直径/球形度数值完全相同，旧编辑也应失效。未改生产代码的 `before.xcresult` 为 **4 项：2 Failed、2 Passed，退出 65**；失败证明旧手势与关闭提交把重置后的梨参数改为 `.155/.32/customized`，其他品类重置及未编辑关闭通过。生产轮前摘要及保护文件核对均相等。
- 直径和球形度草稿分别捕获参数 UUID，在初始化、onAppear、提交检查与重载时贯通；已编辑草稿的来源变化会拒绝写入并载入最新值，随后新编辑可提交。先判断未编辑，保持零写入；最小聚类点数不依赖参数身份，关闭时仍能独立提交。每个字段持有自己的基线，直径拒绝后的重载不会放行旧球形度。重载一次读取完整最新参数，不改变字段冲突、双下界和原联动策略。
- 最后源码修改后的 `after.xcresult` 为 **13/13 Passed、退出 0**，包含四项新回归与九项既有校准/根参数回归。`storage lifecycle ui full` 为 **1069/1069 项、59/59 类 Passed，9 步全部退出 0**，包括整个 Domain 独立编译及 unsigned Release；零失败、跳过和预期失败。13 项方法在定向与全量结果树逐项通过，验证开始/结束快照一致。
- 七份页面 PNG/可访问性附件已独立查看：两种重置冲突恢复 `19/.150/.30` 并显示完整说明；关闭重开为 `20/.150/.30`，旧冲突、较新值及打开时品类仍正确。真实 UIKit 公共控件驱动根页面，无新增生产测试入口。CUA 原生走查新版本工作台 → 校准 → 未编辑关闭 → 工作台，安装前后、打开后与关闭后 **11 份档案的集合/字节及整份 7 项实际持久偏好保持**；重置仅在隔离测试夹具执行。两张原生截图已检查。

独立只读复审未发现本轮生产/UI 阻塞。保留未编辑零写入、设置独立字段、其他品类、打开时品类、根参数所有权、旧计划/校准上下文冻结、阈值、schema、资源上限、`.fused` 唯一可靠来源及全部诊断。本轮没有提交、推送或合并；第 45 轮交付与第 46 轮本地改动分列。证据目录 `/private/tmp/fruit-iteration46/`：`baseline.json`、`before-production-preservation.json`、`before.xcresult`、`after.xcresult`、`critical-methods.json`、`critical-full.json`、`fruit-code-improvement-3tuxuc60/report.json`、`attachments/`、`native-final-preservation.json` 和原生截图。全量保留两条系统 QoS 提示及已有编译警告；最低运行版本、物理 LiDAR、人工果数和实际资源验收仍待补齐。本轮决定 **mergeable**，整体目标仍 **needs changes**。

### 当前范围进度估算

应用户“现在重构了多少百分比”，对照原 R0–R7 交付范围和当前待验收清单，估计**代码架构改造约 90%，包含全部验收的整体完成度约 80%**。这是定性的范围估算，没有预先登记阶段权重或自动进度统计；46 轮迭代不是完成百分比，也不能代表性能提升比例。主要代码所有权/契约、领域隔离、仓储和消费者迁移已实施，完整删除流程、真实观测回放及同设备 30/60/120 秒内存/耗时/精度验收仍未全部通过。独立 framework/package 仅在有实际依赖收益时评估，不因尚未拆包把现有隔离门禁判为未完成。

### 下一轮构思与提示词：直径毫米显示舍入

第 45 轮真实滑块已观察到 `.14999999 m` 显示为 `149 mm`；VarietyParameterFormatter 的单值和区间都用 `Int(meters * 1_000)` 截断。下一轮先固定展示规则及失败回归，只在呈现层处理浮点边界，不修改物理参数或编码。

```text
继续 FruitTreeScanner 整体架构收尾，读取 AGENTS.md、本执行记录并 preflight。
第 46 轮校准重置身份已完成：13 项定向、1069 项/59 类全量、Domain、Release、
原生未编辑关闭及11档案/整份7偏好保护通过；仅三个本轮路径未提交。
先追踪 VarietyParameterFormatter.millimeters/diameterRange 与编辑滑块、品类卡片消费者。
复现 .14999999 m 被截断为149 mm，明确显示到整毫米的舍入规则，再建立失败回归。
覆盖单值、区间、实际滑块步长、不同语言/locale；保护范围与单位的一致性。
修复仅限显示，不将舍入后的数值写回参数，不改变编码、阈值或物理几何。
验证实际编辑页面与品类卡片保持一致，未编辑保存仍为零写入，持久参数字节不变。
不要重做 UUID 草稿保护、根参数装配、原子合并或领域/仓储迁移。
按风险完成测试、iOS原生走查和独立复审，记录真机验收仍未完成。
提交、推送、合并依照当时明确授权；六项原有工作流改动继续保护。
```

## 第四十七轮：整毫米展示统一舍入

2026-10-05。本轮沿用 `33984237`，保护六项原有工作流改动、第 46 轮校准源码和四项回归。只修改品种展示格式、两份测试及本执行记录。

- 根因：VarietyParameterFormatter 的单值和区间端点直接截断 `meters * 1_000`；实际滑块的 `.14999999 m` 因而显示为 `149 mm`，`.034999996 m` 显示为 `34 mm`。生产未改时，修正夹具后的 `before-repaired.xcresult` **4/4 Failed、退出 65**，失败均为显示断言；物理 bitPattern、完整参数、持久字节、零发布和冻结计划保持断言通过。首次 `before.xcresult` 还包含测试读取继承默认值的额外快照断言失败；夹具改为比较隔离 suite 的完整 persistentDomain 后重新复现，原始失败证据保留，未将夹具问题当作产品缺陷。
- 单值和区间共用只读 `millimeterNumber`，显示到最近整毫米，半毫米向远离零的方向舍入。未回写或量化物理参数；重量、locale、单位、区间分隔符、滑块步长及存档编码不变。
- 最后源码修改后的 `verified-targeted.xcresult` **11/11 Passed、退出 0**；固定边界预期覆盖半毫米、三种 locale 和全部 97 个合法滑块网格值。实际根 UIKit 页面覆盖滑块编辑、保存、卡片、重开和未编辑保存，原始 Float bitPattern、整份参数/持久 suite、零发布及下一冻结计划均保持。第 45 轮并发用例仅更新过时的截断显示预期，其并发断言保持。
- `ui` profile **1073/1073 项、59/59 类 Passed，8 步全部退出 0**，包含完整 Domain 独立编译，零失败、跳过或预期失败；11 项定向方法在全量结果树逐项通过，验证开始/结束源码摘要相同。本轮没有重跑 Release 或独立原生 UI XCTest，不能将第 46 轮 Release 和更早的原生 UI 测试写成本轮证据。
- 七份 PNG 和七份可访问性附件已逐份复审：两张梨卡片明确显示 **35–150 mm**，两张新编辑页面显示 **35/150 mm**；冲突说明、重置值与较新字段保持。卡片范围未由 AX 自动断言，已直接检查 PNG。CUA 原生走查工作台 → 设置 → 品种库 → 梨编辑 → 未编辑保存 → 品种库 → 返回 → 完成 → 工作台，默认梨仍为 **30–150 mm**，自定义品种数仍为 0。安装前后、保存后和最终返回后 **11 份档案的集合/字节及整份 7 项实际持久偏好保持**。

独立只读复审未发现本轮阻塞。保留第 46 轮草稿身份保护、原子字段合并、根所有权、物理参数与计划/校准上下文冻结、schema、阈值、资源上限、`.fused` 唯一可靠来源及全部诊断。本轮未提交、推送或合并，第 46/47 轮仍是本地改动。证据目录 `/private/tmp/fruit-iteration47/`：`baseline.json`、`before-repaired.xcresult`、`verified-targeted.xcresult`、`critical-methods.json`、`critical-full.json`、`fruit-code-improvement-n9nvc4mm/report.json`、`attachments/`、`native-final-preservation.json` 与原生截图。全量保留两条已有 QoS 提示及编译警告；最低运行版本和物理 LiDAR/资源/人工果数验收仍未完成。本轮决定 **mergeable**，整体目标仍 **needs changes**；代码约 90%、整体约 80% 的定性估算暂不因本轮显示修复上调。

### 下一轮构思与提示词：按原交付范围核验缺口

呈现层边界收尾后，下一轮回到原 R0–R7 完成条件，逐项关联当前生产入口、所有权和实际证据，区分已实施、已验证与仍缺验收的事项。现有合成观测回放、领域编译和模拟器结果不能替代真实观测或同设备峰值内存/耗时/果数误差。先核对已有观测存档与资源记录入口，再选择有证据的最小缺口；不重复已完成迁移或新增无依据的外观重构。

```text
继续 FruitTreeScanner 整体重构，读取 AGENTS.md、原 R0–R7 蓝图和本执行记录并 preflight。
第 47 轮整毫米显示已完成：11 项定向、1073 项/59 类全量、完整 Domain、
七份页面附件及原生未编辑保存/返回通过；11档案和整份7偏好保持。
保护六项原有工作流改动及第46/47轮本地源码、测试；提交按明确授权执行。
对原蓝图的完成条件建立逐项表，链接当前真实调用链、所有权和已执行证据。
区分代码完成与模拟器、原生控件、最低运行版本、物理LiDAR及资源验收。
核对 Observation 的生成、冻结、回放和存档接口，以及已有峰值内存/结束耗时记录。
先复用现有入口；真实观测基线必须有采样上限、脱敏、模型/配置身份和固定预期。
若需新契约，先固定兼容及失败回归，再实施最小改变；不要将平台缓冲带回 Domain。
物理30/60/120秒及人工果数需要操作者与同场景基准，不能用合成回放替代。
不重做已完成所有权/仓储迁移，不改融合准入、阈值、旧编码、诊断或资源上限。
按实际风险验证并独立复审，记录剩余事项与下一步，整体目标保持active。
```

## 第四十八轮：对照原 R0–R7 完成条件核验

2026-10-05。上一轮完成第 47 轮源码修复、1073 项全量、原生走查和独立复审，属于已验证进展。本轮沿用 `33984237`，读取原蓝图、真实生产链、工程 target、结果树与现有测量入口；新增 [原范围完成条件核验](REFACTOR_COMPLETION_AUDIT_2026-10-05.md)，并更新本记录。没有生产、测试、工程或工作流改动，所有 308 个 Swift 源文件及六项原有工作流改动保持；第 46/47 轮记录与源码也保持。

- 核验覆盖原 8 个阶段、34 条架构/底层约束、七条全应用协作、17 个必测场景和核心不变量。48 个明确引用的方法在第 47 轮结果树唯一出现且 Passed，对应测试源码位置已核对。结果树仍为 **1073/1073 Passed、59 类、8 步退出 0**；本轮没有重跑 XCTest 或原生页面，不把旧结果写成新运行。
- 本轮重新运行整个 Domain 独立编译，**24 文件、iOS 16 simulator/Swift 5、退出 0**；当前 App **unsigned Release 模拟器构建退出 0**。原生 UI target 为 iOS 17，App/单元 target 仍为 iOS 16；编译不能证明最低版本运行。初次 Domain 尝试因沙箱缓存权限失败，仓库外缓存后的会话 handle 在恢复时已丢失，不计成功；最终留存日志/退出码的运行才计通过。首次 Release 自动审批因用量限制未执行，读取用量确认恢复后重新经审批启动，通过后保留原失败经过。
- 实质缺口：当前 Domain 门禁只证明现有 24 个文件；ReliableYieldEvidence、FusionEvidencePipeline、YieldResultComposer 和部分点云/遮挡编排仍在 Core，不能用目录编译通过关闭整个领域链。FramePacket/Observation 已有有界值契约，现有长期持久结果/研究 JSON 尚不是完整观测回放包；回放测试明确使用合成输入。FinalPointCloud.buildDuration 和 estimatedPeakPayloadBytes 分别是单阶段耗时和数组 payload 估算，不是进程峰值、全结束流程耗时或实测资源回归预算。GPU 在途/超时/permit 回收的专门故障证据、最低版本运行、完整原生删除、物理完成/重试、30/60/120 秒及人工果数均继续列为缺口。
- 全应用核验还发现 Dashboard 聚合仍在 Views、批量导出仍有 UI 编排、ScanPlan 未含 plot/tag 快照；这些按原要求列为部分实现。Renderer 仍编排命名/路径/仓储 staging/文件 writer，职责收敛未完成；兼容入口已补保留原因和退出条件，未冒充已移除。
- 下一项有真实调用链依据：ScanView 默认创建 Coordinator 未传根 settings；MetalView 创建 Renderer 未传根设置，Renderer 初始容量与无计划时 applyScanQualitySettings 都取全局共享设置；工厂随后按已经分配的 capacity 截断根配置。此处尚未新增失败回归，不预先声称具体运行后果。第 49 轮先用隔离根值与 shared 值不同的真实路径复现，再让初始容量/预览设置从根装配或现有捕获边界传递，保留预算、阈值、冻结计划、lazy 分配顺序及绑定保护。具体完成标准与提示词见新核验表第 7 节。

本轮对原范围的逐项核验产生了新的实施依据；不把第 46 轮 90%/80% 定性估算当作已完成的证明，不以迭代数或 LOC 再估进度，也未把目录示意、actor 建议和条件性 package 评估变成无条件重写任务。原 `.fused` 准入、诊断、旧编码、资源上限、模型/shader/研究资产保持。本轮未提交、未推送、未合并。证据目录 `/private/tmp/fruit-iteration48/`：`baseline.json`、`current-test-inventory.json`、`selected-test-evidence.json`、`project-targets.json`、`domain-command.json`/`domain.log`、`release-command.json`/`release.log`、`validation-summary.json`、`final-source-preservation.json` 和 `final-review.json`。独立只读复审先发现 Renderer 文件职责和兼容退出条件未完整列入；补齐并修正源码锚点后无新增阻塞，文档本轮 **mergeable**；整体目标继续 **needs changes / active**。

## 第四十九轮：扫描初始化和预览使用根配置

2026-10-05。第 48 轮原范围审计发现真实根配置缺口；上一轮用户进度询问仅核对并报告状态，没有关闭第 49 轮门槛。本轮继续已经建立的失败回归，完成修复、全量验证、原生能力提示/返回走查和独立复审。HEAD 仍为 `33984237`，开始时 12 个已有改动路径和 308 个 Swift 源文件留存摘要/副本，preflight 通过。

- **已复现的根因。** ScanView 默认 Coordinator、MetalView 的 Renderer 初始化和无活动计划时的延迟设置加载使用 shared，而不是 AppDependencies.settings。隔离根设置请求 140 万点，实际初始 buffer 只有共享的 100 万点，RGB/深度预览和相机请求也来自错误来源；随后工厂按这个实际 buffer 截断计划。修复前真实 ScanView/UIViewRepresentable 创建路径的两项回归均 Failed，退出 65；不是仅构造一个替代 Renderer 的探针。
- **修复范围。** ScanView 明确初始化由根 settings 创建的 State Coordinator，并保留已有状态/就绪/结果测试注入。ScanSettingsProviding 在 MainActor 捕获完整 RendererScanSettings；MetalView 从活动计划或根配置传入初始值，活动计划的 resourceBudget 从初始化开始生效。Renderer 保存固定 particleCapacity，初始化直接赋值而不触发 lazy 粒子分配；后续 maxPoints 始终受实际 buffer 限制。无计划预览重载也使用 Coordinator 的根 settings。默认三参数 init 和无参数 apply 的 shared 兼容包装留在既有 Application 捕获边界；Core/Renderer 不再自行读取 shared。
- **保留的约束。** 初始容量仍为 1…300 万点，后续设置不能扩大已分配 buffer；冻结计划、analysis/live 预算、cache 失效、绑定身份/迟到回调保护、SwiftUI 重建时已有 State owner/session/plan/renderer 均保持。未变更融合/深度阈值、仅 fused 可靠准入、诊断、PLY/manifest 编码、模型、shader 或研究资产。
- **定向修复过程。** 初次修复后的 24 项中一项新测试错误假定旧 ARSession.delegate 必须自动清空；核对真实生命周期后改为检查旧绑定回调被拒绝，未修改生产保护。随后 24/24 Passed。四项新增 ScanPlan 回归覆盖真实根 Coordinator/相机请求、实际 MetalView 初始/延迟预览及活动计划重绑、无效容量边界/固定 buffer 和被替换绑定的延迟回调；整份标准偏好与隔离仓储同时核对。
- **全量暴露的分享夹具问题。** 首次 full 为 1076/1077，随后单独 Share 类为 7/8，均在既有 failure 回调的 1 秒等待超时。临时追踪的三次独立启动中，首轮正确回调到 1.0926 秒、普通 FIFO 主队列探针到 1.0954 秒，后两轮为 0.2201/0.2027 秒；证明当时的首轮主队列积压影响人为注入事件，未把 PointerUI 日志当作已证具体根因。临时 trace 已全部删除，删除后的 Dashboard 文件先核对为轮前原摘要。最终只在原 Share 两方法和 preparation helper 中修改夹具：模拟 completion 前独立等一个排队的主队列 turn（5 秒准备门槛），回调自身仍保留 1 秒门槛、精确失败/取消结果和 legacy 无 completion 断言，并增加异步交付、主线程、过度 fulfill 断言。一个 turn 仅隔离此前排队工作，不声称整个 UIActivity 已可交互；生产 ShareSheet 未改。此范围为全量阻塞的必要修复，原 46/47 测试块逐字保持。
- **最后一次源码修改后的验证。** 32/32 定向方法 Passed；修正后的分享 failure/cancel 在三次独立启动中各执行一次，6 次执行通过（结果树为两个唯一方法，各含重复运行）。最终 `full`：**1077/1077 Passed、59 类、零失败/跳过/expected failure、9 步退出 0**，包括 24 文件 Domain 独立编译、全部当前 scheme XCTest 和 unsigned Release 模拟器构建。结果树明确核对四项新扫描方法及两项 Share 方法，受测 9 个源文件摘要与最终源码一致，runner 开始/结束工作区一致。结果包仍有两条 QoS runtime warning；第 47 轮也有两条，不把测试通过外推为真机调度/性能已验收。
- **原生与 UIKit 证据分列。** 专用 iOS 模拟器安装第 49 轮 App 后，先验证新建扫描入口取消；随后实际 Dashboard→QuickScan Q9330→ScanView“不支持 AR 扫描”提示→返回 Dashboard，并验证 Home 后回到同一提示页。原生截图标题、说明、返回按钮可读，未开始采集；真实 ScanView/MetalView 初始化、State 重建和完整配置断言由 UIKit 托管回归提供，托管画布不作为真实 GPU/深度画面证据。临时赋值只新增 fruitType 与 Q9330 的 TagStore.snapshot.v1；按 bundle 寻址清理首次未找到域且未写入，改用核验后的容器文件域成功清理。清理和重新启动后，全部 **11 个 Documents 文件 SHA 不变、整份 7 项原偏好恢复**。可连接的 LiDAR iPhone 未进行物理采集，本轮不宣称真机质量或峰值验收。
- **保护与复审。** 本轮为 7 个生产文件、2 个测试文件及本执行记录。除有意重叠的 Share 类外，11 个原 dirty 文件在写本记录前完全保留，其余 299 个 Swift 与轮前摘要相同；Dashboard 在 Share 类前后逐字相同，原 46/47/48 记录只在当前下一项更新和追加本节外保持。独立只读复审核对了 source、32 项/1077 项真实树、重复启动、六份托管附件、原生提示截图及文件/整份偏好保护，未发现源码范围阻塞。

证据目录 `/private/tmp/fruit-iteration49/`：`baseline.json`、`before.xcresult`、`after-repaired.xcresult`、两次原 Share 失败包、`share-timing-repeated.xcresult`/日志、`final-targeted-tests.json`/`final-targeted-method-evidence.json`、`share-prepared-repeated-tests.json`、`final-full-method-evidence.json`、`final-implementation-preservation.json`、`native-root-validation.json`、`native-scanview-unsupported.png`。最终 full 报告为 `fruit-code-improvement-myc1bj8n/report.json`；失败报告和中间失败均保留。收尾的 `final-source-preservation.json` 和 `final-review.json` 另存仓库外。

本轮 **mergeable**，未提交、未推送、未合并；原整体范围仍为 **needs changes / active**。本轮关闭的是根配置来源缺口，没有自动关闭 R1 的全部身份契约或 R5 的 GPU/物理资源验收。

### 下一轮构思与提示词：GPU 排空和失败回收

实际路径为 renderFrame 获取 3 个 in-flight permit 之一，完成回调释放；stagePointCloud 在 utility worker 排空全部 permit 后冻结最终点云。当前等待函数在超时时归还已取得 permit，但此前没有明确执行在途写入、部分取得后超时、重复排空或取消边界的故障回归。下一轮先建立这个现有生产边界的基线，再决定是否需要修复或仅补证据，不预判实现必有缺陷。

```text
继续 FruitTreeScanner 第50轮，读取AGENTS.md、工作流、原R0–R7核验与第49轮记录并preflight。
49轮根Coordinator、Renderer初始容量/预览和活动计划重绑已通过32定向、1077全量、
Domain24文件、Release与原生不支持AR提示/返回；原生11文件及整份7偏好恢复。
保护原六项工作流、46/47/48/49本地改动与Share夹具；不要自动提交或推送。
追踪renderFrame permit→commandBuffer completed→stagePointCloud utility worker→drain→freeze。
先用真实Renderer/实际semaphore建立通过基线，受控占用与释放permit模拟在途GPU，
不要在主线程阻塞等待，也不要把Semaphore逻辑测试称为真实Metal执行。
覆盖无在途、未完成时不提前冻结、完成后放行、部分取得后超时并全部归还、
超时后重复排空可继续、stage失败不发布文件/receipt，以及取消仍保留已发布receipt语义。
仅在有失败证据时修复最小根因；不得缩短/移除GPU排空、放宽permit数量或跳过故障测试。
如需让stage确定性地控制截止时间，接口必须沿用现有默认行为，避免另造副作用管线。
保持fixed capacity、plan/resourceBudget、仅fused准入、manifest最后发布、PLY字节及生命周期身份。
运行受影响lifecycle/storage定向、可行full/Release与独立只读复审；记录实际结果树。
源码与模拟permit证据不能替代真GPU完成状态、同设备峰值或物理绕拍；这些继续单列。
完成此边界后继续原领域算法/真实观测/资源目标，不将单轮通过当作整体完成。
```

## 第五十轮：GPU 完成屏障与资源回收回归

2026-10-05 建立基线和夹具，2026-10-06 完成最终门禁。上一轮为 progress：根配置改造完成；本轮继续其真实 GPU 排空证据缺口。HEAD 仍为 `33984237`，轮前 20 个 dirty 路径和 308 个 Swift 留存摘要/副本，preflight 通过。原 PointCloudProcessingTests 的 **136/136 基线 Passed、退出 0**。

- **问题与边界。** 正常结束先由 beginFinishingScan 关闭证据准入并停止 recording；renderFrame 获取三个 in-flight permit 之一，Metal 完成回调归还；stagePointCloud 的 utility worker 排空全部 permit 后才冻结和发布 PLY。已有代码包含部分取得后超时的归还逻辑，但旧回归没有直接证明在途 GPU 写入与这条实际 stage 路线。本轮处理这个验证缺口，没有将其预判为生产缺陷，也没有永久修改生产实现。
- **五项新增回归。** 同一个实际 Renderer 的 commandQueue、particlesBuffer 和 inFlightSemaphore 参与测试。SharedEvent 阻止真实 Metal blit 写入，stage 取得另外两个 permit 后握手确认等待，再检查无最终缓存、无发布文件、stage 尚未返回。释放 Event 后核对实际 command completed/nil error、FinalPointCloud 和重新解析的 PLY 均含新的四点/绿色，原来有效的四点/红色不能冒充结果；同时核对源 SHA 和文件身份。其余方法覆盖无在途和重复排空、timeout 0 的部分取得归还、取消后的精确 CancellationError/无发布及再次排空，三个 permit 全部恢复，第四次立即取得必须失败。
- **默认五秒超时的独立证据。** 真实 blit 已完成并进入 completed handler 后，用有界 CPU gate 延迟唯一 permit 归还；实际 stage 沿用生产五秒 deadline，精确抛 gpuDrainTimedOut，缓存与隔离目录仍为空。随后放行 callback，核对全部 permit 恢复并重试实际 stage/PLY 成功。CPU gate 自身截止为 15 秒，超时会使测试失败且仍由完成回调唯一归还 permit。此项证明完成回调尚持有资源时的排空超时，不能描述为 GPU 卡住五秒的验收。
- **夹具诊断和修正。** 首版在 body 前等待 scheduled 五秒，SharedEvent 无人及时放行，触发 Metal error code 2，结果 1/5、退出 65；这是夹具失败。移除前置等待后第二版为 2/5，三项失败来自已 fulfill 却未 wait 的 gpuCompleted expectation；按是否先等待选择剩余事件后五项全 Passed。Event 与 CPU gate 在成功、throw 和最终 defer 均放行，资源保持到有界完成等待结束；测试自身不额外 signal Renderer semaphore。异步上下文的 noasync 警告通过同步探针 helper 消除，未放宽断言或跳过 Metal 条件。
- **负控验证。** 临时把 makeFinalPointCloudSnapshot 移到 drain 之前，单个正向方法为 0/1 Failed、退出 65：提前缓存、旧坐标和红色 PLY 均被捕获。该人为变体不是原实现缺陷。变体和失败树保留仓库外，生产文件随后逐字恢复为 SHA `809f322f436fd1959e503d51e730c4bd35e5e0a7b34183c2bdc332cf0407a0e5`，正式门禁使用恢复后的源码。
- **全量反馈与最后修正。** 首次 full 已为 1082/1082、Domain/Release 全通过，但比上一轮多一条指向 assertAvailableRendererPermits 的主线程 QoS warning。真实回溯定位到夹具立即计数探针；将全部九处调用改 await，在 utility detached worker 中做原最多四次立即取得/逐一归还，并断言探针实际非主线程，expected 2/3 与重复归还拒绝保持。此后重新执行最终存储/生命周期与 full，未沿用改动前的通过报告。
- **最终证据。** `final-storage-lifecycle` 为 **521/521 Passed、25 类、零失败/跳过/expected failure、退出 0**，包含五 GPU 方法、发布后 owned receipt、取消与提交竞争、失败持久化 draft settlement 等精确路径。最后 `full` 为 **1082/1082 Passed、59 类、9 步退出 0**，包括 24 文件 Domain 独立编译与 unsigned Release 模拟器构建；runner 开始/结束工作区一致。五新方法与三项回执/提交/settlement 方法另存结果树核对。新增 PointCloudProcessing QoS warning 已消失，结果仍有两条 internal QoS warning，数量/消息与第 49 轮相同，具体来源和物理性能不外推。
- **保护与证据层级。** 本轮仅新增现有测试类中的 GPU 段和 MetalKit import，并追加本记录、更新当前下一项与顶部收尾日期。去掉新增段/import 后整份原文件逐字相同，136 旧方法和 helper 全部保持；其余 307 Swift、19 个非重叠 dirty 文件与历史记录重建核对保持。仓库外 Python 导入曾生成本轮单个 pycache，已只删除该缓存并关闭后续 bytecode 写入。fused-only、诊断、容量/预算、根配置、PLY/manifest 编码与发布后回执所有权均保持。本轮无 UI 变更，无新增原生走查或物理采集；手工真实 Metal 命令不等于执行 ARKit renderFrame，不证明 LiDAR 质量、进程峰值或物理完成/重试。

证据目录 `/private/tmp/fruit-iteration50/`：`baseline.json`、`task-card.md`、`baseline.xcresult`/方法树、两份夹具失败包、`final-new-tests.xcresult`、`mutation-freeze.swift`/diff/失败树、`final-storage-lifecycle.xcresult`/方法树。首 full 报告 `fruit-code-improvement-os_wdliy/report.json` 保留为中间证据；最终 full 为 `fruit-code-improvement-bt4dxx0_/report.json`。`final-source-preservation.json`、`final-full-method-evidence.json`、`final-review.json` 和 `validation-summary.json` 在收尾核对后另存。

独立只读终审已核对最后源码、521/1082 真实结果树、8 个精确关键方法、负控恢复和完整保护，未发现本轮阻塞；本轮 **mergeable**。未提交、未推送、未合并；原整体范围仍为 **needs changes / active**，R5 的物理资源与完整 AR 捕获验收继续开放。

### 下一轮构思与提示词：GPU 完成失败完整性

收尾复查发现优先级更高的 P1 候选：实际 RendererFrameRendering 在编码时推进 count/index/revision，完成回调忽略 commandBuffer.status/error，直接归还 permit；stage 只核排空和快照。首版手工 Metal code 2 之后也曾冻结旧粒子，说明需要补充“已完成但失败”的生产边界回归；这尚不是实际 ARKit 故障或新扫描污染的运行证明。同队列 FIFO/新扫描 prefix 覆盖会限制旧正常写入的影响，不能直接猜测污染后果。下一轮先共用实际生产完成注册入口建立行为等价基线，再用实际失败命令或明确完成结果注入复现；根据失败证据处理捕获健康状态与代际隔离，不能只比较最新 revision 而忽略同一扫描更早的失败。

随后恢复原 R4/R7 领域迁移候选：Core/FusionValidator.swift 的完整 Observation→投影/匹配→分配→决策编排仅依赖 Domain 纯值/数值服务，没有 buffer、Renderer、共享设置或日志，应按行为等价进入 Domain/Fusion 并更新实际 Xcode group/Sources，保持兼容入口与 fileprivate 可靠证据构造。后续可靠准入、composer、点云几何、真实观测和物理资源仍属于原目标。

```text
继续 FruitTreeScanner 第51轮，读取AGENTS.md、工作流、原R0–R7核验和第50轮并preflight。
50轮最终521存储/生命周期、1082全量、59类、Domain24与Release均通过；
真实Metal在途写入、部分归还、取消和默认5秒完成permit延迟已有明确范围证据。
保护原六项工作流、46至50本地改动，所有历史记录与五GPU回归；不要自动提交/推送。
追踪renderFrame/accumulate编码推进计数、实际completed handler、reset、stage/drain/freeze。
现有handler忽略status/error；它是P1候选，不能先声称已复现ARKit故障或旧scan污染。
先把真实完成注册入口共用，保持行为等价并验证50的五项基线；不要只测手工复制的回调。
用实际Metal失败或明确完成结果故障注入建立失败回归，再选择最小健康状态/代际修复。
要求失败仍唯一归还permit，当前capture写失败后禁止freeze/publish/receipt；
同capture较早失败不能被后续成功清掉，reset之后迟到旧失败/成功不能破坏新状态。
区分真正写入与仅绘制命令；捕获身份/健康状态沿既有锁和生命周期边界传递，
不能仅比较最新pointBufferRevision而漏掉同capture早先失败。
保留默认5秒、3permit、容量/预算、冻结plan、fused-only/诊断和发布后owned receipt。
执行受影响storage/lifecycle和关键GPU方法树、可行full/Release及独立只读复审。
保存最后源码/旧dirty保护、具体失败结果与恢复/重试证据，物理GPU/LiDAR另列。
关闭此边界后恢复纯FusionValidator进入Domain，随后继续原可靠准入/composer/几何、
真实回放和物理资源目标，不将单轮或单个Domain节点迁移当作整体完成。
```

## 第五十一轮：GPU 写入失败完整性与捕获代际隔离

2026-10-06。上一轮为 progress：完成真实 Metal/drain/stage 回归；本轮处理实际 producer 忽略终态错误的根因。轮前 21 个 dirty 路径、308 个 App/Tests/UITests Swift 的摘要与原始副本留存于 `/private/tmp/fruit-iteration51/`，preflight 通过，HEAD 仍为 `33984237`。

- **先建立基线和失败。** 将生产完成处理提取为共用入口，原五 GPU 回归 **5/5 Passed**，存储/生命周期 **521/521、25 类、退出 0**。随后明确注入 `.error` 终态结果，进入同一生产完成方法：两项回归均 **Failed、退出 65**，真实断言发现失败后仍能冻结旧四点/红色并发布 receipt，后续真实成功 blit 也仍能冻结/发布。这里是完成结果故障夹具，不是物理 ARKit 命令失败的复现。
- **实际写入与粘性健康状态。** accumulatePoints 在纹理 guard 后返回实际是否编码写入；短暂持有 pointBufferLock，将编码、index/count/revision 与捕获代际一致关联，完成处理器捕获不可变 generation/wrotePoints。仅当前代的写命令在 status 非 completed 或 error 非 nil 时使捕获失败，清除缓存；失败在唯一 signal 前记录，因此 CPU 排空之后必能观察到。后续成功或较新 revision 不清除同代失败。仅显示命令错误不毒化有效捕获；旧代成功/失败只归还自己的 permit，不能改新代健康、缓存或刷新时间。
- **reset、冻结与 stage。** reset 在既有 pointBufferLock → snapshotLock 顺序下推进 generation/revision，清健康状态与缓存/刷新节流；暂停/恢复仍保留同代状态。缓存命中、采样后的缓存写回及 live 时间预约均原子核对 generation/revision/health，锁不跨重采样、去噪或磁盘 IO。stage 在 detached worker 前固定 expected generation，沿用五秒、三个 permit 的排空，之后明确抛 gpuWriteFailed/captureChanged；不能把旧 stage 改为导出新捕获。已冻结值和发布后 owned receipt 仍由原所有者结算，没有在发布后追加取消/健康检查并丢失 receipt。
- **九项新增回归。** 覆盖失败禁止冻结/发布、失败后真实成功仍拒绝、已有最终缓存失效、同代较新 revision 不能遮住早期失败、reset 后迟到失败/成功不能动新缓存/时间、reset 后真实 Metal 成功立即产生绿色四点预览并可导出、仅显示错误仍可导出、completed 但 error 非 nil 仍拒绝，以及 stage 排空期间 reset 后精确 captureChanged/无文件/receipt。真实命令与 renderFrame 共用标准 pointCloudCommandCompletionHandler；四点 PLY、颜色、源 SHA、文件身份和三 permit 数仍核对。
- **复审反馈与验证范围修正。** 独立审查发现时间预约也需在两把锁下核对代际，已修复；恢复测试改为真实完成回调驱动首个 live 更新。夹具的异步加锁移入同步 helper，标准完成处理器避免测试捕获非 Sendable Renderer；没有增加 unchecked/Sendable 声明或屏蔽诊断。仓库外辅助 runner 首版只识别精确 `storage-lifecycle` 标签，两次 `final/verified-storage-lifecycle` 实际各仅 **150 项点云**，不能冒充 25 类 profile；修正标签选择并核对实际参数/结果树后才取得最终门禁，不削减任何测试。
- **最终证据。** 最后 `accepted-storage-lifecycle` 为 **530/530 Passed、25 类、14 项 GPU 关键方法、零失败/跳过/expected failure、退出 0**，runtimeWarnings 为空。正式 `full` 为 **1091/1091 Passed、59 类、9 步退出 0**，24 源 Domain 独立 iOS 16/Swift 5 编译及 unsigned Release 模拟器构建通过；原 owned receipt、取消与已提交持久化竞争和失败 draft settlement 精确方法也通过。报告为 `/private/tmp/fruit-iteration51/fruit-code-improvement-exftkzhp/report.json`，完整叶节点与当前源码摘要核对，无测试期间源码漂移。全量仍有两条与第 50 轮记录完全相同的内部 QoS warning；不能据此推断真机性能或警告根因。
- **保留与边界。** 本轮六个源码路径及本记录变化；302 个其他 Swift、18 个不重叠旧 dirty 路径摘要保持。重建可逐字恢复第 49 轮 Renderer 原改动、第 50 轮全部 141 测试方法和原 helper、第 50 轮及更早执行记录。固定容量、根配置/预算、仅 fused 可靠准入、诊断、编码与文件格式、manifest 最后发布和发布后 receipt 所有权保留。未提交、未推送、未合并；没有新增 UI 或真机交互证据。
- **决策与剩余风险。** 本轮所需底层门禁完成且独立复审无阻塞，决定 **mergeable**；整体原 R0–R7 仍 **needs changes / active**。真实 ARKit/LiDAR 故障、物理扫描/内存/耗时仍未验收。当前 workflow 把 gpuWriteFailed/captureChanged 统一折为 pointCloudExport，UI 仍提示存储错误并提供同捕获重试；底层会正确拒绝发布，但用户恢复链路尚未完成，列为下一轮 P2。之后继续原领域算法、可靠准入/composer/几何、全应用协作、真实观测与资源目标，不用此轮通过替代整体完成。

下一轮执行提示词：

```text
按默认改进工作流继续第 52 轮。先 preflight 并保护全部既有 dirty work。
沿 Renderer 导出错误 → ScanFinalizationWorkflow → ScanView+Export → 生命周期恢复
检查 GPU 写入失败被误当存储错误、同 capture 重试永远失败的实际路径。
先用实际 finish/export 入口建立失败分类和恢复动作的失败回归，再最小修复。
区分需要新扫描的 gpuWriteFailed、过期捕获和可重试的 GPU 排空/文件写入失败。
复用实际 coordinator/session identity 与恢复流程，不静默重置捕获或中断较新扫描。
提供准确本地化提示，保留旧 API、三个 permit、五秒排空、粘性健康状态、仅 fused
准入、冻结证据和发布后 owned receipt，不在 publication 后丢失结算句柄。
运行 lifecycle/storage、可行 full/Domain/Release，走查真实 iOS 模拟器恢复/导航，
独立只读复审并核对结果树/当前 SHA；物理 ARKit 故障与真机质量继续单列。
关闭这条恢复边界后继续原 FusionValidator 进入 Domain 和原 R0–R7 待完成项。
```

## 第五十二轮：无效点云错误路由与扫描恢复所有权

2026-10-06 至 2026-10-07。上一轮为 progress：第 51 轮的底层 GPU 健康/代际门禁已经关闭，本轮贯通其 Application 和用户恢复路径。轮前 preflight 通过，25 个旧 dirty 路径、308 个 Swift 源摘要及原始副本留存在 `/private/tmp/fruit-iteration52/`，HEAD/分支保持 `3398423774bf3f88f3fb4a732718a4e504a752fb` / `codex/variety-draft-concurrency`。

- **根因与失败证据。** 实际 Renderer stage 的 gpuWriteFailed/captureChanged 被统一折为 pointCloudExport，UI 提示存储错误并允许重试同一个不可用捕获。实际 finish/export 的两项路由回归先得到 **2 Failed、退出 65**；修复夹具参数顺序后，旧生命周期回调影响替换扫描与 failed phase 同步重入后仍发布旧失败的两项回归也得到 **2 Failed、退出 65**。夹具编译失败和原生 UIAlert accessibilityActivate 无法派发动作的失败另存，不能作为行为修复或实际触摸证据。早期 selector 写成不存在的 ScanLifecycleTests，只执行了 20 项其他测试，未算作生命周期验收；最终核对真实类 ScanLifecycleControllerTests。
- **错误分类与可重试路径。** ScanFinalizationWorkflow 新增 pointCloudCaptureInvalid，仅将写入失败/捕获过期归入该项；同捕获重试不可用，重复 finish 保持失败。gpuDrainTimedOut 和文件写入失败仍可用原扫描身份、原计划通过 finish/retry 重试并完成。fail 在发布 phase 后再次核对存储 owner 和 phase，同步 observer reset/cancel 后不发送旧 failed 事件；已发布 receipt 的结算与提交后持久化竞争路径保留。
- **实际 coordinator/session 与 UI。** ScanView+Export 将类型化失败交给只接受匹配身份、当前 finishing、未 teardown 的 coordinator；沿原失败路径关闭证据门、暂停采集并发布 invalidPointCloudCapture 生命周期，不静默重置底层捕获。恢复提示使用准确中英文文案，明确该采集无法估产、重新开始或放弃不生成结果。生命周期回调先核对当前完整 snapshot，排队旧事件不能取消新 workflow 或重新弹窗。
- **弹窗选择与重启失败。** 沿既有 presentation controller 模式保存扫描 owner、唯一 choice ID 与页面 binding。真实 alert 的按钮直接调用该选择并复用原 restart/discard；系统先清 binding 时仍可消费一次，旧选择、同步 dismissal observer 更换 owner/binding、页面失效和已完成扫描均拒绝动作。重启失败仍保留旧失败采集/计划和关闭的证据门，重新提供恢复选择；相机权限故障等待实际 readiness 后生成新选择，隐藏的旧动作无效。
- **实际触摸揭示并修复状态发布问题。** 第一版中文实际触摸两个按钮均通过状态断言，但 `.xcresult` 各有一次 SwiftUI `Publishing changes from within view updates is not allowed`。系统关闭 binding 改为下一次 main queue 执行，并核对捕获的 presentation ID；旧排队关闭不能隐藏已消费动作产生的新弹窗。新增 queued close → 立即 restart → 失败新 choice → drain → 新 discard 组合回归，以及隐式 Cancel 的撤销回归，没有屏蔽诊断或添加 unchecked Sendable。
- **原生 UI 验收范围。** 修复后中文外部真实触摸 **2/2 Passed、退出 0、runtimeWarnings=[]**。英文首包 Discard 实际点击通过，Restart 在锁屏等待触摸期间超时，整包为 **1 Passed + 1 Failed、退出 65**；解锁后 Restart 单独重跑，实际点击 **1/1 Passed、退出 0、runtimeWarnings=[]**，保留原失败包。四份状态 JSON 证明 restart 的 scan/plan ID 更新、capture generation 1→2、健康状态恢复；discard 为 cancelled/teardown、未产生结果文件。截图已检查原生 alert 文案和恢复后页面。这里挂载真实 ScanView 到隔离测试 host、使用生产按钮/Renderer 完成入口与明确故障夹具；放弃返回该 host，不冒充完整 Dashboard 或物理 ARKit 故障验收。临时等待触摸夹具恢复后，DashboardSummaryTests 与原常规测试备份逐字/SHA 相同。
- **工作流反馈。** 原 validate_summary 会接受上述实际 Passed + 非法发布警告。两个门禁回归先得到 **2 Failed、退出 1**；补上警告解析与精确已复现 SwiftUI 警告阻塞检查，运行全部 **36 项 Python 测试通过**，端到端失败报告保留原 test_summary/警告。再次输入真实原警告包也被拒绝。其他警告仍完整保存供复审，计数、选择类、失败/跳过及源码稳定规则未放宽，流程文档同步说明。
- **最终源码验证。** 常规测试夹具恢复后的 `accepted-storage-lifecycle` 为 **542/542 Passed、25 类、退出 0、零失败/跳过/expected failure、runtimeWarnings=[]**。正式 full 为 **1110/1110 Passed、59 类、9 步退出 0**，24 源 Domain 独立 iOS 16/Swift 5 编译及 unsigned Release 模拟器构建通过；19 项新增恢复/本地化回归、14 项原 GPU 方法与 5 项 receipt/取消/持久化结算方法在实际结果树中均 Passed。full 保留与第 51 轮消息完全相同的两条内部 QoS warning，没有新增非法发布警告。报告：`/private/tmp/fruit-iteration52/fruit-code-improvement-uwde7pcu/report.json`；完整方法、native 状态/源码与旧 dirty 保护核对：`final-method-preservation-evidence.json`。验证期间源码无漂移，最后 diff/staged diff 空白检查通过。
- **保留、复审与交付。** 本轮 8 个生产 Swift、2 个测试 Swift、2 个 strings、工作流/测试/流程文档及本记录变化；298 个其他 Swift、17 个不重叠旧 dirty 路径保持。两个测试文件、工作流旧内容及历史执行记录只追加，Renderer/Metal 和第 51 轮 GPU 代码/测试逐字保持；三个 permit、五秒排空、采样/容量/预算、冻结计划、仅 fused 可靠准入、全部诊断、历史编码与 manifest/owned receipt 规则保留。实现复审无明确阻塞，最后证据已核对。本轮决定 **mergeable**；未提交、未推送、未合并。真实 LiDAR、物理 GPU 故障、资源/耗时与果数精度继续单列，整体 R0–R7 仍 **needs changes / active**。

下一轮执行提示词：

```text
按默认代码改进工作流继续第 53 轮，先 preflight 并保护全部旧 dirty work。
第 52 轮恢复链路已关闭：542 定向、1110 全量、Domain24/Release、原生中英触摸
及警告门禁证据已记录，不重做 GPU 健康/错误分类或扩展 UI。
恢复原 R0–R7 领域化目标，检查 Core/FusionValidator.swift 的真实依赖与调用者。
它当前只使用 Foundation/CoreGraphics/simd、领域 Observation/候选/配置和纯融合服务。
先用当前 full 结果树建立对应融合/去重/估产基线，再按原文字节迁入 Domain/Fusion。
维持公共入口、checked Sendable、匹配/重分配顺序、阈值、置信度与深度拒绝规则，
不把平台缓冲/Renderer/设置/日志或额外 Core 源加入独立 Domain 编译来掩盖依赖。
PBX 只移动既有 file reference 的 group，Sources 引用仍恰好一次；检查消费者和兼容面。
Domain 全源门禁应由 24 变为 25，相关风险 profile、可行 full 和独立复审必须通过。
不要扩大 ReliableYieldEvidence 构造权限；仅 fused、诊断、格式、预算和旧 dirty 保留。
记录真实收益为依赖归属收敛，不宣称未测的性能提升或整体完成。
之后继续可靠准入/composer/几何、ScanPlan plot/tag、应用协作、真实观测与物理资源目标。
```

## 第五十三轮：纯融合编排纳入完整 Domain 门禁

2026-10-07。上一目标轮为 progress：第 52 轮恢复链路及非法状态发布门禁完成。本轮恢复原 R4/R7 领域边界目标，preflight 通过，轮前 33 个 dirty 路径、308 个 Swift 的摘要及原始副本保存在 `/private/tmp/fruit-iteration53/`；当前源码首先与第 52 轮最终实测摘要逐项吻合，HEAD/分支保持。

- **真实边界与调用链。** FusionValidator 的 Observation → 投影/匹配 → 全局分配 → 深度否决 → 验证结果仅依赖 Foundation/CoreGraphics/simd 和既有 Domain 值/服务。最终 FusionEvidencePipeline 和实时 confirmedLiveFruitCount 都调用 observations 入口；CVPixelBuffer/DetectedFruit 转换留在 Infrastructure/Detection/FusionValidatorLegacyInput.swift，Core 的投影兼容 extension 仍保留。纯编排位于 Core 使完整 Domain 编译无法覆盖它的依赖边界，这是本轮的架构根因。
- **迁移前基线。** 实际执行中央 fusion profile 的 12 个类及生产实时计数调用者 ScanLiveFruitCountTests，得到 **421/421 Passed、13 类、退出 0、零失败/跳过/expected failure、runtimeWarnings=[]**。独立原始结果树留存，不仅采用第 52 轮的汇总数量。
- **逐字迁移与工程结构。** 将 Core/FusionValidator.swift 原文字节移至 Domain/Fusion/FusionValidator.swift，SHA 保持 `7068ed4141820c58865537d516254372a298b4fc17beff6194cefc321b903deb`。PBX 结构化比较只有 Core 与 Domain/Fusion 两个 group 的 children 变化；原 fileRef `FUSIONVAL987654321`、buildFile `FUSIONVAL279228`、App Sources phase 保持，在唯一 FruitTreeScanner target 中恰好一次。没有重复类、改变 public/internal 入口、改阈值/置信度、重排匹配或引入平台缓冲。
- **迁移后验证。** 全部 **25 个 Domain 源**独立编译为 iOS 16 simulator / Swift 5，原递归全源 gate 未修改、未加入 Core/App/legacy 源掩盖依赖。after-fusion 为 **421/421、13 类、退出 0、runtimeWarnings=[]**，与迁移前全部方法标识/Passed 结果相同。正式 full 为 **1110/1110 Passed、59 类、9 步退出 0**，Domain25 与 unsigned Release 模拟器构建通过；原始树方法集合与第 52 轮完全一致。四类关键消费者的 93 项 validator、完整观测/存档/批量回放、builder 与实时计数方法逐项 Passed；既有固定质量/置信度及 rejected/low-depth/copyFailed/imageOnly/cloudOnly/重分配断言保持。full 两条内部 QoS warning 消息与第 52 轮完全相同，没有新增非法发布警告。
- **保护与复审。** 307 个其他 Swift 逐字保持，迁移文件本身逐字保持，全部 308 个源归一化旧/新路径后摘要相同；32 个不重叠旧 dirty 路径与第 52 轮源/测试/工作流改动保持。执行记录仅追加，最后 diff/staged diff 空白检查通过；验证时工作区没有漂移。独立初审未发现阻塞，工程引用、依赖闭合及最终证据已核对。`fileprivate` 可靠证据构造仍在原 Core 管线内，本轮没有扩大权限或声称该准入已经领域化。
- **证据、收益与决策。** 正式报告 `/private/tmp/fruit-iteration53/fruit-code-improvement-3wgvjcqr/report.json`；前后树、唯一 Sources 证明、93 项关键方法与全源保护位于 `/private/tmp/fruit-iteration53/` 的 `before-fusion-method-evidence.json`、`after-fusion-method-evidence.json`、`project-move-evidence.json`、`final-method-preservation-evidence.json`。实际收益是独立 Domain 门禁开始覆盖完整纯融合编排；没有性能测量或新的物理/原生 UI 验收。本轮 **mergeable**，未提交、未推送、未合并；整体 R0–R7 仍 **needs changes / active**，不能把一个编排节点的迁移当作整体完成。

下一轮构思：ReliableYieldEvidence、FusionEvidencePipelineOutput 与 observations 版准入/保守输出依赖已是领域值；剩余阻碍是同文件混入的 DetectedFruit/resolvedObservation 旧缓冲入口和 Log.fusion.warning。可靠构造器与真正准入实现必须同处领域文件，继续保持 fileprivate 和 `.fused` 检查。日志应由明确领域原因值在现有编排/兼容边界消费，保留原生产告警语义；不能删除日志、注入空 logger 或把 Core Log 纳入 Domain。PointCloudCandidatePipeline、混合 CategoryFilter、composer 和物理资源缺口继续按依赖顺序单独处理。

下一轮执行提示词：

```text
按默认工作流继续第 54 轮，先 preflight、保护旧 dirty work并读原 R0–R7核验。
第 53 轮 FusionValidator 已逐字进入 Domain：before/after421、full1110/59、
Domain25/Release和唯一Sources证据已完成，不重做该迁移或改变匹配/深度阈值。
追踪 Core/ScanFusionPipelines 的 ReliableYieldEvidence、FusionEvidencePipelineOutput、
observations版run/conservativeOutput及 builder/FruitCounter/composer/diagnostics 消费者。
用实际当前管线和完整回放建立通过基线，按完整责任边界迁入同一 Domain/Fusion 文件。
构造器/fruit仍fileprivate，仅原准入代码能从明确fused结果构造可靠证据。
保留无观测、无对齐深度、无稳定检测、无验证、无fused各分支的原返回计数/证据/保守状态。
DetectedFruit入口沿既有Infrastructure兼容extension仅转换为Observation，再调用纯入口。
明确结构化的无对齐深度原因值契约；现有builder/兼容边界据它保留原warning条件与文字，
空观测、仅不稳定或其他保守原因不能误报缺少对齐深度。不要用平台logger或空闭包伪装隔离。
不要整份搬迁混合点云管线，不增加Core源进入Domain gate，不扩大可靠构造权限。
检查新文件App Sources恰好一次、旧入口兼容、输出/schema/zeroYield与调试诊断保持。
验证构造器在文件外不可调用，并证明正常外部消费者仍可读可靠结果。
执行受影响fusion/实时计数、完整回放及full/Release；核对关键方法真实树与最终摘要。
独立复审、关闭本轮后，再推进结果合成/几何、Plan plot/tag、应用协作、真实观测与物理资源。
不宣称目录变化带来未测的内存/性能提升，也不标记整体完成或自动提交推送。
```

## 第五十四轮：可靠估产准入与结构化原因纳入 Domain

2026-10-07。本轮继续原 R4/R7 领域边界目标，处理可靠证据构造与数值准入混在平台兼容/日志文件中的依赖问题。仅关闭该责任边界，整体 R0–R7 仍 **needs changes / active**。

- **完整责任边界。** `ReliableYieldEvidence`、`FusionEvidencePipelineOutput`、observations 版准入和保守返回进入 `Domain/Fusion/ReliableYieldEvidence.swift`。原可靠类型正文逐字保持，fruit/构造器仍 fileprivate，仅 `.fused` 可以构造；对齐、稳定检测、二维去重、验证、先隔离 fused 后三维去重的顺序及所有阈值保持。原 Core 点云/深度/分类管线正文保持，只移除未使用的 os import。DetectedFruit 入口沿既有 Infrastructure extension 转换为 Observation，公共调用兼容。
- **诊断契约。** 无对齐深度的非空输入返回明确的 `FusionEvidenceDiagnostic.missingAlignedDepthContext`；builder 的现有 diagnostics updater 和旧输入兼容边界消费它，保留原告警条件及文字。空输入、只有不稳定证据或没有匹配结果不误报该原因。既有计数、证据数组、保守标志、zeroYieldReasons 和结果格式保留，增加三项分支/兼容回归。
- **全量暴露的测试竞争。** 本轮首次全量的历史工具输出为 1112 Passed/1 failed、退出 65：Dashboard 批量导出测试读到刚创建的 0 字节 CSV。沿真实链确认服务完成、源验证及请求身份复核后才发布 UIActivityViewController；测试仅增加八行等待真实分享界面，CSV 精确数据及完整原档字节断言均保持。没有改生产导出、固定延时或放宽断言。工作流补上异步写出完成边界规则。
- **证据丢失与恢复边界。** 后续全量中断后，进程句柄缺失，OS 检查原进程不存在，`/private/tmp/fruit-iteration54` 原证据也已消失。上述首次失败及早期通过仅记为历史观察，不声称原结果包仍可读取，也不将中断全量算作通过。依据此前实际打印的 SHA 和未变 HEAD 重建轮前 308 Swift 快照，全部摘要匹配；32 个不重叠旧 dirty 及执行记录追加前的原文保持，303 个其他 Swift 保持。新增持久证据规则，当前原始结果重新取得并保存到仓库外 `Library/Logs`。
- **当前可复核验证。** 重建轮前快照实跑 **421/421、13 类**；当前融合/实时计数加既有导出用例实跑 **425/425、14 类**，两者退出 0、runtimeWarnings=[]，旧 421 方法全部保留，新增选择恰为三项融合回归及一个既有导出方法。正式 full **1113/1113、59 类、9 步退出 0**，零失败/跳过/expected failure，Domain **26 源、iOS 16 simulator/Swift 5** 与 unsigned Release 模拟器构建通过。结果树中 96 项 validator、观测回放、builder 和实时计数关键方法逐项 Passed。两条内部 QoS 警告完整保留，文字与历史观察一致；旧原包已丢失，未声称重新逐包对比。没有非法状态发布警告。当前实际 CSV 附件 186 字节，ROOT41 PLOT/BATCH42/7/1.25 与总计正确，SHA 为 `952325e7c98de7913044c5171a2bb3b12803420aa1d5ff81cbe99c428241e6e7`。
- **工程、权限与复审。** PBX 结构化比较只有两个新对象及 Domain/Fusion、App Sources 两个既有对象追加，旧引用保持，新源只进入 App 一次。独立文件读取可靠结果编译成功；尝试构造被编译器明确以 fileprivate 拒绝。验证期间源码未漂移，原类型字节、旧 dirty 和未改源码摘要已核对，diff/staged diff 空白检查通过，暂存区为空。独立只读复审未发现准入、告警、兼容或导出断言阻塞问题；当前 full 原始树和全部九步成功已另行复核。
- **证据与决策。** 持久根为 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration54-20261007/`；正式报告 `fruit-code-improvement-sinpti36/report.json`，原始 before/after `.xcresult`、`recovered-baseline.json`、`boundary-and-project-evidence.json`、`final-method-preservation-evidence.json` 和导出附件均在该根。实际收益是可靠准入纳入完整 Domain 门禁，未测内存/性能收益不作宣称。无新 UI 或真机质量验收，本轮 **mergeable**；未提交、未推送、未合并。物理深度、真实观测回放、资源和最低系统运行仍待验收。

下一轮构思：可靠准入已有受限领域输入，真实 composer 仍调用 Core 的 FruitCounter 和 ScanYieldEstimateHelpers，后者依赖三份 SimpleFruitGeometry 与 FruitEstimationQualityScorer。六个文件构成计数、可见重量及几何质量的纯数值依赖闭包，应一次迁移完整责任边界。composer 本身还依赖混合 Input、ColoredPoint、遮挡/树冠与 Core 诊断，暂不整份迁移或制造空接口。

下一轮执行提示词：

```text
按默认工作流继续第 55 轮，先 preflight并保护所有旧dirty，核对原R0–R7范围。
第54轮可靠准入已领域化：当前before421/after425、full1113/59、Domain26/Release，
原始证据在Library/Logs/FruitTreeScanner/refactor-iteration54-20261007；旧tmp包不可用。
追踪composer→FruitCounter可靠计数→ScanYieldEstimateHelpers可靠可见重量与质量，
及SimpleFruitGeometryEstimator/Metrics/Categories、FruitEstimationQualityScorer依赖。
以本次实际通过full的源摘要/方法树建立六文件整体迁移基线，保留全部原文字节。
将完整纯计数/重量/几何质量责任纳入Domain/Yield，维持既有入口、权限及兼容重载。
保留候选显式ID优先/只消费一次、旧10cm严格空间回退、品类一致、权重/取整、
平均重量fallback和人工复核提示，主轴/分位跨度/球拟合/密度/阈值/Date/UUID全保持。
不得让imageOnly/cloudOnly进入可靠产量，也不得扩大ReliableYieldEvidence构造权限。
PBX移动既有file references，Sources条目与target归属不变且每个源恰好一次。
独立Domain全源门禁不得排除新源或借入Core；按实际闭包预期26增至32，实测确认。
核对FruitModelsTests、YieldEstimatorTests、builder、完整观测/存档/批量回放和实时计数，
运行受影响定向及full/Release，逐项对比前后方法/固定数值断言和源摘要，独立复审。
composer混合输入另行设计领域值，不把整份混合编排直接搬进Domain伪装闭合。
关闭本轮后继续Plan plot/tag、应用协作、真实观测与物理资源目标；不宣称整体完成，
不自动提交、推送或合并，也不以目录迁移声称未测的资源收益。
```

## 第五十五轮：计数、可见重量与几何质量的完整领域依赖闭包

2026-10-07。第 54 轮已以当前持久原始结果及独立终审关闭；本轮继续原 R4/R7 算法领域边界，preflight 通过。轮前 41 个 dirty 路径、309 个 Swift 摘要和六文件原文留存于仓库外持久目录；HEAD/分支保持，暂存区为空。

- **根因与完整范围。** 生产 `YieldResultComposer` 以可靠证据调用 FruitCounter 计数和 ScanYieldEstimateHelpers 估算可见重量；后者依赖三份 SimpleFruitGeometry 和 FruitEstimationQualityScorer。六文件只依赖 Foundation/simd 与既有 Domain 值，却位于 Core，独立 Domain 门禁无法覆盖这条计数/重量/质量链。将六文件整体逐字迁入 `Domain/Yield`，不拆出额外空接口。composer 的混合 Input、点云、遮挡和诊断编排仍待后续设计，本轮没有将其整体搬迁。
- **行为与兼容保持。** 六个源的原文字节全部相同；生产 count/weightedTotal/computeYieldFromReliableEvidence 仍只接收受限 ReliableYieldEvidence。旧 ValidatedFruit 重载继续用于兼容和诊断，fileprivate 准入权限未扩大。候选显式 ID 优先、单次消费、严格 10 cm 旧空间回退、品类一致、权重/取整、均重 fallback/人工复核，以及主轴、分位跨度、球拟合、密度、质量阈值、Date/UUID 语义均保持；没有行为变更或为迁移新写镜像测试。
- **工程与旧工作保护。** PBX 只新增 `ARCHYIELD001` group，并修改 Core/Domain 两组的 children；原六个 fileRef、buildFile 和全部 Sources phases 对象保持。各源仍只在原 App target 出现一次。309 个 Swift 归一化路径后摘要完全相同，303 个未迁移源逐字保持；40 个非 PBX 旧 dirty 在验证期间保持，最终仅追加本执行记录后，其余 39 个旧 dirty 仍保持。递归 Domain gate 原文未修改，没有排除新源、引入 Core 源或放宽规则。
- **前后真实验证。** 迁移基线使用刚完成的第 54 轮持久 full：1113/1113、59 类、九步退出 0，迁移前 App/Test/工程/验证源摘要全部与它的受测值匹配；追加交付文档不影响该源码基线。迁移后定向 **424/424、13 类、退出 0、runtimeWarnings=[]**，与原树中相同选择的完整方法集合一致。全部 **32 个 Domain 源**独立编译为 iOS 16 simulator/Swift 5。正式 full **1113/1113、59 类、九步退出 0**，零失败/跳过/expected failure，unsigned Release 模拟器构建通过；前后全量 1113 个唯一 Passed 方法完全相同。FruitModels 126、YieldEstimator 45、FusionValidator 39、builder 42、完整观测回放 9、实时计数 6，共 **267 项**关键消费者方法逐项 Passed。两条内部 QoS 告警与本轮持久基线的原文一致，无非法状态发布告警。
- **复审、收益与决策。** 独立只读初审及终审均无阻塞，逐字迁移、真实生产入口、纯依赖闭合、PBX 唯一归属、当前定向/full 原树、267 项关键方法及最终源码/文档保护均已核对。验证期间工作区未漂移，最后 diff/staged diff 检查通过。实际收益是完整纯计数/重量/几何质量责任纳入独立 Domain 编译，源码数量和算法实现未减少，未宣称性能/内存收益。证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration55-20261007/`，正式报告 `fruit-code-improvement-uoah4bo_/report.json`；`baseline.json`、`originals/`、`move-and-project-evidence.json`、`after-fusion-method-evidence.json`、`final-method-preservation-evidence.json` 保留原文和真实方法树。本轮 **mergeable**，未提交、未推送、未合并；整体 R0–R7 仍 **needs changes / active**。两条内部 QoS、真实观测、物理深度/资源和最低系统运行仍开放。

下一轮构思：CanopyGeometryEstimator 与 OcclusionCorrector 的数值核心只依赖领域配置及 ColoredPoint；后者实际是四个不可变字段的 checked Sendable 值，却与 SceneKit 的 PointCloudData/展示模式定义在同一 Core 文件。先将纯点值和两项几何/遮挡责任纳入领域闭包，可保留原数组和所有调用入口，避免为隔离生成额外大数组或协议。之后再处理 composer 的混合输入与本地化诊断契约。

下一轮执行提示词：

```text
按默认工作流继续第56轮，先preflight并保护旧dirty，读取原R0–R7核验与本轮记录。
第55轮六文件已逐字进入Domain/Yield：before/after full1113/59方法一致，
after424/13、Domain32/Release通过；持久证据在Library/Logs/FruitTreeScanner。
追踪Core/PointCloudDisplayModels中的ColoredPoint与CanopyGeometryEstimator、
OcclusionCorrector及builder/composer/点云展示/导出消费者，不按文件名猜测试类。
ColoredPoint是pos/r/g/b四个let字段的checked Sendable纯值，保持正文、成员初始化器、
布局和API，把它从SceneKit展示文件分离到Domain；其余展示类型和平台依赖保留。
确认两项算法闭包后整体逐字迁入Domain，保留ColoredPoint数组入口与positions入口。
不新增大型数组映射、第二套点表示、空协议或unchecked Sendable来伪装隔离。
保留树冠地面/树干/相邻簇过滤、局部原点、稳健分位、1500采样、120000投影格、
512分区及全部原边界；遮挡半径/深度/36分箱、证据可靠性和校正上限全保持。
仅fused参与可靠估产、低置信度/拒绝深度不升级、zeroYield和诊断/格式保持。
用当前真实full与源摘要建立基线，PBX原引用移动，新纯点文件App Sources唯一一次；
Domain全源gate原文不变，预期32增至35并实测，不借入Core或SceneKit。
覆盖PointCloudProcessingTests中的真实树冠方法、OcclusionCorrectorTests、
YieldEstimatorTests、builder与完整观测/存档/批量回放，运行定向及full/Release。
对比字节、固定结果、完整方法树和旧dirty，独立复审；遇到行为缺陷另立失败回归，
不在纯迁移里顺手改阈值。关闭后设计composer领域输入/诊断边界，继续Plan plot/tag、
应用协作、真实观测与物理资源；不宣称整体完成或未测性能，不自动提交推送合并。
```

## 第五十六轮：纯点值、树冠几何与遮挡校正的领域闭包

2026-10-07。上一目标轮完成第 54/55 轮迁移和验证，属于 progress。本轮继续原 R4/R7 领域目标：preflight 通过，当前 App/Test/工程/验证源摘要与第 55 轮持久 full 的最终受测摘要完全一致，执行记录也与其交付摘要匹配。轮前 53 个 dirty 路径、309 个 Swift 摘要及本轮原文保存到仓库外持久目录；HEAD/分支保持，暂存区为空。

- **真实根因与责任边界。** builder 直接计算树冠，composer 通过遮挡算法计算冠层半径、深度和覆盖；这些算法只需要纯数值及领域配置，但 ColoredPoint 定义在 SceneKit 展示文件中，阻碍完整 Domain 独立编译。ColoredPoint 实际为 pos/r/g/b 四个不可变字段的 checked Sendable 值。本轮将其原声明分离到 `Domain/PointCloud/ColoredPoint.swift`，并将 CanopyGeometryEstimator、OcclusionCorrector 整份逐字迁入 `Domain/Yield`。
- **保留与资源。** 两项算法原文字节、点值声明、字段顺序、成员初始化器及 Sendable 保持。PointCloudDisplayModels 的其他展示类型原文保持，仅提取该声明并移除未用 simd import；SceneKit 仍留在展示边界。保留原 ColoredPoint 数组/positions 入口，没有额外映射、大数组拷贝、第二套点表示或空接口。树冠过滤、局部原点、分位跨度、1500 采样、120000 投影格、512 分区，以及遮挡分箱、证据可靠性、公式和上限均未修改；仅 fused、置信度/拒绝深度、zeroYield、诊断与格式保持。
- **工程和源码保护。** PBX 结构化比较只新增纯点 fileRef/buildFile 和 PointCloud group 三对象，修改 Core/Domain/Yield/App Sources 四对象；所有原 fileRef/buildFile 保持，旧 Sources 列表只新增纯点一次。新点、两算法及原展示源均只归属原 App target。310 个当前 Swift 中，306 个未迁移源逐字保持，加上两项逐字算法共 308 个旧源归一化路径后相同；点声明和保留展示部分分别核对。验证期间 52 个非 PBX 旧 dirty 保持，最后仅追加本记录后其余 51 个旧 dirty 保持。Domain gate/工作流原文未改，没有排除新源或借入 Core/SceneKit。
- **通过基线与定向。** 使用刚完成且当前源码匹配的第 55 轮实际 full 原始树建立迁移基线，选中央 fusion、实时计数及 PointCloudProcessingTests，得到真实基线 **574 个 Passed 方法、14 类**。迁移后独立执行同样选择，**574/574、14 类、退出 0、runtimeWarnings=[]**；前后方法标识与 Passed 结果完全一致，未删除/放宽现有测试。独立 Domain 全源编译覆盖 **35 源、iOS 16 simulator/Swift 5**；另外一个文件使用原成员初始化器读取所有字段并要求 Sendable，独立类型检查退出 0。
- **完整验证。** 正式 full **1113/1113、59 类、九步退出 0**，零失败/跳过/expected failure，Domain35 与 unsigned Release 模拟器构建通过；前后完整 1113 个唯一 Passed 方法一致，574 项定向均包含于 full。八类关键消费者共 **431 项**：FruitModels126、YieldEstimator45、FusionValidator39、builder42、完整观测回放9、实时计数6、PointCloudProcessing150、OcclusionCorrector14，逐项 Passed；真实树冠方法和既有固定数值/存档/批量断言保持并执行。两条内部 QoS 告警消息与持久基线一致，原始警告完整保留，无非法状态发布警告。验证期间源码没有漂移。
- **复审与证据。** 独立只读初审及终审均无阻塞，确认纯依赖、原文、API、数组和工程归属，并核对当前 full 原树、314 项受测摘要、51 项其他旧改动、仅追加记录及下一轮设计契约。最终源码摘要及 diff/staged diff 空白检查通过。证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration56-20261007/`；正式报告 `fruit-code-improvement-fprp1e3c/report.json`，`baseline.json`、`originals/`、`move-and-project-evidence.json`、`point-consumer-command.json`、`targeted-method-evidence.json`、`final-method-preservation-evidence.json` 保存原文/命令/实际原始树。本轮 **mergeable**，未提交、未推送、未合并；实际收益为纯点值及几何/遮挡依赖进入独立 Domain 门禁，不宣称未测的性能/峰值内存收益。

整体 R0–R7 仍 **needs changes / active**。composer 的混合数值/装配、结构化零产原因、点云编排、Plan plot/tag、应用协作、真实观测和物理资源/最低系统运行缺口继续保留。

下一轮构思及可直接使用的提示词见 [数值估产评估与结果装配边界设计](YIELD_ASSESSMENT_DESIGN_2026-10-07.md)。拟交付正产、成熟零产、非成熟未标定三分支的完整纯数值评估，现有 facade 保持冻结身份、展示/诊断文字及结果格式适配。设计明确保留两次取整、零权重分支、显式 nil 校准上下文和各分支缺省字段；第 57 轮尚未实施，不将设计稿算作已关闭缺口。

## 第五十七轮：纯数值估产评估与三分支结果装配

2026-10-07。上一轮已完成第 56 轮纯点值/几何/遮挡迁移与验证，属于 progress。本轮继续原 R4/R7 领域责任收敛：preflight 通过，轮前 310 个 Swift 与第 56 轮 full 的 314 项受测摘要、执行记录交付摘要均匹配；60 个旧 dirty 路径和本轮原件保存到仓库外持久目录。HEAD/分支保持，暂存区为空。

- **根因与改动。** Core composer 原本同时依赖旧 builder 输入、点云管线输出、诊断/本地化和校准上下文查询，并执行计数、重量、覆盖、遮挡、校准数值及质量规则。本轮新增 Domain `YieldAssessmentInput` / 不可变评估输出与具体 evaluator，接收现有点数组、目标聚类点、受限 ReliableYieldEvidence、证据观测、候选和冻结参数，负责完整数值评估。新增 `YieldOcclusionCalculator` 接收原完整覆盖函数块，仅调整入口访问级别，其余原文保持。现有 composer 保留入口/API，适配冻结身份、展示字段、诊断/说明及 YieldResult 格式。未标定季节使用独立领域评估入口，只计算树冠和空计数，仍在聚类/融合前返回。
- **精简与保留。** 移除迁移后无消费者的 `VisibleEstimateCorrection` 六行声明；其余重量 helper 原文保持。保留加权正数而分类取整为零时的正产分支、先遮挡取整再校准取整、Float 重量乘法顺序及校准前基线。目标点覆盖保守下界、同类别/最近位置/二维关联、失效深度禁止二维回退及全部阈值保持。可靠入口仍只接受 fused 准入值，fileprivate 构造权限未扩大；候选身份/一次消费和缺失几何平均重量规则保持。捕获 identity 存在且 context=nil 仍为 nil，只有原正产且无 identity 路径计算兼容上下文。成熟零产及未标定季节不额外填入原本为空的校准/cluster 字段；原原因顺序、说明、诊断与 schema 保持。共享现有数组/COW，不新增整云转换，不宣称物理内存收益。
- **基线与复审修复。** 先在原实现固定两次取整、几何缺失平均重量、正权重/rawCount0、成熟零产校准字段缺省和未标定季节默认值，原实现及迁移后各 **577/577、14 类、退出 0、warnings=[]**。首次基线编译发现两处新测试参数顺序错误，已修复，失败原日志保留。独立复审指出非空可靠集合但权重为零的分支缺少契约；通过真实 FusionEvidencePipeline 的零 confidence/显式零 minConfidence 取得该证据，不伪造构造器。仅暂时恢复本轮 composer/helper 到轮前原件摘要，原实现新回归 **1/1 Passed、退出 0、warnings=[]**，随后恢复最终实现；最终 **578/578、14 类、退出 0、warnings=[]**，方法集合精确等于原 577 加该 1 项。零权重计数结果保留原始证据，YieldResult 走成熟零产并保持正产字段 nil/数组空。
- **工程与完整验证。** 工程结构化核对只新增两个 fileRef/buildFile 四对象，修改 Yield group 与原 App Sources 两对象，新源均唯一归属 App；其余工程对象保持。完整 Domain **37 源、iOS 16 simulator、Swift 5** 独立编译通过，门禁/runner/工作流未改。正式 full **1117/1117、59 类、九步退出 0**，无失败、跳过或 expected failure；unsigned Release 模拟器构建通过。第 56 轮全部 1113 个 Passed 方法保留，新增 4 个契约均执行，最终 578 项定向完整包含于 full；全部观测回放 9 项、原校准 canonical bytes、存档/批量回放和相关数值断言均通过。两条内部 QoS 告警消息与原全量基线一致，无非法 SwiftUI 发布告警。最终 316 项受测摘要一致，验证期间没有源码漂移；307 个其它旧 Swift 逐字保持，最终其余 55 个旧 dirty 路径保持，历史记录仅追加、57 设计仅更新状态。
- **证据与结论。** 持久根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration57-20261007/`；正式报告 `fruit-code-improvement-jzzhfr8i/report.json`。`baseline.json`、`originals/`、`before-methods.json`、`zero-weight-before-command.json`/原始单方法结果包、`after-zero-methods.json`/原始定向包、`wrapper-removal-evidence.json`、`final-method-preservation-evidence.json` 与 `delivery-evidence.json` 留存完整原件/方法树/源码保护证据。独立复审的 P2 已关闭，最终无阻塞发现；本轮决定 **mergeable**。本轮未提交、未推送、未合并。

下一轮范围与可直接使用的提示词见 [结构化零产原因与原格式适配设计](ZERO_YIELD_REASON_DESIGN_2026-10-07.md)。现有 ScanDiagnosticsBuilder 仍把事实判断与本地化字符串混合；设计明确保留动态深度文本与 noDetections 相同导致的旧 cloudOnly 抑制、原因顺序、旧导出/UI 建议及未标定早返回，不把尚未实施的第 58 轮算作完成。

Release 中四处既有 shared 主 actor 隔离编译告警与第 56 轮的文件/行号/消息完全一致，原日志完整保留；当前工程使用 Swift 5，迁入 Swift 6 前仍需单独修复这些入口，不把现有告警算作已解决。

本轮证据归档 helper 曾因匹配 `before-*`，把固定 full 基线副本与首次编译失败尝试一起移入失败归档，原件始终保留。收尾已缩小为明确的尝试文件清单；固定副本从原正式日志恢复，原日志、归档副本和恢复副本 SHA-256 一致，原始方法证据没有丢失或重建。

整体 R0–R7 仍 **needs changes / active**。结构化零产原因、点云编排、Plan plot/tag、Dashboard/批量应用协作、真实观测持久回放和物理资源/最低系统运行验收继续开放。

## 第五十八轮：结构化零产原因与旧文本适配

2026-10-08。上一轮第 57 轮已完成实现、完整验证与复审，属于 progress。本轮继续原 R4/R7 的诊断责任收敛：preflight 通过，第 57 轮 316 项受测摘要与交付记录/设计摘要匹配；轮前 312 个 Swift、64 个旧 dirty 路径与本轮原件保存到仓库外持久目录。HEAD/分支保持，暂存区为空。

- **根因与改动。** 原 `ScanDiagnosticsBuilder.zeroYieldReasons` 同时判断模型/深度/点数/检测/候选/融合事实并生成本地化文字，未标定季节原因另在 composer 中直接写入。本轮新增 Domain `ZeroYieldReason` 与纯分类策略，接收现有值诊断和明确最小点数，返回有序原因；不导入 L10n、平台缓冲、模型服务或文件系统。Core facade 的原签名保持，新适配函数将领域原因映射为旧 `[String]`。未标定评估增加明确原因值，composer 仅替换一处原因来源，仍在聚类/融合前早返回。
- **兼容与精简。** 原事实条件和顺序逐段核对一致。Domain 按 cloudOnly 模式且 fused 为零给出候选原因，Core 对前序字符串数组保留原元素等值 `contains` 抑制。动态深度文本恰好等于 noDetections 时仍抑制，只有子串或带后缀空格时不抑制；不反向解析文字、不去重、不 trim。动态/正式原因即使相等仍各保留一项，原前缀、分隔符、空 fallback、未标定专用中文均保持。诊断初始化与 note 函数原文保持，所有旧测试原文保留；只拆事实与格式适配，没有第二套状态。仅 fused、零权重分支、低置信度/拒绝深度否决、两次取整、校准身份、字段缺省及旧存档/研究 schema 保持。
- **原实现基线。** 先在原实现加入六项契约：组合原因顺序、动态文本元素相等/仅含子串/尾部空格、重复正式原因、最小点数严格边界、健康空数组/default note、动态空白/空字符串区别。迁移前 **584/584、14 类、退出 0、warnings=[]**。迁移后追加三项领域契约，分别验证有序结构化事实、cloudOnly 候选不解释动态文本，以及未标定原因与原说明适配；最终定向 **587/587、14 类、退出 0、warnings=[]**。原 578 项及六项原实现契约全部保留，新增仅三项结构化契约。
- **完整验证。** 完整 Domain **38 源、iOS 16 simulator、Swift 5** 独立编译通过，门禁/runner/工作流未改。正式 full **1126/1126、59 类、九步退出 0**，无失败、跳过或 expected failure，unsigned Release 模拟器构建通过。逐方法树证明原 1117 项全部保留，新增九项精确对应本轮契约，587 项定向完整包含于 full。关键九类 343 项、全部观测回放 9 项、原校准 canonical bytes 与存档/批量回放均通过。两条内部 QoS 运行时告警的数量及 message 与第 57 轮相同，本次第二条另有 DashboardSummaryTests.swift 的 sourceURL；四处主 actor 隔离编译告警的位置/message 集合相同，原日志的重复输出保留。无非法 SwiftUI 发布告警，既有告警没有被当作已解决。
- **保护与复审。** 最终 317 项受测摘要一致，验证期间工作区无漂移；308 个其它旧 Swift 逐字保持，记录更新后其余 59 个旧 dirty 路径保持。工程只增加新文件的两个引用对象并更新 Yield group/App Sources，新源唯一归属 App，其余对象保持。历史执行记录仅插入本轮，58 设计仅更新顶部状态。独立只读复审源码、实际结果树、告警与摘要，无阻塞发现；本轮决定 **mergeable**。本轮未提交、未推送、未合并。
- **证据。** 持久根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration58-20261008/`；正式报告 `fruit-code-improvement-h1qdzon4/report.json`。`baseline.json`、`originals/`、`before-methods.json`/原始定向包、`after-methods.json`/原始定向包、`final-method-preservation-evidence.json` 和 `delivery-evidence.json` 保留源码原件、方法集合、条件/适配与旧 dirty 保护证据。

下一轮范围与可直接使用的提示词见 [点云候选管线与纯算法依赖闭包设计](POINT_CLOUD_CANDIDATE_DESIGN_2026-10-08.md)。当前点云编排仍接收混合 builder 输入，通用 KDTree/聚类/去噪算法尚在 Core；方案交付完整纯值管线及依赖闭包，Renderer 专用重载留适配层，不把目录迁移写成实际内存或取消性能收益。独立复审指出初稿遗漏聚类主体依赖的 `PointCloudClusterAnalysis` extension，已读取其真实实现并将整份原文迁移及 Sources/API 保护补入设计和提示词。第 59 轮尚未实施。

整体原 R0–R7 仍 **needs changes / active**。点云编排、Plan plot/tag、Dashboard/批量应用协作、真实观测持久回放、同设备物理内存/阶段计时/ground truth 与最低系统运行验收继续开放。

## 第五十九轮：完整点云候选管线与纯算法依赖闭包

2026-10-08。第 58 轮已完成实现、全量、复审与交付记录，属于 progress。本轮继续原 R4/R7 的完整领域链：正式 preflight 通过，第 58 轮 317 项受测源码与交付记录/59 设计摘要全部匹配；轮前 313 个 Swift、68 个旧 dirty 路径及本轮原件保存到仓库外持久目录。HEAD/分支保持，暂存区为空。

- **根因与完整改动。** 原点云候选编排只需点、颜色过滤器、聚类/点云实验配置，却接收含 Renderer 身份、检测诊断和结果参数的整个 Core builder 输入，算法依赖闭包尚未独立。新增 Domain `PointCloudCandidateInput` 不可变 Sendable 值及完整候选管线/output，Core 同名兼容重载解析 `colorFilter ?? fruitCategory?.colorFilter` 一次后进入纯值入口；生产 builder 保持原调用并实际经过该入口。KDTree、PointCloudCluster、完整 PointCloudClusterAnalysis extension 三份文件逐字迁移到 Domain/PointCloud，未遗漏 analyzeCluster 的颜色/尺寸/球形度/特征值实现。
- **去噪边界与精简。** 通用统计/result/泛型 SOR/unchangedResult 进入 Domain `PointCloudDenoising.swift`；Core 原文件只保留两个 RendererPointSample 重载，默认参数与位置适配原文保持。不同文件名避免 App 编译中的重复 Swift basename。没有平行算法、空协议或扩大 Renderer 类型依赖；Core 深度候选及品类过滤余段逐字保持。旧 builder、同步/debug 聚类与 Renderer 公开入口均保持。
- **算法和资源保留。** 过滤优先级/点顺序，SOR 的 max 准入、严格 k+1、Float/Double 累积、邻域排除自身、保留阈值/顺序/统计原样保持。三份迁移原文证明 KDTree 距离/等距/堆、DBSCAN 密度/噪点/局部间距、分析阈值/几何/候选身份规则未改变。async 最小点数早返回、userInitiated 队列与 continuation 保持。阶段数组和 COW 沿用原路径，不增加整云转换；采样、GPU/cache/revision/identity 和取消准入仍由原 owner 负责。仅 fused、拒绝/低置信度深度否决、零产诊断、校准身份/两次取整、存档及 manifest 规则保持。未声称已经测得物理内存或取消延迟收益。
- **原实现基线与定向。** 在原实现补六项固定契约：显式过滤覆盖品类、品类 fallback/nil 过滤、max 的乘数/下限两侧与恰达五点准入、严格 k+1 及固定均值/标准差/阈值、async 空/不足/六点八面体候选几何与点身份、KDTree 最近成员及半径包含边界。原实现 **722/722、30 类、退出 0、warnings=[]**；迁移后只追加一个不依赖 Core builder 的 Domain 完整管线契约，最终 **723/723、30 类、退出 0、warnings=[]**。原 716 项、六项原实现契约及旧测试原文均保留。
- **工程与完整验证。** PBX 只新增两份新源的四个对象，修改 Core/Domain PointCloud group 和原 App Sources 三对象；三份移动源复用原 fileRef/buildFile，全部相关源唯一归属 App，其余工程对象保持。完整 Domain **43 源、iOS 16 simulator、Swift 5** 独立编译通过，门禁/runner/工作流未改。正式 full **1133/1133、59 类、九步退出 0**，无失败/跳过/expected failure，unsigned Release 模拟器构建通过。逐方法树确认原 1126 项完整保留、新增恰为七项契约，723 定向全部包含；关键十一类 501 项、九项观测回放、原校准 canonical bytes、存档/批量回放均通过。
- **告警与保护。** 两条内部 QoS 告警的数量/message 与第 58 轮相同，本轮两条均无 sourceURL（58 第二条包含 DashboardSummaryTests.swift 来源）；四处既有主 actor 隔离编译告警的位置/message 集合相同，重复原日志保留。无非法 SwiftUI 发布告警，不将既有告警当作已解决。最终 319 项受测摘要一致，验证期间无漂移；307 个其它旧 Swift 逐字保持，文档收尾后其余 64 个旧 dirty 路径保持。历史记录只插入本轮，59 设计只更新顶部状态。
- **复审与证据。** 独立只读复审无阻塞发现；本轮决定 **mergeable**。持久根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration59-20261008/`，正式报告 `fruit-code-improvement-vmwvl313/report.json`。`baseline.json`、`originals/`、`before-methods.json`/原始包、`after-methods.json`/原始包、逐字迁移补丁、`final-method-preservation-evidence.json` 与 `delivery-evidence.json` 保留原件、方法树、所有权与保护证据。本轮未提交、未推送、未合并。

下一轮方案与可直接使用的提示词见 [批量导出应用编排与临时文件所有权设计](BATCH_EXPORT_WORKFLOW_DESIGN_2026-10-08.md)。真实页面仍持有批量导出 Task/generation、await 后发布与临时文件清理；这属于原蓝图明确要求的 Application 长任务入口。设计完整迁移业务所有权，保持现有 writer/仓储/分享/错误恢复契约，不只换目录或添加无人使用的 service。第 60 轮尚未实施。

另已核查 Plan 分类缺口：Start/Quick/Rescan 请求携带地块/标签并在 Dashboard 激活时写入独立 TagStore，ScanView/ScanPlanFactory 未传入 ScanPlan。冻结扫描分类与后续可编辑树分类的消费关系仍需完整设计，不能仅加 unused 字段就标为完成。

整体原 R0–R7 仍 **needs changes / active**。Plan 地块/标签、Dashboard/批量应用编排、真实观测持久回放、COW/物理峰值与阶段耗时、ground truth/最低系统/设备验收继续开放。首次 preflight 因新的外部 output-root 尚未创建而被参数检查拒绝；创建目录后正式 preflight 通过，该次拒绝未执行任何 Xcode 验证。

## 第六十轮：批量导出应用编排、文件所有权与验证就绪门禁

2026-10-08。第 59 轮已完成，继续原 R6/R7 的应用编排边界。正式 preflight 通过，轮前 315 个 Swift、79 个旧 dirty 路径及原件已保存在仓库外；第 59 轮最终 319 项受测摘要匹配。当前 HEAD/分支保持，暂存区为空。任务在本轮实现与验证期间持续推进；中间一次仅回答进度的目标轮属于 no progress，随后重新核验并继续排查真实失败。

- **根因与改动。** 原批量页面直接持有 Task、generation、await 后发布及临时文件删除。新增 Application `BatchExportWorkflow` 和具体 `BatchExportOperations`，页面实际通过稳定 `@StateObject` 使用；AppDependencies 装配生产操作，Dashboard 路由实际注入。页面移除重复业务状态，保留选择、格式、选项、完整请求构造、本地化失败及分享呈现。成功返回的文件由单一不可变 lease 接管；服务仍清理尚未交接的部分产物。任务跨 await 只捕获操作和弱 owner，owner 已释放时也清理迟到 URL；真实请求 reader 只捕获 store 和 State 位置，不捕获整个 View。
- **契约保留。** 空请求、替换取消/身份失效、当前任务才能结束忙碌态、完整请求等值及原成功/失败分支差异保持。离开、重试、来源变化、旧分享回调及受管清理规则保持；不删除源档或其它 session 文件。service/repository/writer、输出格式、source/revision/hash、manifest 最后发布、未知研究字段、校准 canonical bytes 及仅 fused 可靠估产均未修改。没有新建平行生产导出路线或改变阈值。
- **基线与所有权证据。** 原实现定向 **501/501、14 类**；最终同样选择 **515/515、14 类、退出 0**，原 501 方法完整保留，新增恰为 14 项 workflow 契约。受控服务故意忽略取消，覆盖取消后替换、旧成功/失败/defer、全部请求输入变化、失败差异/重试、离开及 owner 释放后的文件清理。实际 UIKit 宿主验证同身份页面重建仍使用原 workflow，真实 reader 不阻止 owner 在服务返回前释放。受控 continuation 在测试失败收尾时也移除后唯一恢复，原两项文件清理测试改为实际挂载页面而非访问未安装的 StateObject。
- **实际 UI 与缺陷修复。** UIKit 的 UIAlert action `accessibilityActivate` 实测返回 false，失败原包保留，未将其算作真实点击。既有原生 UI target 增加普通生产 App 的恢复用例，独立 runner 仅新建并删除自己拥有的模拟器；通过 UUID marker 在 App 终止后植入一份合法旧档和自有目录故障，在第二个真实弹窗后仅解除该故障。实际点击 Cancel、再次导出、Retry、系统分享关闭和产品“收起”，等真实完成状态后再检查 CSV 字段、原档 SHA 与产品清理。最终 **2/2 Passed**，保留原 Variety 确认方法，runtimeWarnings=[]；fixture 准备/修复/内容检查/清理、源档保护、自有模拟器删除及源码冻结均成立。五个批量阶段截图已逐张核查并持久保存。
- **SwiftUI 发布回归。** 实际 UI 曾记录 `Publishing changes from within view updates`：SwiftUI 在已关闭 alert 的更新中再次写 false，旧 `dismissFailure` 对 nil 重复发布。先保留原警告及 **1 项失败回归**（观察到 1 次发布，预期 0），再加 nil 幂等 guard；该方法已在最终定向和 full 实际通过，最终真实 UI 无该警告。没有放宽默认 runner 的非法发布拒绝规则。
- **全量失败、对照与流程改进。** 首次正式 full **1091 通过/56 失败，共 1147**，全部失败报宿主缺少 UIWindowScene，源码未漂移，原始退出 65/结果包保留。CoreSimulator 日志显示该运行从关机设备启动；明确 bootstatus 就绪后保持同一份源码和测试选择，full **1147/1147** 与 Release 全通过。此对照支持明确启动前置条件，不把冷启动认定为所有 scene 缺失的唯一根因。先备份并扩展三份既有工具/流程文件范围；新回归在旧 runner 下为 **2 方法、7 个失败断言/subcase**，修改后 **39/39 工具测试通过**。默认入口仅在 XCTest 前新增所选 UDID 的 bootstatus 步骤；启动失败保留退出并阻止 tests/Release，quick/preflight 不启动设备，不改 selector、scene 断言或完整性门槛。bootstatus 不等于 foreground scene 验收。
- **最终完整门禁。** 最后工具修改后的正式 full **1147/1147、59 类、十步全 0**，无失败/跳过/expected failure，含启动就绪、完整 Domain **43 源/iOS 16 simulator/Swift 5** 和 unsigned Release 模拟器构建。原 1133 个唯一方法全部保留，515 定向全部包含，新增恰为 14 项 BatchWorkflow。App/单元/原生 UI 源在工具范围扩展后逐字保持，既有定向/UI 原始证据仍对应同一份 App；最终 full 验证当前工具，39 项工具测试对应当前三份工具/流程摘要。最终 **324 项受测摘要**核对通过，验证期间无漂移。
- **告警与剩余风险。** 定向和最终 full 各有两条既有内部 QoS 消息；full 第二条附 DashboardSummaryTests sourceURL，数量/message 与既有基线相同。四处既有主 actor 默认 shared 编译告警及四处旧测试 RunLoop async 告警保持；本轮新增两条测试 `WeakMutability` 样式告警，未写成“无新增告警”。真实 Retry 再次失败的弹窗时序尚未单独实测，不能宣称全部恢复时序验收。375×667 截图可见底层部分标题/主按钮裁切及完成操作靠底；相关布局源本轮未改，来源属于既有布局的判断是推断，未取得原版本同设备对照。上述限制保留为后续候选，不混入本次所有权迁移；物理 LiDAR、资源与最低系统运行仍未验收。
- **保护、复审与交付。** 工程只新增四对象、修改 Application/App Sources/UI group/UI Sources 四对象；两个新 Swift 各唯一归属预期 target，原对象/顺序保持。runner 原文只插入 bootstatus，流程文档只插入对应一段，原工具测试 406 行全部保留，仅插入三项新方法。308 个其它旧 Swift、72 个范围外旧 dirty 逐字保持；历史执行记录只插入本轮，60 设计只更新顶部状态。独立只读复审生产链、真实 UI、工具门禁、原始方法树/告警/SHA 无阻塞发现；本轮决定 **mergeable**。未提交、未推送、未合并。

持久证据根：`/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration60-20261008/`。最终正式报告 `fruit-code-improvement-qzjgmkv5/report.json`；`baseline.json`、`originals/`、`scope-extension.json`、`readiness-originals/`、`readiness-scope-extension.json`、`after-methods.json`、`batch-native-ui-ptda1xlt/`、`scene-host-diagnosis/`、两份 readiness 回归、`structural-preservation-evidence.json`、`final-method-preservation-evidence.json` 与交付摘要保留完整证据。首次失败及同源码就绪对照报告分别为 `fruit-code-improvement-37w5iq2o`、`fruit-code-improvement-t76p2gey`，没有覆盖或隐藏失败。

下一轮方案和可直接使用的提示词见 [扫描分类快照的完整消费设计](PLAN_CLASSIFICATION_DESIGN_2026-10-08.md)。第 61 轮尚未实施；从 Dashboard 实际接受的启动分类冻结一次，经两条 makePlan、对应 receipt 的结束流程、事务存档、typed 读取到研究 JSON 贯通，并保持校准重存的原分类。整体原 R0–R7 仍 **needs changes / active**：Plan 分类、Dashboard 聚合、Renderer 文件编排/兼容入口、真实观测留存回放、物理内存/耗时/精度及最低系统验收继续开放。

## 第六十一轮：扫描分类冻结、存档与研究消费贯通

2026-10-08。继续原 R1/R6 的分类值契约，正式 preflight、原件和旧 dirty 保护均完成。第 60 轮最终 324 项受测摘要及三份交付文档已复核；轮前 317 个 Swift、89 个旧 dirty 个体路径保留在外部基线。本轮仅处理启动分类未进入扫描存档的真实消费缺口，没有启动新的功能范围。

- **根因与改动。** Start/Quick/Rescan 的选择此前只写可编辑 TagStore。现在 AppDependencies 在 Dashboard 激活的同一个主 actor 同步动作中，沿用原 assignment 的过滤/去重顺序，捕获地块/标签 ID、当时名称和标签顺序，放进同一个 ScanLaunchRequest，保持原 request.id 和 GPS 对象。新增纯 Domain 不可变 `ScanClassificationSnapshot`；Dashboard 实际传入 ScanView，开始和中断重启两条 makePlan 都使用该次启动快照。后续目录改名、删标签、编辑 assignment 不改变活动 Plan；下一次激活重新捕获。
- **实际消费与格式。** 对应 receipt 的 planID guard 保持，生产结束流程只把该 Plan 的分类传入 ScanAssessment/ExportRequest。新增可选 metadata `scanClassification`，字段内部版本为 1；显式空与旧档缺失分别为 `.empty`/nil，非法 present 或不支持版本不能静默成为空分类。typed companion → PLYParserResult → VerifiedScanRecord 沿原已解析结果透传，不为 verified record 再解析大型 JSON。研究 JSON 实际保留分类原始 envelope 及版本 1 的未知扩展键。旧无分类兼容入口仍省略字段，不回填当前目录；manifest 1–3、旧 CSV、当前 TagStore 批量分组、canonical 校准字节、仅 fused 可靠估产和诊断保持。
- **同源重存与保护范围。** 原事务锁内保留已验证原分类；无显式值继承原值，相同显式值保留原 envelope，冲突显式值拒绝且不改已提交文件。可解析、含分类但未通过完整性验证的档案拒绝静默覆盖；仅失败验证路径需要额外有界读取。不可读、非 JSON 或超过既有上限的 metadata 继续沿用 legacy repair，不能宣称恢复其中任意历史分类；原 oversized repair 回归保留通过。实际校准 UI 只读取基线，没有重写扫描存档的生产入口，本轮验证既有服务的同源重存契约，没有制造校准写入路线。
- **失败先行与修复记录。** 生产改动前，非法分类接受、同源重存丢分类、研究导出丢分类三项回归实际全部失败，退出 65、原包保留。首轮定向编译发现 Routing 扩展不能访问另一文件的 private 环境依赖；轻量 activateScan 委派移回 DashboardView.swift，保留私有属性。第二次定向为 **693/694**，唯一失败是新增 absent/empty 夹具的请求树名与 PLY fallback 不一致，被原 identity 校验正确拒绝；只修夹具树名，没有放宽生产校验。上述失败均未覆盖。
- **最终验证。** `targeted3` **694/694、26 类、退出 0**，原 683 方法全部保留；新增总计 **11**（存储 8、Dashboard 2、结束流程 1）。覆盖非法字段、显式空/缺失、未知扩展、冲突拒绝、发布失败回滚/重试、根接受顺序/身份、实际挂载开始/中断重启和生产结束到研究读回。正式 full **1158/1158、59 类、十步全 0**；原 1147 方法和全部 694 定向完整包含。完整 Domain **44 源/iOS 16 simulator/Swift 5** 与 unsigned Release 模拟器构建通过。325 项受测摘要在定向、full 前后与交付源码一致。
- **UI 与告警限制。** 两张新挂载截图和 AX 已逐张核查：CLASS61、采集中、取消/停止/查看要求均存在。测试替换了物理 AR runtime/readiness，截图为白色 AR 背景，追踪提示覆盖指标，模型身份未准备；恢复通过生产 intent，不冒充原生 UIAlert 触摸、正常 AR 布局或真机采集验收。定向/full 各两条既有 QoS；最终 full 与第 60 轮两条完整对象一致。两轮各 10 个唯一源码编译告警位置，文件/message 和位置数一致，测试行号随新增段平移；没有非法 SwiftUI 发布。现有 SDK 链接/部署告警原日志保留，不宣称无告警。
- **保护与复审。** 为避免重复大 JSON 解析，先保存并扩展两个 reader 原件；未修改基线。299 个其它旧 Swift、77 个范围外旧 dirty 逐字保持。PBX 只新增两个对象，并向原 Domain group/App Sources 各插入一次，新源唯一归属 App。独立只读终审原始报告、方法树、源码摘要、分支、空暂存区、告警和消费链，无阻塞发现；本轮 **mergeable**。未提交、未推送、未合并。

持久证据根：`/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration61-20261008/`。原始失败分别见 `regression-before`、`targeted`、`targeted2`；最终定向见 `targeted3`，正式 full 为 `fruit-code-improvement-6wcophp_/report.json`。`baseline.json`、`originals/`、`reader-originals/`、`reader-scope-extension.json`、`full-command.json`、`final-evidence.json`、`native-ui-qa/` 保留方法、输入保护及交付依据。

### 剩余范围与第 62 轮候选

分类贯通已关闭。整体仍 **needs changes / active**；按原目标仍有三类架构工作与一组整体验收，不能由轮数或测试数计算工作量百分比：

1. **Dashboard 聚合。** `DashboardDailySummary` 仍在 Views；Hero 与 Stats 各自反复构造今日摘要。`YieldReportData` 和 `TrendsData` 仍在 SwiftUI 文件，报告/趋势通过计算属性重建筛选、去重和排序结果。聚合应由 Application 接收明确历史快照与时间上下文，页面消费结果。下一轮以这条真实链为候选，先证明现有行为与发布边界。
2. **Renderer 文件编排与兼容退出。** 继续核对硬件捕获、GPU 排空/冻结与文件写入的责任和唯一副作用入口，满足退出条件后才删兼容路线，保留有界最终输入及取消/重试。
3. **真实观测留存回放。** 现有合成回放不能代替真实输入；仍需有界、可还原、脱敏并带模型/配置身份的实际观测基线与黄金预期。
4. **整体验收。** 真机 COW/峰值内存、阶段耗时、30/60/120 秒 LiDAR 采集、人工果数误差和最低系统运行尚未证明；历史遗留的 UI 恢复/删除证据与紧凑布局限制也需按实际范围收尾。设备连接、模拟器通过或估算 payload 不计作这些项目通过。

第 62 轮提示词：

```text
继续原架构目标，先读取AGENTS.md、默认工作流、原R0–R7蓝图和第61轮最终证据。
preflight保存原件，保护所有旧dirty；不提交、推送或合并。
检查ScanHistoryStore.scanFiles→Dashboard/首页Hero与Stats→报告/趋势实际调用链。
为今日汇总、同树最新完整记录、零产、同时间tie-break、溢出和趋势顺序建立真实基线。
把数值筛选/去重/排序聚合收敛到Application的具体值与所有者，实际页面消费同一已发布结果；
明确历史快照与Calendar/时间输入，避免只移动文件后仍在多个body计算属性重复全量聚合。
设计记录刷新、删除/导入/完成扫描、日期跨日/回到前台的更新边界；异步时拒绝过期发布，
保持每条现有公式与排序差异，不制造每次body一个Task、重复历史仓储或空壳protocol。
先聚焦一条可完整验收的聚合链；保持本地化/导航/布局、完整性状态过滤和可靠估产规则。
运行相关定向、Domain、full/Release；核对原方法、告警、源码冻结并独立只读复审。
记录实际证据、未证明的资源收益和下一步；整体目标直到剩余条目逐项验收才完成。
```

## 第六十二轮：Dashboard 聚合所有权、时间上下文与一致发布

2026-10-08。继续第 61 轮指定的真实 Dashboard 链。正式 preflight 通过，轮前 HEAD、空暂存区、旧 dirty、318 个 Swift 及本轮原件保存到仓库外；第 61 轮 325 项受测摘要在改动前匹配。本轮只处理历史聚合及其页面消费者，原有架构迭代保持。

- **根因与改动。** 原 Hero/Stats 重复构造今日摘要，报告/趋势在 SwiftUI 计算属性重复筛选、去重和排序。原数值算法进入 Application `DashboardAggregation.swift`；每个实际 `ScanHistoryStore` 拥有一个具体聚合 owner。成功历史读取更新其输入，首页、报告、趋势观察同一个不可变 snapshot，一次发布 daily/report/trends/recent，页面不再全量聚合。自定义 historyStore 仍从实际注入实例取值，没有平行全局缓存、第二仓储、空协议或每次 body 一个 Task。
- **时间与并发。** 主 actor 冻结 Calendar/startOfDay 和历史值，utility worker 构造结果。记录替换、跨日/时区通知、前台及页面进入触发必要更新；相同记录和时间上下文不重复启动。替换取消旧任务，await 后同时检查取消及 generation，禁止过期发布。悬挂 builder 前只捕获输入、builder 和弱 owner；释放取消工作。工作线程仅在构建前后检查取消，不能据此宣称筛选/排序中途即时停止；刷新期间保留上一份完整 snapshot，数据可能短暂落后于 scanFiles。
- **保留与精简。** 今日按原树名计树，报告按归一化树名取最新完整记录，date/treeID/id 决胜，趋势仍为所有完整记录及原稳定时间顺序。零产、溢出、浮点累积、prefix 3/20、失败/取消历史保留、布局/路由/本地化/API 均保持。旧算法原件核对仅有值 conformance、显式 now 和预计算 prefix20 的变化。旧 Views Summary 引用退出，新 Application 源唯一进入 App Sources；现有三个 PBX 对象只按约定更新引用数组。融合、阈值、证据生命周期及存档/manifest 均未改。
- **原实现基线与回归。** 原实现 DashboardSummaryTests **129/129**。最终 `targeted2` **137/137、退出 0**，原 129 方法和所有旧测试行保留；新增恰为八项，覆盖明确时钟/时区、取消后迟到、相同记录跨日、通知/前台、owner 释放、历史失败/取消及实际挂载页面的一致发布/空态。最后一次默认闭包修复后重新执行，无失败/跳过/expected failure。
- **终审修复。** 初次全量虽通过，终审逐源码位置抽取编译告警时发现新增 non-Sendable 函数转 `@Sendable` 警告；将默认函数引用改为不捕获状态的显式闭包，保留修复前原始包及审查草稿，并重跑最终定向、full/Release。没有放宽 Sendable、取消、算法或测试门禁。最终告警集合与原轮对照另存，既有 SDK/QoS/Swift 6 迁移提示不算已解决。
- **完整验证。** 最终正式 full **1166/1166、59 类、十步全 0**，原 1158 方法和全部 137 定向完整包含，新增恰为上述八项。完整 Domain **44 源/iOS 16 simulator/Swift 5** 和 unsigned Release 模拟器构建通过。最后 353 项受测摘要一致；309 个其它旧 Swift/343 个其它受测源及 preflight 范围外 95 个旧 dirty 路径（83 个存在文件、12 个删除路径）保持。最终唯一源码告警位置 11 个：前轮 10 个按文件/message/数量保留，测试行号平移；新增一条 weak owner 测试样式提示，Sendable 转换告警消失。定向/full 各两条既有 QoS，message/数量一致，sourceURL 随结果包变化；没有非法 SwiftUI 发布，不宣称无告警。
- **界面与保护。** 最后一次源码的四张挂载截图与 AX 已逐张核对：首页 1 次/1.2 kg/1 树，报告和趋势 AGG62-NEW/3.4 kg/7 果，空态可开始扫描。测试使用实际 UIKit 宿主和页面，但替换了历史 loader/worker，不能代替原生触摸及真机输入。首页英文产品名在挂载截图有截断，布局表达式未改，但没有旧版本同设备渲染对照，仍记为风险。首轮正常 App 首页/历史进入及关闭实际观察，2504 个 Documents 文件与 8 个偏好值摘要不变。最终 full 后正常 App 已重新启动并观察首页；主窗口/紧凑窗口、Raise 和缩放坐标尝试均遇到 noWindowsAvailable，报告/趋势原生触摸走查未完成，已请求人工打开页面补齐。不能以挂载通过代替这个门禁。
- **复审与决策。** 实现后根代理另行只读对照源码原件、生产调用链、方法树、告警、源码摘要及工程引用，修复 Sendable 转换后无阻塞源码发现；没有冒充第二位审查者签署。因原生 UI 门禁未完成，本轮当前 **needs changes**，整体仍 **needs changes / active**。记录与下一轮方案已交付，但不宣布本轮验收关闭；未提交、未推送、未合并。

持久证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration62-20261008/`。原件/基线见 `baseline.json`、`originals/`、`preflight/`、`baseline/`；修复前证据见 `targeted/`、`fruit-code-improvement-zvm8uv9e/`、`pre-sendable-review/`；最终定向为 `targeted2/`，最终 full 为 `fruit-code-improvement-9m9mxy57/report.json`。方法树、源码摘要、告警差异与交付依据见 `targeted-audit.json`、`final-evidence.json`、`compile-warning-comparison.json`、`Review62.md`、`delivery-evidence.json`。

### 当前剩余与下一轮设计

Dashboard 的源码改造与自动验证已完成，原生报告/趋势走查仍待补。整体还剩 **两项架构工作加一组整体验收**，并有本轮这一项 UI 门禁；这些项目的工作量不同，不能按测试数或轮数折算百分比：

- **Renderer 文件编排与兼容退出。** 下述设计尚未实施。
- **真实观测留存与黄金回放。** 需有界、可还原、脱敏并带模型/配置身份的真实输入及预期，现有合成回放不计作完成。
- **综合验收。** 真机 COW/峰值内存、阶段耗时、30/60/120 秒 LiDAR、人工果数误差、最低系统运行，以及历史 UI 恢复/删除/紧凑布局等未完成项。设备连接或模拟器通过不计作这些条目通过。

Renderer 的真实生产链为 `ScanFinalizationOperations.production.exportPointCloud → ScanCoordinator.stagePointCloud(plan:...) → Renderer.stagePointCloud async → GPU 排空/捕获验证/最终云 → ScanRepository.stagePointCloud → PLYPointCloudWriter`。同一 Core 文件同时承载硬件操作、冻结值、文件格式和草稿发布；下一轮按这条链拆责任，不以目录数代替交付。

1. Renderer 保留硬件、GPU 排空、capture generation 与有界最终云冻结，提供明确冻结结果；冻结与原 generation 检查顺序保持。
2. Application 具体 staging 操作接收冻结云和扫描上下文，负责目标路径/命名、仓储写入及 StagedPointCloud 交接。生产结束流程必须实际使用该操作；避免另造无人调用的 service。
3. Infrastructure 承载纯 PLY 格式与分块文件写入。Renderer 样本适配留 Core；FinalPointCloud 等纯值只有在完整依赖闭包核对后移动。保留 1024 点块、EINTR/write-all/fsync、独占原子发布及发布前完成 receipt 的边界。
4. 回调 savePointCloud/exportPLY/stagePointCloud 目前只在兼容链内部互调；须重新检索生产、测试和公共 API 承诺，满足退出条件才删除，不能仅按一次文本搜索擅自破坏接口。异步 Renderer stage 有真实测试调用者，先适配保留。

下一轮提示词：

```text
继续原 R0–R7 目标，先读取 AGENTS.md、默认工作流、蓝图和第62轮最终证据；
先补齐第62轮未完成门禁，再启动新的源码改动。preflight 保存原件并保护全部旧 dirty；
不提交、推送或合并。检查 finalization→coordinator→Renderer async stage→repository→PLY writer 的真实链，
为 GPU drain timeout/write failure、captureChanged、空云、取消前/发布后、名称冲突和重试建立原实现基线。
把硬件排空/冻结留 Renderer，具体文件 staging 编排放 Application，PLY 格式和有界写入放 Infrastructure；
让生产 finalization 实际使用同一副作用入口，不增加平行发布路线或空 protocol。
保持 generation/identity、采样和缓存、原 PLY 字节/GPS格式、原子独占发布、SHA/file identity、
draft ownership，以及发布后即使取消仍返回 receipt 给 owner 清算的契约。
只在完整调用者/API退出条件成立后删除旧回调；保持现有异步入口可用。
先做最小完整职责切分，不混入阈值/算法改变，不添加整云转换或复制。
运行 storage/lifecycle 定向、Domain、full/Release，逐方法核对保留，结构化对比编译/运行时告警，
检查源码冻结和 PBX唯一归属，单独只读复审并记录证据、剩余风险及下一候选。
没有真机峰值/阶段计时证据，不声称已取得资源收益；整体直到实际观测回放与设备验收通过才完成。
```

## 第六十三轮：固定最终点云与拆分文件暂存职责

2026-10-08 实施及自动验证，2026-10-11 完成记录与原生补验。轮前 preflight、原件及原实现 passing baseline 留存；本轮只处理 GPU 冻结到文件暂存的真实生产链。HEAD 仍为 `3398423774bf3f88f3fb4a732718a4e504a752fb`，没有暂存、提交、推送或合并。

- **根因与失败证据。** 原 combined stage 在冻结成功后遇到文件失败，重试会重新冻结 Renderer。同 capture generation 内点云 revision 继续变化，实际写入值与首次冻结值不同。新增真实 Metal/生产 finalization 回归：首次冻结 revision 50 红色点云，测试独占目标目录被普通文件阻断；随后改成 revision 51 绿色点云，修复目录并重试。原实现退出 65，身份、内存点云及 PLY 内容断言失败；修复后的同一行为回归通过，原失败结果包保留。
- **职责与精简。** 六字段 `FinalPointCloud` 进入 Domain；Renderer 只负责有界硬件排空、capture 验证和最终值冻结；Application `PointCloudStaging` 接收冻结值及扫描上下文并调用现有 repository；Infrastructure `PLYPointCloudWriter` 持有纯格式和分块文件写入。生产 finalization 实际贯通这条唯一入口。旧无外部调用的回调链退出，仍有真实调用者的 Renderer async stage 适配保留，generation 在 MainActor 等待前固定。
- **冻结所有权。** workflow 保存成功冻结值，文件失败只重试 stage，沿用原 ScanID/PlanID/GPS；在 IO 前核对 capture 与云 signature。取消、reset、新扫描清除冻结重试值；GPU/capture 失败分类保持。两个 await 都不强持有 workflow owner，迟到冻结不进入 IO，发布后的草稿仍返回原有清算路径。发布后不增加会丢失 receipt 的取消检查。
- **保留。** 原采样/滤波/signature、缓存/revision、permit/锁顺序、5 秒排空截止时间、1024 点写块、EINTR/write-all/fsync、独占原子发布及发布前 SHA/file identity 不变；PLY header/vertex/GPS 编码逐体核对保持，六字段值契约保持。没有新整云转换、第二仓储或发布器，没有改变融合/阈值、fused-only、零产和置信度诊断。
- **实际验证。** 原实现 storage/lifecycle **565/565**；最终定向 **572/572**。新增七项覆盖生产文件失败复用、原计划/GPS、capture 不匹配、stage 取消、cancel/reset 清理及两个悬挂阶段的 owner 释放/迟到草稿。最终 full **1173/1173、59 类、十步全 0**，原 1166 方法与全部 572 定向方法完整包含；零失败/跳过/expected failure。Domain **45 源/iOS 16 simulator/Swift 5**、unsigned Release 模拟器构建及 diff check 通过。当前 358 项受测源码摘要仍一致；范围外 349 个旧 Swift 与 100 个旧 dirty 路径保持，新增三个 Swift 源均唯一进入 App Sources。
- **告警和限度。** 最终全量两条 QoS 告警与前轮 message/数量一致，定向没有运行时告警。编译告警位置由 11 增至 13，新增两条 weak owner 测试样式提示，无新增生产并发告警。测试后的模拟器诊断收集存在前轮同样的 `simctl` 查找错误 72；测试、结果树和 Release 均退出 0，不声称日志无错误或已经取得真机资源收益。
- **独立复审与决定。** 第二位只读审查者 `/root/review_iteration63` 对照源码原件、完整调用链、取消/重试/身份、writer 字节、工程归属、方法树、受测摘要和告警，无阻塞发现；原始失败证据未弱化。本轮代码 **mergeable**，整体 **needs changes / active**。

持久证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration63-20261008/`。原件与基线见 `baseline.json`、`originals/`、`preflight/`、`fruit-code-improvement-6r85g2xx/`；失败/修复回归见 `regression-original.xcresult`、`regression-repaired.xcresult`；最终定向为 `fruit-code-improvement-lt1quk3m/report.json`，full 为 `fruit-code-improvement-em289qqx/report.json`。审计及交付见 `validation-audit.json`、`compile-warning-comparison.json`、`runtime-warning-comparison.json`、`Review63.md`、`delivery-evidence.json`。

### 第 62 轮原生补验与当前剩余

2026-10-08/11，设备交互恢复后使用正常 App 和指定 iPhone 17/iOS 27 模拟器实际操作报告、趋势：两页显示无可靠数据，与当前两条未完成历史相符；开始扫描进入新建向导第 1/5 步，空编号的下一步不可用，取消返回首页；两页完成按钮也均返回首页。没有输入或保存扫描。原生截图逐张核对；2520 个 Documents 文件及 8 项偏好值摘要前后完全一致，证据见 `native-ui-recheck/`。该补验关闭第 62 轮待补的空态/导航触摸门禁，第 62 轮对应范围 **mergeable**。非空聚合仍以原挂载测试为证据，紧凑布局旧版对照与真实扫描不由此关闭。

当前还有 **一个主要架构代码包：真实观测留存与黄金回放**，方案和完整提示词见 [下一轮设计](REAL_OBSERVATION_REPLAY_DESIGN_2026-10-08.md)。先审计现有提交/manifest/删除事务，保存实际冻结 Input 与 Float32 点位模式，使用原 builder 离线回放，不重新从四位小数 PLY 假定完整输入。真实 LiDAR 正常/退化样本、30/60/120 秒资源与阶段计时、人工果数误差、最低系统运行和其余原生恢复/删除/布局验收仍开放；最后还需按范围提交和远程交付。没有工作量权重，不换算完成百分比，也不为继续迭代增加原目标之外的改造。

## 第六十四轮：实际输入留存、事务归档与本地黄金回放

2026-10-11/12。关闭原 R4/R7 真实观测持久回放的主要代码缺口，实际设备验收继续开放。开始时记录 322 个 Swift/工程源摘要、112 个旧 dirty 路径、空暂存区和 HEAD；保留原件及所有失败结果到仓库外持久目录。本轮受测旧源码范围为 31 项，包含内部 Operations 构造迁移与一次旧 UI 测试完成边界修复，未扩展生产校准行为。

### 根因与实现

- **实际输入缺失。** 旧结果/研究 JSON 只有输出，四位小数 PLY 无法逐位重建实际 Float 输入。生产 finalization 现在保存已捕获 Input 的全部配置与无 buffer 观测、完整 renderer/plan/model/算法/源码身份；二进制点段按原 Float32 位模式/顺序分块写出，保持原 PLY 字节和原可靠估算输入。
- **预算与执行安全。** 显式版本化 DTO、有界数组/文件/容器 reader，点/观测/样本/总字节超预算明确 unavailable，不截断估算输入。原 `minPoints=Int.max` 回放实际崩溃后，新增执行前拒绝不安全算术域；留存原始值，生产阈值不改。完整/非默认/可选字段、拒绝来源、位模式、未知 schema、重算摘要后的身份/预算/模型/矩阵变异和源码身份错配均有实际回归。
- **唯一事务与恢复。** draft-owned 准备目录先验证，再由既有 exporter 事务发布输入 JSON/点段、metadata/CSV，manifest 最后发布。覆盖取消、重试、替换回滚、摘要与 source/revision 复核。回滚失败保存 staging/备份并保留 PLY 锚点；删除/取消清算包含新 artifact，按完整 basename/revision/UUID 归属，避免删除带点同名前缀源。reader 一次终态错误后继续拒绝读取。原失败包完整保留。
- **重试输入所有权。** 独立复审发现 coordinator capture 消费观测后，fallible prepare IO 失败时 workflow 没有保存 raw snapshot，重试会捕获空集合。原生产回归明确复现观测/类别丢失；最初 0.1 秒样例未满足生产稳定门槛，不能据此声称正产量变零。修复为 capture/bind 两个明确内部操作，由同一 workflow 在 IO 前保留 raw，重试复用同一 ID，成功/取消/reset 释放。最终健康样例两帧间隔 0.5 秒，先用原 builder 证明正果数/产量，再断言重试完全相等、capture 一次、所有身份/观测/诊断保留和 golden 匹配；0.35 秒生产稳定门槛未改。
- **本地独立导出。** 新 `.ftsreplay` 容器有界、流式、逐条读取，使用既有 builder 比较结果/诊断/几何；生产来源不重新执行 CoreML。导出省去显式 GPS、树名/分类标签、图像和扫描日期，保留局部坐标与帧时间关系；不自动上传。六类合成证据覆盖可靠、混合点云、低 confidence、copyFailed、image-only、cloud-only，旧固定黄金预期保留。

### 实际验证、复审与保护

- 最后生产/回放/点云定向 **208/208**；联合 storage/fusion/lifecycle **971/971**；最终 full **1194/1194、59 类**；Domain 独立编译 **45 源**、unsigned Release 均退出 0。零失败/跳过/预期失败，原 1173 方法全部保留，新增 21 方法。源码身份生成器 3 项 Python 测试通过。
- 第一次最终 full **1193 通过/1 失败**，旧校准关闭测试读到尚未提交的值，Release 正确停止。只增加有界业务提交状态等待，再等待保存任务，原持久化/下一计划/较新值/冻结计划全部精确断言保留；独立回归及最后 full 通过。日志没有直接记录两个回调先后，不把推断写成已观测时序。默认工作流补充了 UIKit 消失、SwiftUI 提交、已入队保存的不同完成边界。
- 最终源码审计保护 **291 项其它原源码**；工程仅增加所需源/身份 phase，既有 Sources 相对顺序和唯一 target 所有权保持。Debug/Release 的 `ScanReplayBuildIdentity.json` 均与当前 **309 个生产源/资源文件**一致。编译告警集合无增减，保留两条旧 QoS 告警，第二条本次带 Dashboard 测试来源；不称无告警。
- 正常 App 实际选择观测回放包、核对说明与普通字段/分组隐藏、切回 CSV 恢复选项、关闭回首页；四张原生截图留存。**2560 个 Documents 文件、8 项偏好值**前后摘要相同，installed binary/identity 与最后受测 Debug 相同。现存两条旧记录不完整、导出按钮不可用；完整记录原生回放导出/失败弹窗没有通过本走查验收，不冒充真实设备输入。
- 第二位审查者只读签署本轮代码/模拟器对应范围 **mergeable，无已知阻塞**；受测源码、方法树、PBX、告警、UI/数据保护均复核。证据：`/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration64-20261011/`，风险 `fruit-code-improvement-0jmog89b`，full/Release `fruit-code-improvement-t6yqp7n2`，完整审计 `validation-audit.json`，原生 `native-ui/`。原崩溃/编译/断言/回滚失败记录均保留，未把中间失败改写成通过。

### 当前剩余与下一步

主要架构代码主线已经落地，**整体仍 needs changes / active**，剩余不是按文件/测试数计算的百分比：

1. **真实输入与物理资源/精度。** LiDAR 设备正常、退化/零产包实际留存/导出/读回与 golden；30/60/120 秒、同设备物理峰值/COW 与阶段计时、人工果数/重量对照。现有合成生产路径测试不代替这些证据。
2. **系统与原生验收。** 最低支持系统实跑；其余原生保存失败/恢复、完整记录导出/删除和紧凑布局等原范围门禁。永久删除仅按已确认的具体测试记录与动作执行。
3. **Git 交付。** 按范围整理对应提交、远端推送/检查与合并。本轮暂存区为空，未提交、未推送、未合并。

下一步提示词见 [第 64 轮设计的验收收尾](REAL_OBSERVATION_REPLAY_DESIGN_2026-10-08.md#6-当前下一步与提示词)。先补实际验收，出现有证据的缺陷再小范围修复，不为持续迭代增加新的无依据架构包。

## 第六十五轮：回放错误呈现与紧凑屏幕失败恢复验收

2026-10-12。延续原目标的本机验收，未增加新的架构包。上轮只在两条不完整旧记录上验证格式切换，不能证明完整旧记录的回放失败提示。本轮扩展现有隔离 iPhone SE 原生流程，在旧 CSV 故障/取消/精确存储修复/重试/分享/内容检查/清理后执行回放失败、取消与 CSV 恢复。

- **实证根因。** 初次原生 build 退出 0、UI 退出 65（1 失败/1 通过）；新增具体不可回放文案断言失败。服务抛出的 `ScanReplayError` 被 workflow 原样保留，但页面 presentation 只识别 Batch/Cocoa 错误，四类回放错误均落入 generic。新增单方法在原生产实现退出 65、实际 1 项失败，失败结果和附件全部保留。
- **聚焦修复。** `BatchExportView` 增加四个明确 typed 错误映射并使用对应本地化文案；Batch/Cocoa 原映射、未知错误兜底、取消/重试按钮与行为保持。新增单测覆盖四类原因及未知错误；原生确认具体提示、取消恢复、宿主管理目录无残留与原档摘要保持，切回 CSV 保留原 treeID 字段状态。仓储、回放格式、融合算法与阈值均未改。
- **最终验证。** 全部 `BatchExportServiceTests` **141/141** 通过；full **1195/1195、59 类、10 步退出 0**，Domain **45 源**与 Release 通过；原 1194 方法全保留且仅新增上述回归。隔离原生 **2/2** 通过，既有品种确认门禁保持。编译告警集合保持，两条旧 QoS 告警仍在。365 项冻结清单有 362 项不变，改动的三项为生产页面、导出单测和原生 runner；UI 测试另由原生运行快照核对，不能误算入 365。PBX 不变，116 个范围外 dirty 文件摘要保持；309 个生产源/资源身份与最终 Debug/Release/原生构建一致。
- **复审与反馈。** 只读复审确认旧恢复断言保留、宿主独立检查和明确 typed 映射；修正审计脚本误把 UI 测试算入旧冻结清单的计数。默认工作流补充新导出格式须核对服务到页面错误映射及失败/取消/恢复路径，不能仅验证服务异常或格式切换。
- **边界。** 本轮代码范围 `mergeable`；整体 `needs changes / active`。合成旧记录只证明本轮 UI/文件恢复，不证明完整回放包原生成功导出、实际 LiDAR 或最低系统实跑。用户暂不能采集，下一步继续本机完整回放成功链及其余恢复/删除确认/布局。永久删除按具体动作确认；未暂存、提交、推送或合并。

持久证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration65-20261012/`：`baseline.json`、`originals/`、`Task65.md`、`ScopeExtension65.md`；初次原生失败 `batch-native-ui-t8hbcx0w` 与 `original-ui-attachments/`，单测原失败 `regression-original.xcresult`；最终定向 `regression-repaired.xcresult`，full `fruit-code-improvement-w7qggtic/report.json`，原生 `batch-native-ui-i3lra2qi/report.json`，审计 `validation-audit.json` 与 `final-ui-attachments/`。

## 第六十六轮：合成完整档案的原生回放成功链

2026-10-12。按用户“先完成本机验收”补齐原生成功路径，生产代码、PBX、算法与阈值均未改。既有六种合成证据回归始终执行；仅在本轮 UUID 和 owned 模拟器核对通过时导出生产仓储提交的六文件夹具，或消费实际原生导出包。新 runner 核对附件唯一性、文件名、字节数和 SHA 后播种空隔离目录；实际分享/完成态后才检查包，逐字节比较 JSON/Float32 输入、检查黄金段摘要和脱敏哨兵，清理后检查临时文件为空及原档摘要不变。二次生产 reader/builder 比较实际包的 identity/revision/golden、修正果数 2、融合证据 1 与产量；强制核验本轮专属黄金附件，避免可选分支未执行也被算作通过。

- 首轮 fixture 1、UI 2、golden 1 均通过，但 Xcode 重装迁移沙盒后宿主引用旧路径导致末尾保护检查失败；保留整轮结果，修正为重新解析当前 owned 容器再逐项核对六文件 SHA。随后新增断言误用 `YieldResult.fusedFruitCount` 导致编译失败；独立复审定位后改为 `diagnostics.fusedFruitCount`，失败包及首次 full 编译失败均保留。
- 最终新原生 **2/2**，fixture 与实际包黄金读回各 **1/1**；所有阶段退出 0、无失败/跳过/预期失败/运行时告警，全部宿主保护和清理标志为真。旧 CSV 故障/取消/修复重试/分享/内容/清理、回放失败/取消/CSV 恢复及品种确认原生 **2/2** 保留。两套 runner 仅删除各自 owned 模拟器。
- 最终 full **1195/1195、59 类、10 步退出 0**，Domain **45 源**与 Release 通过；与上轮 1195 方法集合完全相同，编译告警集合及两条旧 QoS 告警保持。365 项旧冻结清单有 363 项不变，变化为回放单测和旧 runner；另核对 UI 源及新 runner 摘要。**118 项范围外 dirty**、PBX 与全部生产源保持，309 文件构建身份仍为 `f39972e7810c7a2d4718cc5d962c82e1694cbef9521bca87f120a0f7c9b2d227`。
- 实际检查 iPhone SE 四张回放截图。另在第二 owned 模拟器用 Device Hub 点击历史 → 删除确认 → 取消，记录仍在、六文件摘要保持；弹窗漏列实际会删除的回放输入是下一轮候选，未执行永久删除。该模拟器暂留用于复验说明修复，不触碰既有模拟器和用户数据。

证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration66-20261012/`：`Task66.md`、`baseline.json`、`originals/`；原失败 `replay-native-ui-smldv17n`、编译失败 `replay-native-ui-zqdtyy_z`/`fruit-code-improvement-mg2m8d1o`；最终 `replay-native-ui-mshvni6h`、`batch-native-ui-b8cy7b4d`、`fruit-code-improvement-6k49wkzo`，`validation-audit.json`、`final-replay-ui-attachments/` 和 `manual-native/`。本轮范围 **mergeable**；合成成功链不证明实际 LiDAR、最低 iOS 16 或永久删除已验收，整体 **needs changes / active**。没有 Git 交付。

## 第六十七轮：准确说明历史删除的影响

2026-10-12。第 66 轮 Device Hub 实际点击发现单条删除提示只枚举 PLY/CSV/结果 JSON/manifest，遗漏仓储同样会删除的回放输入。本轮仅修正 `ScanHistoryDeletionCopy` 单条/全部 fallback 及中英文对应资源，明确全部关联文件、已有观测回放数据和不可撤销后果；没有修改删除控制器、路由、文件规则、算法、阈值、测试方法或 PBX。原截图与六文件摘要作为缺陷基线保留，不增加与低影响文案实现重复的单测。

最终 full **1195/1195、59 类、10 步退出 0**，Domain **45 源**与 Release 通过，原 1195 方法集合全等；编译告警集合与两条旧 QoS 告警保持。资源变化更新了生产构建身份，因此用当前构建重新生成合成完整档案，fixture **1/1**、实际回放导出/分享/内容/清理与品种确认原生 **2/2**、实际包 strict reader/原 builder 黄金读回 **1/1** 全通过，全部宿主保护为真。309 源/资源身份为 `4d2169f5cc11bf5eace5e63fac480c455edc3e967db5adcd668a34ac92234111`，Debug/Release/原生一致。

在 owned iPhone SE 安装该 full Debug，安装可执行摘要一致。用 Device Hub 实际打开中英文单条/全部四个确认弹窗，全文与按钮均可读，再分别取消；六个档案文件名和 SHA 全等，截图与独立宿主检查留存。365 项旧冻结清单中 362 项保持，仅三个文案文件变化；**119 项范围外 dirty** 及 PBX 保持。永久删除未执行，设备交互工具要求动作时确认，已就唯一合成记录提出明确请求，既有用户档案不参与。

证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration67-20261012/`：`Task67.md`、`baseline.json`、`originals/`、preflight `fruit-code-improvement-e3lp0ihe`；full `fruit-code-improvement-c91ge8ly`，当前身份原生 `replay-native-ui-_sqgimib`，`manual-native/` 四弹窗及取消截图、`validation-audit.json`。本轮文案与确认/取消范围 **mergeable**，整体 **needs changes / active**。英文首页 SE 指标 Today/Yield/Trees 等出现词内换行，已留存 `en-home-metric-wrapping.png`，作为下一轮有证据的紧凑布局修复；不扩大为整体 UI 重写。没有 Git 交付。

第 67 轮签署后的补验：用户明确回复“允许删除本轮合成记录”，再次核对 owned 模拟器唯一记录及六文件 SHA 后，用 Device Hub 点击单条 Delete。六个关联文件全部清理，历史页实际显示 No Scan Records，仓库外六原件摘要保持。`permanent-delete-acceptance.json`、`manual-native/permanent-delete-empty-history.png` 保存授权与结果；不修改原签署时点，不外推全部删除、删除故障或用户既有档案验收。

## 第六十八轮：英文窄屏指标不再词内换行

2026-10-12。实际 SE 英文首页截图中 Today/Yield/Trees/scans 在单词内折行，根因是三个均分卡片内始终横排标题、数值和单位。新增独立原生回归首先在原生产布局退出 65：三个标题实际高度 24 pt、scans 21.5 pt，旧品种门禁通过；原包、几何 JSON 和截图保留。新类仅追加在既有 UI Sources 文件，旧 Batch/Replay/Variety 内容逐字保持，PBX 未改。

只修改 `DashboardHeroMetric`，用既有 `ViewThatFits` 模式优先按单行固有宽度选择原横排，不足时改为标题上、数值/单位下。字体、卡片外观、聚合值、单位复数和按钮保持；长数值允许有限缩放。最终原生 **2/2** 通过，五个文字/单位高度分别为标题 **12 pt**、单位 **11 pt**，截图全文完整无省略，双主按钮可点击。Device Hub 实际检查当前构建中英文横竖屏，窄屏文字完整，宽屏横排保持，owned 空档案目录保持。

最终 full **1195/1195、59 类、10 步退出 0**，Domain **45 源**及 Release 通过；原 1195 方法集合、编译告警集合和两条旧 QoS 告警保持。当前生产身份变化后重新生成完整合成档案，fixture **1/1**、回放成功/分享/清理和品种原生 **2/2**、实际包黄金读回 **1/1** 全通过。309 文件身份 `376bc2270e1e7487d4ca923f4c72cdcd83c4d2a7e4a086f3b6948ff524464b99` 与 Debug/Release/两套原生/安装产物一致。365 旧冻结清单有 364 项保持，仅 HeroPanel 变化；UI 源另核对，**119 项范围外 dirty** 和 PBX 保持。

安装检查发现 67/68 的主可执行摘要相同而 App 代码 `debug.dylib` 不同。第 68 轮补验实际安装主程序、代码 dylib 与受测 Debug 全等，新增默认工作流段落防止只核对加载器；`ScopeExtension68.md` 和 `debug-loader-comparison.json` 留存依据，不将该较强检查回填为 67 签署时已执行。

证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration68-20261012/`：`Task68.md`、`originals/`，原失败 `baseline-dashboard-native-3y0iyml7` / `baseline-attachments/`，最终 `repaired-dashboard-native-gci9q1qs` / `repaired-attachments/`，full `fruit-code-improvement-3ruqub4n`，回放 `replay-native-ui-cgyw5nhy`，`manual-native/`、`validation-audit.json`。本轮范围 **mergeable**，全目标仍 **needs changes / active**；下一步逐项核验其余本机恢复门禁及外部条件，已有合成/模拟器证据不代替最低系统、真实 LiDAR、物理资源或人工 ground truth。没有 Git 交付。

## 第六十九轮：正常 App 单条删除失败与实际重试

2026-10-12。本轮关闭已有 controller/仓储回归不能替代的原生证据缺口，没有发现新的业务缺陷，未修改 App、测试、工程、算法或工具。preflight `fruit-code-improvement-09cq7rn_` 通过，检查真实 ScanHistoryView → deletion controller → store → repository → 历史刷新/重试链；365 项冻结源码与第 68 轮相同。当前全量中的七个具体删除/取消/迟到/事务等待回归均有 Passed 方法证据，本轮没有重跑 XCTest。

新建 owned iOS 27 SE，安装第 68 轮 full Debug，逐项核对主程序、实际承载代码的 debug.dylib 和生产身份。从生产仓储合成夹具复制六文件目标，并加入两文件 `CONTROL-KEEP-69` 控制记录，八份原件保存在仓库外。用户在动作时明确允许本轮目标的失败及重试验收；只对目标 CSV 设置可撤销 immutable 标志，不涉及既有扫描或全部删除。

实际 Delete 失败弹窗准确列出 **CSV、PLY point cloud**：其余四个目标伴随文件清理，CSV/PLY 保留原摘要，控制记录保持。点击 Close 后损坏记录与警告仍在；再次对同一记录确认 Delete，又得到相同残留说明。保留该失败弹窗，仅解除 CSV 标志后点击实际 **Try Again**，目标剩余两文件清理，警告和目标记录消失，历史只显示完整控制记录。各阶段逐项核对文件和截图；宿主没有 unlink 目标或重新启动 App 代替重试。

证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration69-20261012/`：`Task69.md`、`existing-regression-evidence.json`、`manual-native/report.json`、五阶段 JSON/PNG、`fixture-originals/` 与 `validation-audit.json`。124 项既有 dirty 文件中只有两份验收文档补记，其他文件、PBX、HEAD 和空暂存区保持。独立复审见 `Review69.md`；本轮单条失败/关闭/恢复范围 **mergeable**，不外推批量全部删除或多记录失败子集的原生通过。最低 iOS 16、真实 LiDAR/物理资源/ground truth、其余恢复门禁和 Git 交付仍开放，整体 **needs changes / active**。

## 第七十轮：正常 App 历史读取失败与真实重试

2026-10-12。补验冷启动无缓存与已有成功缓存的实际目录 IO 读取失败，没有发现新的业务缺陷，App、测试、工程、工具不变。preflight `fruit-code-improvement-ym69m5je` 通过；检查 Dashboard/ScanHistoryView → history store → detached disk read → repository → load presentation → Retry 的真实链。第 68 轮结果树中十个精确历史读取/取消/迟到/错误呈现方法均 Passed，本轮没有重跑 XCTest。

在新 owned iOS 27 SE 安装相同 full Debug，核对主程序、代码 debug.dylib 和当前生产身份。保存外部八原件，将 scans 目录可逆改名保留，在原路径放普通文件制造真实读取错误。冷场景显示明确错误卡片而非空历史；恢复目录后点击真实 Retry，出现两条完整记录。再次阻断后，在同一 App 会话返回首页再打开历史页，显示“上次成功读取的 2 条记录”警告且保留旧列表；恢复目录再点击真实 Retry，警告消失，两条记录及数值保持。修复前后、点击前后六阶段均核对八档案 SHA，不 unlink 原档、不执行永久删除、不重启 App 代替重试。

原生下拉手势尝试未取得刷新完成或失败转换的可判定证据，不计通过，也不据此宣称业务缺陷；该入口继续开放。证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration70-20261012/`：`Task70.md`、`manual-native/report.json`、六阶段 JSON/PNG、`fixture-originals/`、`existing-regression-evidence.json`、`validation-audit.json` 及 `Review70.md`。124 项基线 dirty 中仅两份验收文档补记，其余 122 项、365 项 freeze、PBX、HEAD 与空暂存区保持。最低 iOS 16、真实 LiDAR/资源/ground truth、全部删除/失败子集、其他门禁及 Git 交付仍开放，整体 **needs changes / active**。

## 第七十一轮：历史刷新动作与取消边界

2026-10-13。第 70 轮下拉缺口继续检查；preflight `fruit-code-improvement-9rf7_akr` 通过。原生自动 drag/scroll 没有可判定转换，未直接据此归因 App。追加生产 sheet 中真实 UIKit 刷新控件的公开事件回归后，悬挂读取在旧实现实际被取消，失败和更新均不发布。最小参考 ScrollView 使用同一 loader 能通过；固定 TagStore、仅移动 modifier 均不能修复。最终直接传同一 historyStore 给 ContentView，在纵向 ScrollView 的 refreshable 中显式捕获它，排除中间函数值及整个 View 捕获；水平筛选栏不再带刷新控件。View 仅发出原 reload 命令，不新增任务、磁盘工作或状态 owner。捕获变化与 SwiftUI 动作生命周期的关联是 A/B 证据推断，不声称确认了框架内部机制。

新增一个生产回归方法，确认两个在途请求的 pending/loading/indicator/current/window、失败保留旧记录、第二次更新替换记录、完成均未取消 `[false,false]`，并断言仅真正纵向历史列表拥有刷新控件。全部旧测试文本保持；参考诊断方法只保存在外部。早期函数值方案虽全量通过，但新增 Sendable 编译告警，因此拒绝最终验收；字面量包装去掉告警却重现取消，也保留失败。最终直接 owner 候选没有新告警，`refresh-direct-owner` 精确方法树 1/1 Passed、runtimeWarnings=[]。

最终 full `fruit-code-improvement-fjhcu48a` 和独立 `audit_build71.py` 均退出 0：**1196/1196、59 类、10 步 0、Domain 45 源/Release**，原 1195 方法全保留，规范化编译告警集合与两条旧 QoS 完全相同。严格 gate 通过后才执行当前身份 `replay-native-ui-vclkz48o`，fixture **1/1**、实际回放导出/分享/清理和品种确认原生 **2/2**、实际包黄金读回 **1/1** 通过，原档/payload/golden/owned 清理均通过。当前 365 冻结项中 362 保持，变化仅两生产视图和该测试；工程、UI 测试与工具保持。

原生使用唯一 owned71 SE，旧八文件另存隐藏 baseline 目录，当前黄金六文件和控制两文件另做外部备份。真实目录故障仅改名保留与普通文件占位，修复仅改名复原，所有十六原件及外部十六备份摘要保持。自动拖动没有取得可判定转换；用户明确确认“在历史页直接下拉后出现”失败横幅。代理随后取图已是首页，因此失败图只记为同会话重开后捕获：明确上次成功读取的 2 条记录，旧列表保留。修复前后错误画面 SHA 相同。用户随后确认“横幅消失，仍有 2 条记录”；代理在未插入 Retry/Done/重开/重启的同页恢复现场取图核对：没有错误横幅，两条完整记录及 7 fruits/1.2 kg、2 fruits/0.5 kg 保持。六阶段均保留当前八档案、前八原件及外部十六原件 SHA。不把第一下拉冒称代理直接截图证明，不把自动公开事件解释为触摸证据。

证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration71-20261013/`：`Task71.md`、三源原件/增量、失败诊断包、最终定向附件、`full-method-preservation.json`、最终 full/replay、六阶段 `manual-current/`、人工观察记录和 `validation-audit.json`。第二审查者已最终独立核对代码、文档、方法树、安装 exe/dylib、恢复现场及十六原件，限定本轮 **mergeable**、无阻塞，见 `Review71.md`。其直接检查后仅清理唯一 owned71 临时设备，清理前两个八文件目录摘要和外部十六原件保留，其他设备/default 保持；清理后再次审计通过。整体仍 **needs changes / active**，没有 Git 交付。下一步按原缺口表推进全部删除/失败子集与最低系统；真实 LiDAR 和 ground truth 依用户要求暂缓。

## 第七十二轮：全部删除、混合失败与直接重试补验

2026-10-13/14。按原 R6 及本机验收缺口检查 Clear All → deletion controller → history store → repository → 刷新/失败子集重试，没有发现新的业务代码缺陷。App、测试、工程和工具均未改；本轮只更新两份验收/下一步文档。125 项已有 dirty 路径保持，123 项范围外摘要与 365 项冻结源码保持，HEAD 和空暂存区保持，没有 Git 交付。

- **正常清空。** 只使用 owned iOS 27 SE 和合成记录，安装第 71 轮 full Debug；核对主程序、实际代码 debug.dylib 及 309 源/资源身份。用户对本轮两记录明确授权后，实际 Delete All 清理八个目标文件，历史显示 No Scan Records；目录外控制和外部原件保持。
- **混合失败和 Close。** 两份独立生产黄金记录各六文件及 legacy 两文件共三记录 14 文件；仅给 B.csv 和 legacy result JSON 设置可解除的 immutable 标志。用户具体授权后实际 Clear All：成功记录六文件清理，B 保留 CSV/PLY，legacy 保留 result JSON/PLY，共四残留。弹窗准确列出两失败记录和 result JSON、PLY point cloud、CSV。Close 后损坏提示/记录仍在，再次实际清空仍得到相同失败与四个原摘要残留。
- **归因缺口保留。** 首次解除故障后的最终现场只剩 Late 控制，但按钮时间和窗口映射不足，用户明确没有手动操作；该观察保留为 `mixed-recovered-unattributed`，不作为直接 Try Again 通过。没有把后续补验回填成首次动作证据。
- **获准补验通过。** 相同三记录重新准备，Late 两文件仅改名暂存。用户于本轮确认页明确允许再次清空失败及重试，实际得到上述两失败/四残留；归还 Late 后只解除两标志，错误弹窗画面保持。以新截图核对紧凑窗口 `deviceWindow-AppWindow-1`，直接点击 Try Again；没有 Done、重开或 App 重启。动作前后 UTC 间隔 **37.905 秒**，目录修改时间和恢复截图时间均落在该窗口；六文件变为 Late 两文件，页面只显示完整 LATE-KEEP-72、9 fruits/2.5 kg，错误弹窗/横幅消失。目录外两文件与外部 18 原件每阶段摘要保持，宿主没有 unlink 扫描目标。
- **证据边界。** Late 只加入磁盘，未证明在点击前进入当前缓存，其存活只证明重试未扩为磁盘枚举。精确 failed-ID 子集另由实际 controller 源码和现有七个精确删除/取消/提交竞争方法证明，不能把该原生夹具夸大为缓存全列表区分。原 12 阶段和补验六阶段的 PNG/JSON、授权及有界时间证据分别保留。
- **验证。** 本轮生产夹具回归 **1/1 Passed、退出 0、零 runtimeWarnings**。App/Test 与第 71 轮受测源码完全相同，复用其 **1196/1196、59 类、Domain 45 源、Release**，不虚增全量次数；原两条 QoS 告警的限制保持。`git diff --check` 与 staged diff check 通过。只读复审与 owned 环境清理结果另记，原生补验本身已取得所需证据；整体仍 **needs changes**，最低 iOS 16 实跑、真实 LiDAR/ground truth/物理资源及 Git 交付未完成。

最终独立只读复审 `/root/review_iteration72_final` 无阻塞，限定第 72 轮 **mergeable**。审查者直接核对原图/18阶段、安装构建、live控制/18原件、七个原始精确方法及范围保护；之后按其条件再次检查并只清理 owned72。shutdown/delete 均退出 0，default 和其余设备 ID 保持、18 外部原件保持，清理后 `audit72.py` 再次退出 0。没有通过产品删除控制记录，没有清理其他环境。

持久证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration72-20261013/`：`Task72.md`、`baseline.json`、`originals/`、`fixture-capture.xcresult`、`existing-regression-evidence.json`、`manual-native/report.json`、`retry-action72.json`、`fixture-originals/`、`Review72.md`、`review-decision.json`、`manual-simulator-cleanup.json`、`validation-audit.json` 和 `audit72.py`。`completion-requirements72.json` 与阻塞审计保留授权前时点，最新要求状态见 `completion-requirements72-final.json`；不能视为当前仍缺本轮授权。下一轮提示词见同根 `Next73.md`。

## 第七十三轮：最低系统运行条件核验

2026-10-14。第 72 轮收尾后继续原 A32 最低系统验收，preflight `fruit-code-improvement-46qz4a3j` 退出 0。本轮没有修改 App、测试、工程或工具，也没有下载 runtime、改变全局 Xcode 选择或降低系统声明。当前指定 Xcode 为 27.0，宿主 macOS 27.2/arm64；simctl 仅有 iOS 27 runtime，当前五台已配对 iOS 设备均为 27.x。

核对受测 Debug 实际代码 dylib 和 Release 主程序：Info 的 MinimumOSVersion 与各 Mach-O 架构的 minos 都是 **16.0**，SDK 为 27.0。它们证明构建目标声明，不能证明 iOS 16 启动或行为。Apple [官方支持表](https://developer.apple.com/xcode/system-requirements) 将 Xcode 27 的模拟器支持起点列为 iOS 17；支持较旧 runtime 的 Xcode 26.6 官方宿主范围止于 macOS 26.x，不能据此认定在当前 macOS 27.2 并行装旧 Xcode 就得到受支持的补验环境。因此最低系统缺口需要兼容宿主/工具链和实际 iOS 16 runtime，或另有 iOS 16 设备及有效安装/验收条件；**最低系统实跑仍未通过**。原生 UI target 的最低 17 声明保持，不把其 iOS 27 结果当作 App 最低版本证据。

本轮范围仅两份当前执行/验收文档；125 个已有 dirty 路径、123 个范围外摘要、365 项受测源码、HEAD/空暂存区保持，diff 检查通过，没有重跑无源码变化的 XCTest。仓库外持久证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration73-20261014/` 保存 preflight、原件、实际工具/runtime/设备 OS 清单、Debug/Release build version、官方原始 HTML/SHA 与选定三行、`Task73.md` 及可执行的 `MinimumOS16Acceptance.md`。配对设备原始标识仅留在仓库外。独立复审另记；整体仍 **needs changes**，本轮条件核验不替代真实运行、LiDAR/ground truth/物理资源或 Git 交付。

最终独立只读复审无阻塞，限定第 73 轮条件核验与文档 **mergeable**，见同根 `Review73.md`；其重新读取真实 Mach-O、私有设备清单、官方当前表格及保护摘要，结论与本轮原始证据一致。最低 iOS 16 实跑与整体目标仍为 **needs changes**。当前已询问用户是否另有可补验设备/兼容 Mac，未收到环境信息前保持待验。

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
| 第三十六轮冷入口失败回归 | /private/tmp/fruit-iteration36/before.xcresult | 1 个实际断言失败，退出 65；Xcode 额外诊断收集错误单独保留 |
| 第三十六轮定向及渲染 | /private/tmp/fruit-iteration36/after.xcresult；attachments/ | 8 通过，退出 0；八张真实工厂/选择器/刷新/空态附件逐张检查 |
| 第三十六轮 storage / UI / full | /private/tmp/fruit-iteration36/fruit-code-improvement-jlizdi4n/report.json | 1023 通过，0 失败/跳过/预期失败，59 类、9 步退出 0；Domain / Release 成功，快照一致 |
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

**2026-10-14 当前执行入口：** 下方 2026-10-07 更新、四项候选和后续历史提示词保留各自时点，不能直接作为当前待办。第 49–64 轮已实施根配置、GPU 屏障/错误恢复、完整领域依赖边界、批量应用编排、分类冻结、Dashboard 聚合、固定最终云/文件暂存及实际输入回放包；第 65–71 轮补齐回放错误/成功链、删除说明、窄屏布局、单条删除失败重试、历史 IO 失败与下拉恢复。当前生产身份为 `897a49c36f4a80c07945a3c6592240693297abc1c7800a6d8e4a8ec699e85907`（309 源/资源），365 项受测冻结清单保持；同源码全量为第 71 轮 1196/1196、59 类、Domain 45 源及 Release，不记作第 72 轮新执行。

当前按以下顺序推进；各项没有工作量权重，不折算完成百分比，也不沿用下方历史 3/8 口径：

1. **第 72 轮已关闭。** 正常清空、混合失败、Close 后再失败及获准的直接 Try Again 补验已通过；37.905 秒有界记录证明六文件变为 Late 两文件。独立复审为本轮 mergeable，owned72 安全清理、其他设备 ID/18 外部原件保护及清理后审计均通过。原未归因观察不回填。详见第 72 轮及 `Next73.md`；不重复该永久删除验收。
2. **最低系统需要兼容环境。** 第 73 轮核对当前 macOS 27.2/Xcode 27、仅 iOS 27 runtime、已配对设备均 27.x；官方 Xcode 27 模拟器支持最低 iOS 17。当前 Debug/Release 的实际 minos 16 保持，不能把构建当实跑，也不为通过验收改变产品最低版本。下一步按 `MinimumOS16Acceptance.md` 在兼容宿主/工具链和 iOS 16 环境取得真实运行结果，逐项区分宿主测试、正常 App 触摸及物理捕获。
3. **真实观测与物理资源。** 用户暂时无法采集，先完成可执行的本机验收。实际 LiDAR 正常/退化输入、人工果数/重量、同设备 30/60/120 秒与峰值内存/阶段计时仍未验收；合成六案例及数值 payload 不能关闭这些要求。
4. **按范围完成 Git 交付。** 当前轮未暂存、提交、推送或合并；保留已有 dirty，交付前明确对应改动范围并使用受测最终源码。整体仍为 **needs changes**，第 72 轮原生补验通过不代表原目标完成。

当前逐项核验与方法定位保存在仓库外 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration72-20261013/`，`completion-audit-method-locators.json` 仅用于定位已执行方法；方法名本身不证明其断言覆盖整个要求。新的代码迭代须由实际缺陷或未闭合的原架构职责驱动，不重复已完成迁移。

**2026-10-07 第 53 轮更新：** FusionValidator 逐字进入 Domain/Fusion，完整独立 Domain 编译由 24 源增至 25 源；421 前后方法和 1110 全量/Release 通过。第 52 轮更新中的纯 validator 候选现已关闭，当前继续可靠证据准入的完整责任边界，提示词见第 53 轮末。下方列表及前一更新保留各自历史时点，整体主线状态未因单节点迁移改变。

**2026-10-07 更新：** 下方第 1 项保留第 51 轮时点的候选记录；其 GPU 失败分类和用户恢复代码/模拟器边界已由第 52 轮关闭，物理验收仍开放。当前下一步为纯 FusionValidator 进入 Domain，按第 52 轮末提示词执行。整体主线完成口径仍是 3/8（37.5%）已关闭、5 项部分实现；没有基于工作量的百分比，历史 90%/80% 定性估算已由第 48 轮核验撤回。

根据当前代码，前述扫描/仓储边界、观测链路、质量关联、融合值服务、回放、品类/设置分层和结果/质量/诊断值归属已实施；整个 Domain 的 24 个源文件已通过独立 iOS 模块编译，门禁已接入 CI 并验证本地失败传播。接下来补齐运行证据：

1. **贯通 GPU 失败分类与用户恢复。** 第 51 轮已修复并验证写入失败禁止冻结/发布、同代粘性状态、旧回调隔离及 stage 固定代际，最终 530 定向、1091 全量、Domain/Release 通过。当前 Application 仍把 GPU 失败归为 pointCloudExport，UI 解释成存储错误并重试同捕获，是有真实调用链依据的 P2 候选。下一轮先建立实际错误路由回归，区分新扫描恢复、过期捕获与可重试排空/文件错误，保持所有权和较新扫描不受旧任务影响；提示词见第 51 轮末。完成后恢复纯 FusionValidator 进入 Domain，以及 [原 R0–R7 核验](REFACTOR_COMPLETION_AUDIT_2026-10-05.md) 中的可靠准入/composer/几何、全应用协作、真实观测和资源目标。完整 ARKit/物理资源继续单列，整体目标未完成。
2. **补齐完整记录删除流程的剩余证据。** 隔离夹具的历史读取、三种批量格式、取消/清理、校准基线导入及保存已实际核对；第 28–30 轮发现的状态、临时目录所有权和颜色问题已修复。删除确认与取消通过，永久删除尚待用户在操作时确认；得到具体确认后只操作 UI-FIXTURE-B，核对 PLY/结果 JSON/完成清单消失、其他源摘要保持及历史刷新。第 37 轮 Device Hub 已可操作，永久删除缺口仍为对应操作确认。物理完成/重试仍需另行验收，不用模拟器无 LiDAR 的页面替代。
3. **设备回放与物理验收。** 混合几何和必须重分配的合成回放已完成，不重复。下一步设计有采样上限和脱敏规则的真实观测基线，并标明人工果数、采集条件及模型/配置身份。已发现可连接 LiDAR iPhone；实际 30/60/120 秒绕拍需要操作者与场景基准。分别记录物理内存、采集/结束耗时、深度拒绝诊断和人工果数误差，不能用模拟器通过代替。
4. **持续构建远程验收与模块收益评估。** Domain 门禁及模拟器编译已在 PR #10 的 run `36801712785`、PR #11 的 run `36827532091` 实测成功，覆盖第 1–30 轮；第 31 轮经 PR #12 的 run `36833185872` 成功后合并为 `f440f587`。第 32–35 轮经 PR #13 的 run `36965233999` 成功后合并为 `76e15a99`；后续第 36–42 轮已交付，第 42 轮 PR #16 合并为 `75c85cc4`；第 43/44 轮按本次用户授权交付，实际远端终态见交付检查点和随后核验结果。当前有 App、单元 XCTest 和独立 UI XCTest 三个 target；Domain 类型仍使用模块内可见性。framework/package 需要按消费者定义公开 API，只有能减少实际依赖复杂度时才启动该迁移。当前维持单 App target 与完整 Domain 编译门禁，保留模型/shader 归属及 ReliableYieldEvidence 准入权限。

这些事项尚未完成，不能用当前定向或全量 XCTest 代替它们的实现与设备验收。目标继续保持 active。

## 下一轮执行提示词

以下为历史累计实施上下文；当前优先级和证据状态以上节“2026-10-14 当前执行入口”及回放设计第 6 节为准。旧候选、旧测试数量和旧永久删除记录不得直接复用为本轮待办或动作授权。

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
结果、质量、诊断值与冻结身份已经纳入；生产保持单 App target，单元与原生 UI 测试使用各自 target。
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
PR #10/#11/#12/#13 的远程 CI 已实测通过并合并，覆盖第 1–35 轮。不重做该集成，不冒充 XCTest 或 IPA 签名；本次授权交付第 36–39 轮，状态以对应 PR 为准。
第 28 轮已修复最近记录默认 0 被呈现为可靠结果的问题，第 29 轮已移除 UI 过时临时目录检查，由导出服务统一判断所有权。第 30 轮在实际 SwiftUI sheet 边界声明深色方案，修复固定深色背景上的黑色标题与分组文字；浅色系统入口有失败回归与修复后证据。最新最终全量 1026 项通过；真实 UI 已核对三种批量产物与取消、收起、切换格式及页面关闭后的清理。不要重做这些修复或把合成夹具当真实精度证据。
完整历史读取、校准未校准基线导入和删除确认/取消已有证据；永久删除尚待用户确认，物理验收仍缺操作者采集。下一步在已确认授权后完成隔离模拟器 UI-FIXTURE-B 的删除，检查关联文件与历史刷新并保护其他夹具。未收到确认时保留该记录；继续补充真实设备采集条件、人工果数及资源测量，不制造无关重构来代替尚缺的证据。
第 31–34 轮已贯通仓储历史查询/删除、生产完成刷新、工作台/历史/批量列表、导入、校准扫描来源和预览。
第 34 轮关闭/返回原生走查已补齐，第 35 轮报告与趋势根历史装配和最终 1022 项全量已完成。
第 36 轮历史对比根装配与选择/刷新回归已完成，最新全量 1023 项通过。
第 37 轮地图根装配和选中 ID 生命周期已完成，最新全量 1024 项通过。
第 38 轮已补齐对比关闭/重开/选择器取消/结果返回，最新全量 1025 项通过。
Mac 已可操作；趋势、地图空态入口/关闭及对比实际选择有原生证据，
报告实际两条完整记录统计与关闭、对比返回已补齐，11 份档案/校准文件保持。
第 39 轮设置、相机和品种当前品类已共用根配置，最新全量 1026 项通过；
11 份档案和 21 项保护设置保持，实际设置/菜单取消/返回/关闭/重开已走查。
第 40 轮已贯通启动与品类不匹配根配置、动作凭证和设置返回显示，最新全量 1034 项通过；
11 份档案及本轮 25 项保护设置保持，启动入口/取消/重开已原生走查。
第 41 轮已贯通分类生产者、实际 Dashboard 激活和重新扫描，最新全量 1039 项通过；
11 份档案和 25 项设置保持，分类分页/表单取消/转入启动/重开/完成返回已原生走查。
第 40–41 轮已由 PR #15 合并，第 42 轮已贯通历史筛选/复核、结果快速标记及批量导出分类消费者，
最新全量 1042 项、59 类及 Release 通过；原生筛选/返回与批量关闭/重开已走查，11 份档案及全部 7 项实际持久偏好保持。
第 42 轮 PR #16 已合并为 75c85cc4；第 43/44 轮按当前“推送并合并”授权交付，核对随后检查点。
第 43 轮校准、品种编辑与扫描计划已共用根参数，1045 项单元测试、59 类、Release 及
独立原生 UI 确认测试通过；11 份档案和全部 7 项实际持久偏好保持。
原生 UI target/独立 scheme 只用于自有临时模拟器，默认单元 scheme 和 App iOS 16 声明保持。
第 44 轮已保护未编辑/已提交校准草稿与同字段冲突、关联下界，1053 项、59 类及 Release 通过；
11 文件及全部 7 项实际偏好保持。第 43/44 轮已经由 PR #17 合并为 f8d6811b。
第 45 轮品种编辑已原子合并实际修改字段、保护参数重置身份和直径上下界；
15 项定向、1065 项/59 类全量、Release、独立原生 UI 1 项与原生交互通过，
11 文件及整份 7 项偏好保持。下一步按第 45 轮提示词先复现校准同数值重置身份，
毫米显示 Float 截断单独处理，不重做根参数迁移或品种字段合并。
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
