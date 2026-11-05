# 真实观测留存与黄金回放：下一轮设计

2026-10-08 设计，2026-10-13 状态更新。第 64–70 轮完成输入留存、错误呈现、合成原生回放、删除说明、英文窄屏指标修复、单条删除失败/重试及历史读取失败/缓存/实际 Retry。第 71 轮修复刷新动作归属和捕获边界，当前代码全量 1196/1196、Domain/Release、同身份回放 fixture1/UI2/golden1 通过；第一次直接下拉失败由用户确认，第二次同页下拉恢复由用户确认并核对当前恢复现场。只操作隔离合成夹具，十六原件与备份保持。真实 LiDAR 输入包、资源/精度、最低系统和其他本机门禁仍开放，整个目标仍为 **needs changes / active**。

## 实施检查点：第 64 轮代码验证完成

- 生产 finalization 保存实际 Input、完整观测/配置/身份和按原顺序写出的 Float32 点段；小凭证接入唯一仓储事务，manifest 最后发布。超预算明确 unavailable，不截断估算输入。严格 reader、研究状态、取消、失败恢复和永久删除包含新 artifact。
- 本地 `.ftsreplay` 容器按条目流式写入和有界读取，省去显式 GPS、树名、分类/标签、图像及扫描日期，保留投影和稳定窗口所需的局部坐标与帧时间；不自动上传。回放调用既有 builder，比较结果、诊断和几何，并验证打包的算法/源码身份。Debug/Release 的身份均与当前 309 个生产源/资源文件一致。
- 独立复审发现并修复执行算术域崩溃、reader 错误后继续读、回滚失败丢备份、恢复目录删除/同名前缀归属及准备 IO 重试丢观测。原始失败包均保留。捕获与绑定由同一结束流程分阶段拥有，IO 前保留原快照，重试不重复消费 coordinator；取消、成功和 reset 释放。
- 最终定向 **208/208**，联合 storage/fusion/lifecycle **971/971**，全量 **1194/1194、59 类**，Domain **45 源**与 Release 均退出 0；无失败/跳过/预期失败，原 1173 项方法全部保留。编译告警集合保持，仍有两条旧内部 QoS 告警。首次最终 full 的旧校准关闭测试为 1193 通过/1 失败；补上真实草稿提交的有界等待后再全量通过，生产校准实现和全部原精确断言保留。
- 正常 App 原生选择回放包显示说明并隐藏普通字段/分组，切回 CSV 恢复选项，关闭返回首页；2560 个 Documents 文件及 8 项偏好值摘要不变，实际走查二进制/身份与最终受测 Debug 相同。当前只有两条不完整旧记录；完整记录原生回放导出/失败弹窗及其余恢复、删除、紧凑布局不由此关闭。
- 原始证据：`/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration64-20261011/`。最终风险 `fruit-code-improvement-0jmog89b`，最终 full/Release `fruit-code-improvement-t6yqp7n2`，源码/方法/PBX/告警检查见 `validation-audit.json`，原生见 `native-ui/`。没有 staging、commit、push 或 merge。

## 第 65 轮：原生失败路径与错误呈现

旧完整扫描可导出 CSV，但没有回放输入。隔离 iPhone SE 原生测试首次在具体不可回放说明处失败；`BatchExportFailurePresentation` 仅识别 Batch/Cocoa 错误，四类 `ScanReplayError` 均落入通用提示。新增定向回归在原生产实现失败，随后增加四个明确映射，保留未知错误兜底和原有取消/重试行为。

最终导出测试 **141/141**、全量 **1195/1195、59 类**、Domain **45 源**与 Release 通过；原 1194 方法全保留，仍有两条旧 QoS 告警。原生 **2/2** 通过：保留 CSV 存储故障/取消/修复重试/分享/清理链，新增回放具体失败/取消/无残留/原档摘要保持/切回 CSV 字段恢复；既有品种确认门禁仍执行。当前 309 个生产源/资源身份为 `f39972e7810c7a2d4718cc5d962c82e1694cbef9521bca87f120a0f7c9b2d227`，最终 Debug/Release 与原生构建一致。第 64 轮数据仍作为历史证据，不替代此次构建身份。

