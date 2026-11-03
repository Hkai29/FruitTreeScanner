# 扫描分类快照的完整消费设计

第 61 轮已实施、验证和独立复审，本轮 mergeable。对应原蓝图「开始扫描时将果园/标签所需身份和值写入 ScanPlan」；整体目标继续 active，最新证据与后续范围见执行记录第 61 轮。

## 实际缺口

Start / Quick / Rescan 提交的 `ScanLaunchRequest` 已携带 plotId/tagIds。Dashboard 激活时将它们写入独立 TagStore；传给 ScanView 的参数及其两条 makePlan 调用没有分类。ScanPlanFactory、ScanPlan、ScanFinalizationPersistence 构造的 ScanAssessment 和 ExportRequest 均没有该值，因此已提交存档不能说明本次扫描使用了哪些分类。

这是原架构要求尚未贯通的消费链，不能只增字段或只写 TagStore 便判完成。独立 TagStore 的树分类允许后续编辑；历史扫描的冻结分类属于该次扫描。需要同时保留两者的语义。

## 最小完整改动

1. 建立一个 Domain 不可变 Sendable / Equatable 分类快照，明确地块和标签的 ID、当时名称及确定顺序。无分类与旧存档缺失必须可区分，不能用当前 TagStore 回填历史身份。
2. Dashboard 从根 TagStore 和已提交 launch 选择构造一次快照，传给 ScanView；开始和中断后新扫描两条实际 makePlan 路线均接通。直接初始化兼容入口保持默认的明确空分类，不增加 `.shared` 读取。冻结后改名/删标签/更改树 assignment 不改变活动 Plan。
3. 结束流程只使用 receipt 对应 Plan 的分类，经 ScanAssessment / ExportRequest 写入可选版本化 metadata 字段。仓储 typed DTO / 已验证记录读取真实字段，研究 JSON 导出实际保留和消费该快照。校准重存必须保留原分类，而非覆盖为当前树分类。
4. 不改变现有批量导出的「当前 TagStore 地块分组」行为；新存档分类作为独立研究字段。旧 CSV / legacy JSON / manifest 档案按原规则读取，不伪造名称、ID、revision、来源或校准上下文。

捕获时点定为 Dashboard 激活扫描的主 actor 同步动作：沿用 `createOrUpdateAssignment` 对现存 ID 的过滤和标签去重顺序，从该次实际接受的 assignment 与同一个根目录读取名称一次，将快照放进同一个 activeScanRequest 值并保留原 request.id。不能在 SwiftUI cover/body 重建时重新查询目录。Quick/Rescan 与 Start 共用该入口；中断后新计划沿用该次启动快照，扫描下一棵树则重新捕获。直接 ScanView / makePlan 兼容入口显式默认空分类，不能借默认值读 `.shared`。名称保持捕获时原值，不参与算法阈值或校准 canonical identity。

存档字段需要区分：旧字段缺失、已知版本的显式空分类、有效分类，以及存在但非法/不支持的字段。后两者的读取失败或兼容报告不能静默变成“本次未分类”。实施前确认 typed reader 的错误传播与 research raw 字段保留，覆盖解析和事务失败路径；不通过提升整个 manifest 版本来绕过原 1–3 兼容。

只给真实持久化消费链加必要值；不引入分类 service/protocol，不将小型 TagStore 合并进扫描事务仓储。未知研究字段、canonical 校准字节及其身份输入原样保护。

## 验收与风险

- 先 preflight、保存原件与旧 dirty，复核第 60 轮最终受测摘要；先为当前 Start/Quick/Rescan 和存档路径运行基线。
- 定向证明分类顺序/无效选择处理；活动 Plan 不随后续 store 编辑变化；两个 makePlan 入口都传递；结束流程拒绝异 Plan receipt；冻结分类真实写入并经仓储/研究 JSON 读回。
- 覆盖旧档缺失、不合法新增字段策略、未知字段保留、校准重存和保存失败/重试。只在完整事务完成后比较字节/摘要；manifest 最后发布、source/revision/hash 校验及回滚保护不变。
- 运行生命周期/存储/启动相关定向、完整 Domain、full、unsigned Release；核对旧方法集合、warnings 和最后受测摘要。独立复审后记录决策。
- 真实观测持久回放、Dashboard 聚合、Renderer 文件编排/兼容入口和物理验收继续开放，不以本项通过代替整体完成。

## 第 61 轮提示词

```text
继续第61轮，读取AGENTS.md、默认改进工作流、本设计、原R0–R7蓝图及第60轮真实交付证据。
先preflight保存原件、核对最终受测SHA/方法树、保护全部旧dirty；不提交推送合并。
追踪Start/Quick/Rescan→ScanLaunchRequest→Dashboard→ScanView两条makePlan→ScanPlan
→对应receipt的结束流程→ScanAssessment/ExportRequest→事务metadata→typed读取/研究JSON。
建立明确有序的不可变扫描分类快照，实际接通整个消费链，不只增加无人消费的Plan字段。
区分本次扫描冻结分类、可编辑树TagStore和旧存档字段缺失；不得用当前目录回填历史身份。
活动Plan不能受后续分类改名/删除/assignment编辑影响；校准重存保留原扫描分类。
保持既有当前地块分组、独立小型存储、legacy格式、未知研究字段、canonical校准字节、
source/revision/hash核对、manifest最后发布、取消/重试及仅fused可靠估产。
基线后聚焦实施，覆盖实际两个makePlan入口、生产结束/仓储/研究导出、旧档和失败边界。
运行相关定向、完整Domain、full/Release，检查原方法、runtimeWarnings和最终源码冻结。
独立只读复审并记录实际证据/限制，提出下一项原范围候选；整体目标保持active直到逐项证明。
```