证据：`/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration65-20261012/`；原生初次失败 `batch-native-ui-t8hbcx0w`、定向原失败 `regression-original.xcresult` 均保留；最终 full `fruit-code-improvement-w7qggtic`，原生 `batch-native-ui-i3lra2qi`，方法/源码/告警审计见 `validation-audit.json`，原生截图见 `final-ui-attachments/`。仅闭合本轮错误呈现与旧记录失败恢复范围，尚未证明完整回放包原生成功导出、真机精度或最低系统运行。没有提交或推送。

## 第 66 轮：合成完整回放的原生成功验收

生产仓储提交的六文件合成完整档案，经附件 SHA/长度/名称核验后播种空 owned iPhone SE。实际页面选择回放 → 导出 → 系统分享 → 完成态 → 收起清理；宿主核对实际包输入 JSON/Float32 与原档逐字节一致、黄金段摘要、脱敏哨兵及原六文件保护。二次生产 strict reader/原 builder 消费实际导出文件，identity/revision/golden 相同，修正果数 2、融合证据 1、产量 0.48540313 kg；本轮专属附件是强制门禁，不能把未执行的可选验证分支算作黄金通过。

最终 fixture 1、原生 2、golden 1 全部 Passed/退出 0；原 CSV/失败恢复与品种门禁另 2/2，全量 1195/1195、Domain 45 源/Release 通过。1195 方法全保留、编译告警及两条旧 QoS 告警保持；生产/PBX 不变，Debug/Release/两套原生生产身份仍与第 65 轮相同。首轮沙盒迁移后旧路径失败及新增断言成员错误造成的编译失败完整保留，修复后重跑最终源码。证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration66-20261012/`，最终 `replay-native-ui-mshvni6h`、`batch-native-ui-b8cy7b4d`、`fruit-code-improvement-6k49wkzo` 与 `validation-audit.json`。

Device Hub 在第二 owned SE 实际点击历史删除确认/取消，原六文件 SHA 保持；弹窗漏列回放数据为下一轮修复候选，永久删除未执行。本轮回放范围 mergeable，实际 LiDAR、最低系统和其余验收仍开放；没有提交或推送。

## 第 67 轮：历史删除说明修复与实际取消验收

单条与全部删除说明统一覆盖全部关联文件、已有回放数据及不可撤销后果，中英文与 fallback 一致；删除行为不变。最终 full 1195/1195、Domain 45 源/Release 通过；原 1195 方法、编译告警及两条旧 QoS 告警保持。生产文案资源更新身份后，以当前构建重建夹具并重跑 fixture 1 / 原生 2 / golden 1，全部阶段与保护门禁通过；当前 309 文件身份 `4d2169f5cc11bf5eace5e63fac480c455edc3e967db5adcd668a34ac92234111` 与 Debug/Release/原生一致。

Device Hub 在 owned SE 实际检查中英文单条/全部四弹窗并取消，六原文件摘要保持，安装可执行与 full Debug 相同。永久删除待动作时确认，英文首页指标的词内换行已保留为下一轮局部修复候选。证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration67-20261012/` 的 `validation-audit.json`、`manual-native/`，full `fruit-code-improvement-c91ge8ly` 与原生 `replay-native-ui-_sqgimib`。本轮范围 mergeable，整体仍 active；没有 Git 交付。

第 67 轮原签署后的补验：用户明确允许删除唯一合成记录，实际单条 Delete 清理六文件并刷新为空历史，外部原件摘要保持。证据 `permanent-delete-acceptance.json`；该结果不外推全部删除、失败路径或用户档案。

## 第 68 轮：英文紧凑布局与当前构建复验

原生失败回归记录三个标题 24 pt、scans 21.5 pt 的词内换行；`DashboardHeroMetric` 横排固有宽度不适合时纵排标题/数值单位，保留字体、卡片、数值、单位与动作。修复后布局/品种原生 2/2，标题 12 pt/单位 11 pt，实际中英文横竖屏全文完整、宽屏横排保持。full 1195/1195、Domain 45 源/Release 通过，原方法及编译/两条旧 QoS 告警保持。当前生产身份重新生成夹具后回放 fixture 1 / 原生 2 / golden 1 全通过。

当前 309 文件身份 `376bc2270e1e7487d4ca923f4c72cdcd83c4d2a7e4a086f3b6948ff524464b99` 与 Debug/Release/两套原生/安装产物一致；明确核对承载 App 代码的 debug.dylib，不能只比较 Debug 加载器。证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration68-20261012/` 的原失败、最终原生/full/replay、`manual-native/` 与 `validation-audit.json`。本轮范围 mergeable，整体仍 active；没有 Git 交付。

## 第 69 轮：单条删除的实际 IO 失败与恢复

本轮没有 App/测试/工程/工具改动，365 项源码冻结与第 68 轮相同。安装主程序、代码 debug.dylib 和当前 309 文件生产身份逐项一致；第 68 轮 full 1195/1195、Domain 45 源/Release 等作为相同源码的已有证据，本轮未重跑。已有七项精确删除回归的 Passed 方法另留存。

在新 owned iOS 27 SE 中，获准六文件合成目标的 CSV 设置可撤销 immutable 标志。实际 Delete 失败准确提示 CSV/PLY 残留，其他四文件清理；Close 保留损坏记录和警告，再次确认 Delete 后仍准确失败。保持失败弹窗，宿主只解除 CSV 标志，再点击实际 Try Again，目标六文件最终全部清理，历史只保留完整 `CONTROL-KEEP-69`。控制两文件和八份外部原件逐阶段 SHA 保持；没有宿主 unlink 目标或重启替代重试。

证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration69-20261012/` 的 `manual-native/`、`fixture-originals/`、`existing-regression-evidence.json`、`validation-audit.json` 和 `Review69.md`。本轮单条失败恢复范围 mergeable，整体仍 active；没有 Git 交付。此结果不关闭全部删除或多记录失败子集的原生验收，不替代最低系统、真实输入、资源和准确率。

## 第 70 轮：历史目录读取失败与实际 Retry

没有 App/测试/工程/工具改动，365 项源码冻结及当前生产身份保持。新 owned iOS 27 SE 的安装主程序、代码 debug.dylib 与第 68 轮 full Debug 全等；第 68 轮 full 1195/1195、Domain 45 源/Release 是相同源码已有证据，本轮零新 XCTest，十项精确历史回归 Passed 方法另留存。

将八文件 scans 目录可逆改名保留，在原路径放普通文件，实际 App 冷读取显示错误卡片而非空历史；修复后真实 Retry 恢复两完整记录。第二次故障由同会话返回再重开历史页触发，明确“上次成功读取的 2 条记录”，保留旧列表；再次修复和实际 Retry 后警告消失。六阶段八档案及外部八原件 SHA 全等，未 unlink 原档、未执行永久删除或重启代替重试。

下拉手势未取得有效刷新证据，不计通过或据此判断业务缺陷。证据 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration70-20261012/` 的六阶段 `manual-native/`、`fixture-originals/`、`existing-regression-evidence.json`、`validation-audit.json`、`Review70.md`。没有 Git 交付；本轮仅补历史读取错误与重试原生证据，其他验收仍开放。

## 第 71 轮：刷新修复与当前身份回放

生产 sheet 的实际刷新控件悬挂加载回归在旧实现失败：结果返回时任务已取消，store 正确拒绝发布。直接在唯一纵向记录 ScrollView.refreshable 显式捕获同一 historyStore 后通过；水平筛选不再继承刷新控件。仅两生产视图和一项新增回归，不修改 store 取消/代次/仓储、不改变融合或可靠估产规则。任务捕获影响 SwiftUI 生命周期属于对照证据推断，未声称确认其内部实现。

最终 `fruit-code-improvement-fjhcu48a` **1196/1196、59 类、10 步退出0、Domain45/Release**，原1195方法全部保留，旧编译告警集合/两条QoS保持。当前 `replay-native-ui-vclkz48o` fixture **1/1**、原生 **2/2**、实际包 strict reader/原 builder 黄金读回 **1/1** 全通过，原档、实际payload与owned环境清理保持。最终309文件身份 `897a49c36f4a80c07945a3c6592240693297abc1c7800a6d8e4a8ec699e85907` 在 Debug/Release/回放/当前实际安装中一致；安装主程序与代码dylib都精确等于最终 full Debug。

当前owned71设备保留前八文件baseline与当前八文件，外部十六原件逐一SHA相同。目录故障/复原仅改名，没有产品删除或重启代替重试。用户明确确认第一次直接下拉出现失败；代理取图时已回首页，所以失败截图明确来自后续同会话重开，不能冒称直接下拉帧。修复后同一失败画面保持；用户再次直接下拉并确认“横幅消失，仍有 2 条记录”，代理随即检查同页恢复画面，确认无横幅、两条完整记录及数值保持，未插入Retry/Done/重开/重启。六阶段十六原件及备份SHA相同；自动drag与公开控件事件均未被写成触摸通过。最终独立复审本轮mergeable、无阻塞；直接检查后仅清理owned71临时设备，外部十六原件及清理前摘要保持，其他设备/default不变，清理后再审计通过。最终审计与独立结论见证据根 `/Users/reece24/Library/Logs/FruitTreeScanner/refactor-iteration71-20261013/` 的 `validation-audit.json`、`Review71.md`；整体active/needs changes，没有Git交付。

## 1. 设计时证据与根因（2026-10-08）

- `Observation.swift` 已是无 pixel buffer 的同帧证据值，包含 FrameID、检测框、类别/置信度、时间、相机姿态/内参、图像尺寸、坐标约定、深度 confidence 来源、ROI/投影样本及拒绝原因。
- `ScanCoordinatorWorkflows.fusionEstimateObservationsSnapshot()` 合并稳定归档与当前检测，按 Observation.id 去重。稳定归档的每轨压缩与 360 帧 live window 是现有采集策略；不能将两者误说成整个最终输入已有统一磁盘字节预算。
- `ScanEvidenceSnapshot.freeze` 绑定真实结束输入与 source receipt，但只保留内存值。`ScanResearchArchiveCodec` 写结果和统计，不能还原 `ScanFusionYieldBuilder.Input`。
- 现有 `ScanObservationReplayTests` 明确使用 synthetic model/context，未证明实际设备观测已留存及可回放。
- **现有 PLY 不能充当原始数值输入的逐位备份。** PLY 按四位小数编码坐标；实际估算直接使用冻结的 Float 点数组。仅从旧 PLY 读取会量化输入，不能据此宣称重放了同一个输入。颜色及点顺序也必须保留。

## 2. 必须交付的边界

留存的输入必须来自实际 finalization 已接纳的 `ScanEvidenceSnapshot`，关联其 ScanID/PlanID/snapshot/sourceSHA、模型指纹、算法/源码身份和全部实际估算配置。由回放入口重建同一 Input，走现有 `ScanFusionYieldBuilder.build` 和仓储/研究导出核对。不得另写一套估产算法或只序列化结果冒充回放。

该包证明 **检测后的观测到融合/估产** 可回放。没有 RGB/原始模型张量时不宣称可重新执行 CoreML 检测；真机端到端精度仍按 ground truth 协议独立验收。黄金预期是算法回归基线，人工果数/重量是外部准确率证据，两者分别记录。

## 3. 最小实现方案

1. **Application 输入所有权。** 从 finalization 已冻结的 snapshot 构造具体 replay request，保留全部 `ScanFusionYieldBuilder.Input` 字段；按一次估算身份固定，取消/重试不重新读 Renderer、SettingsStore 或全局品种参数。先审查 `ScanAssessment → ScanRepository.commit → ScanResultExportService` 的真实提交链，再决定最小交接点，不增加平行生命周期 owner。
2. **Infrastructure 版本化编码。** 显式 DTO 和严格 reader；保存 schema、算法身份、模型/config/calibration 身份、资源预算及采集来源。观测保留拒绝、缺失值及 confidence provenance；不将 unavailable/copyFailed 修补成可靠深度。矩阵/坐标约定、Float 精度、顺序和 UUID 的往返须可证明。
3. **精确点输入。** 单独的有界二进制 Float32 点段按原顺序流式写 x/y/z/r/g/b 位模式，固定字节序与长度、count、SHA。不重新读四位小数 PLY、不转整云 String/Data、不修改现有 PLY 格式；同时绑定原 PLY sourceSHA，区别文件身份与算法输入身份。
4. **预算与失败语义。** point 数使用现有 analysis 上限；为观测数量、每条样本数、总字节及 reader 分配设置明确预算。超限/缺字段/未知必需版本/非完整输入必须明确标为不可回放或拒绝，不能静默截断后称完整黄金包。该预算不改变当前可靠估产输入、阈值或归档策略。是否使扫描提交失败须在事务设计中明确，不吞掉失败且不破坏已有完整记录。
5. **唯一事务入口。** 包的准备/发布/取消/恢复与现有仓储 draft、manifest 最后发布、revision/source identity 联动；先验证可选扩展及旧 schema 兼容，禁止脱离仓储独立发布第二套“完整扫描”。精确输入的全部 fallible work、大小/摘要核对发生在宣称包完整之前。删除、研究导出和取消清算须包含新 artifact，旧记录无包时明确 unavailable。
6. **本地脱敏导出。** 真实输入先本地留存，外发另需授权。导出省去 GPS、树名/标签、图像和设备个人身份，保留扫描局部坐标及必要的时间关系。任何时间/坐标重定基须证明投影、匹配和时间窗口结果不变；无法证明时保留本地原件并标注脱敏包不可作为逐位黄金基线。不得自动上传真实果园数据。

## 4. 验证与验收

| 风险 | 必需证据 |
|---|---|
| 保存的不是实际输入 | 真实生产 finalization 绑定 request 与 receipt；冻结后修改全局配置/缓存不改变包；读回全部字段逐项核对 |
| PLY 量化导致错误等价 | 使用无法由四位小数精确表达的坐标、边界颜色与顺序；二进制读回逐位相等，并证明旧 PLY 读回存在差异 |
| 低置信度被补全 | available/unavailable/copyFailed、拒绝深度、imageOnly/cloudOnly/零产原因往返；仅 fused 进入可靠产量 |
| 文件与身份 | 篡改、截断、错误 count、错 ScanID/PlanID/sourceSHA、未知版本、超限、取消/重试、发布碰撞、已提交记录保护 |
| 真实可回放 | LiDAR 设备实际采集包；至少一个正常与一个退化/零产场景；离线重建现有 builder 的结果、诊断与几何，对照明确容差和算法版本 |
| 资源 | 有界 reader/writer 与没有整云转换的源码证据；同设备实际内存/阶段计时独立留存，算术 payload 不计物理峰值 |

先建立现有实际输入不能由 result/PLY 完整还原的失败回归，再实现最小完整包。运行 storage/fusion/lifecycle、Domain、full/Release，保留旧方法与数据格式、比较告警、核对 source freeze/PBX，并独立只读复审。没有真实设备采集包和独立读回预期时，状态仍是实现通过/真实验收待补，不能关闭全目标。

## 5. 第 64 轮原实施提示词（历史）

```text
继续原 R0–R7 架构目标，读取 AGENTS.md、默认工作流、第63轮最终证据及本设计。
preflight保存原件，保护全部旧dirty；不提交、推送或合并。
检查真实finalization frozen snapshot→assessment→repository→exporter/manifest的提交、重试、删除与恢复链。
先用生产输入证明旧result/研究JSON缺少观测配置，旧四位小数PLY不能逐位还原实际Float估算点。
实现最小完整、版本化、可校验、有明确预算的真实观测回放包：保存实际Input、模型/算法/config身份，
精确点段按原Float32位模式与顺序分块写，观测保留矩阵、坐标约定、缺失值、拒绝与confidence来源。
让真实结束流程与现有仓储唯一事务消费它；严格声明完整/不可回放，超限不得静默截断或改估产输入。
先明确旧schema兼容及包失败、取消、迟到发布、重试、永久删除的契约，保持manifest最后发布与原档保护。
回放必须调用既有builder；合成测试用于实现验证，真实设备包和人工ground truth分别用于实际回放/准确率验收。
保留fused-only、低置信度否决、零产/扫描/置信度诊断、原采样与阈值；不扩大RGB/GPS收集或自动上传。
运行相关定向、Domain、full/Release、原方法树/告警/source freeze/PBX检查并独立复审。
完成后按剩余真机、最低系统和原生UI门禁逐项审计；证据不全时保持目标active。
```

## 6. 当前下一步与提示词

主要架构代码包已实现并完成上述模拟器验证。下一步先完成实物输入和验收，不按轮数、测试数或文件数换算百分比，也不增加缺少实际问题证据的重构。

截至 2026-10-14，用户暂不能提供真机采集，先完成本机验收。当前身份的合成回放成功链、中英文删除确认与取消、获准的合成单条删除及实际失败/关闭/修复/重试、英文窄屏词内换行、历史无缓存/有缓存 IO 失败与实际 Retry，以及第 71 轮历史下拉失败/同页恢复均已有对应层级的证据。第 71 轮首次下拉失败由用户直接确认、错误画面在同会话重开后取得；第二次同页恢复有用户确认和当前截图，不改写成自动手势全部通过。

第 72 轮正常全部删除与混合失败/Close 后再次失败已有原生证据。首次恢复的结果与时间/窗口映射不足，原观察保留且不计直接重试通过。用户随后在实际确认页明确允许本轮补验：重新准备相同三条合成记录，Late 控制仅改名暂存；实际清空失败后归还 Late、解除两处可逆故障，再从新截图确认的紧凑窗口直接点击 Try Again。37.905 秒前后记录包含目录修改和恢复截图时间，残留 6→2、页面仅 Late 完整记录且错误消失；18 外部原件及目录外控制摘要保持，没有重开历史或重启 App。此补验关闭按钮触发归因，最终独立复审限定本轮 mergeable，按条件清理 owned72 后再次审计通过，default/其他设备 ID 和18外部原件保持。Late 只加入磁盘而未证明进入当前缓存，它的存活仅证明重试未扩大到磁盘枚举；失败 ID 子集另由 controller 源码及精确单测证明。

随后逐项核对最低系统及剩余本机/物理门槛，不追加无依据架构包。合成记录与 owned 模拟器须明确标注，保护既有档案；永久删除按具体记录与动作确认。本机重新核对仅安装 iOS 27，App Debug/Release 的最低版本为 iOS 16；编译不能代替该系统实跑。当前 1196/59、Domain 45 源和 Release 为第 71 轮同源码证据复用，第 72 轮新执行的夹具回归为 1/1，不虚增全量执行次数。

第 73 轮进一步核实：当前 macOS 27.2/Xcode 27 的实际工具链、runtime 和配对设备 OS 都没有最低系统实跑条件；受测 Debug/Release 的实际 minos 16 保持。Apple [官方支持表](https://developer.apple.com/xcode/system-requirements) 显示 Xcode 27 模拟器起点为 iOS 17，不能只下载一个旧 runtime 就认定可验 iOS 16；旧工具链还须满足各自的宿主系统范围。下一步在兼容宿主/工具链和实际 iOS 16 环境执行仓库外第 73 轮 `MinimumOS16Acceptance.md`；当前仍待验，不变更最低版本声明或原生 UI target 取得通过。

```text
继续原 R0–R7 目标的验收收尾，读取第64轮最终记录及仓库外原始结果。
保护全部现有dirty与扫描数据，先核对当前源码/算法身份和受测构建；不把旧构建证据作为新源码通过。
第72轮获准的直接Try Again补验已完成，先核对最终审计/复审/owned清理结果，不重复永久删除。
第73轮已核实当前Xcode27的模拟器支持最低17；按MinimumOS16Acceptance.md取得兼容环境后，
核对受测源码/模型身份、实际iOS16 runtime/device并完成App16启动/操作，不拿部署声明或27结果代替。
用户能采集后，在LiDAR设备取得正常与退化/零产输入，使用实际冻结包读回与原builder黄金比较，
独立记录人工果数/重量、条件、模型和配置；完成同设备30/60/120秒采集、阶段耗时及物理峰值内存。
没有同设备改前基线时只报告测量值，不宣称资源收益。
永久删除按具体测试记录和动作确认执行。存在缺陷时先复现根因再小范围修复、验证、复审。
最后按用户授权整理对应提交并完成远程交付；设备数据、最低系统或交付缺证据时不宣告整体完成。
```

当前整体结论：**needs changes**；第 72 轮限定范围 **mergeable**，原生补验、最终复审和 owned 清理已完成。第 73 轮已明确最低系统的环境缺口；剩余为兼容环境中的 iOS 16 实跑、实物验收与 Git 交付。
