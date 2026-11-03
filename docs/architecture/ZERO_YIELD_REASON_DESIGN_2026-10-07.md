# 结构化零产原因与原格式适配设计

2026-10-07，第 57 轮后续设计。**第 58 轮已实施并验证**；实际证据与剩余项见 [第 58 轮记录](REFACTOR_ITERATIONS_2026-09-27.md#第五十八轮结构化零产原因与旧文本适配)。本文延续原 R4/R7 的结构化诊断要求；不表示真实观测、资源测量、应用协作或物理验收已完成。

## 1. 已有基础与真实缺口

第 57 轮已分离纯数值估产评估与现有结果装配。剩余零产规则位于 `Core/ScanDiagnosticsBuilder.zeroYieldReasons`：模型、深度、点数、检测、候选和融合事实的判断直接生成 `L10n.Diagnostics` 字符串。非成熟未标定季节则在 composer 中直接生成专用中文原因。

实际消费者：

```text
YieldResultComposer → ScanDiagnosticsBuilder.zeroYieldReasons
  → ScanYieldDiagnostics.zeroYieldReasons: [String]
  → ResultPresentationModels / ResultDiagnosticsSection / DiagnosticRecommendation
  → ScanResultExportService → ScanArchiveDTO / ScanResearchArchiveCodec
```

这些字符串已经参与旧页面、归档、研究 JSON 和建议匹配。下一轮将事实判断结构化，再在现有适配处生成原字符串；现有存储 schema 和展示消费者保持兼容。

## 2. 责任边界

| 位置 | 责任 |
|---|---|
| Domain | 具体 `ZeroYieldReason` 值和纯分类策略；接收已有纯值诊断/最小点数，返回有序原因；不引用 L10n、日志、缓冲、模型或文件系统 |
| Core 适配 | 保留 `ScanDiagnosticsBuilder.zeroYieldReasons` / `zeroYieldNote` 签名，映射为原字符串，保留文本相关的旧抑制语义 |
| 未标定季节 | 从明确的领域原因生成原专用说明，继续在聚类/融合前早返回，保留该分支的字段缺省 |
| UI / 存档 / 导出 | 继续使用原 `[String]`、原顺序/说明和既有 schema；本轮不迁移持久格式或重写页面 |

使用具体枚举和函数，不增加空协议、闭包注入或第二套诊断状态。枚举可包含动态深度失败说明的关联值；不能通过重新解析已有中文来决定领域原因。

## 3. 必须保留的契约

- 原判断顺序：模型 → 深度不可用 → 动态深度失败 → 点数不足 → 未处理帧 → 无检测 → 置信度过滤 → 未映射标签 → 无候选 → 融合失败 → cloudOnly 保守拒绝。
- 原条件和边界，包括 `imageModelStatus != "CoreML"`、严格小于最小点数、置信度过滤与未映射可同时出现，以及 fusionFailed 的 image/candidate/fused 三项条件。
- 动态深度失败字符串不删改、不合并，也不按本地化文本推测另一种故障。
- **原文本抑制行为：** cloudOnly 原逻辑使用 `Array<String>.contains(String)`，检查前序原因数组是否有元素与 `L10n.Diagnostics.noDetections` 完全相等；不是字符串子串搜索。动态深度失败文本恰好相等时也会抑制 cloudOnly，仅含该子串、带前后缀时不抑制。Domain 按 cloudOnly 模式且 fused 为零产出候选原因，Core 对已映射的前序数组执行这项兼容抑制；不能改为只检查 noDetections 枚举、在两层重复分类或反向解析文字。
- 动态原因与正式 noDetections 同时产生时，即便文本相等也保留两个原始项及顺序。适配器不使用 Set 去重，不 trim、不改译文；UI 首项、建议精确键和旧存档继续获得原数组。
- 保留原说明的前缀 `⚠️ `、分隔符 `；`、空数组 fallback 与顺序。现有建议仍按原字符串工作。
- 未标定季节原因仍为原专用中文，不借本轮增加翻译或成熟期错误；manual_review/crown_untrained、N/A、零计数及未填的 cluster/校准字段保持。
- 仅 fused 的权限、零权重分支、低置信度/失效深度否决、两次取整、校准身份和全部数值均保持。
- 保留结果诊断、旧归档/研究 JSON 未知字段、原 source/revision 摘要和 manifest 最后发布。

## 4. 实施与证据

1. 按默认流程 preflight，核对第 57 轮最终受测源码摘要、原始方法树和所有旧 dirty。
2. 在原实现先建立通过基线：完整原因顺序/组合、点数阈值两侧、动态原因与 noDetections 完全相等/仅含子串但不相等/与正式原因重复三例、空原因 fallback、未标定季节固定缺省。
3. 提取纯原因枚举和分类器，保留旧 facade 并接入两个实际生产分支；不添加未使用的替代路径。
4. 结构化 Domain 原因与旧字符串输出分别断言；既有固定预期不改成调用被测策略生成，不能用旧新两个实现互相比较代替固定预期。
5. 新源实际唯一进入 App Sources，完整 Domain 独立编译不借入 Core，不排除新文件或修改门槛。
6. 定向覆盖 ScanDiagnosticsBuilderTests、DiagnosticRecommendationTests、builder 全分支、完整观测回放和相关估产测试；full/Release 核对实际方法树、校准 canonical bytes、存档/批量回放、告警和最后源码摘要。
7. 独立只读复审顺序、条件、文本兼容、早返回和字段缺省，修复阻塞后重跑受影响关卡。记录下一轮有证据的原范围候选。

这一步的收益是领域原因可直接验证、旧格式适配职责明确。它不会提供真实传感器精度或性能数据。点云编排、Plan plot/tag、Dashboard/批量应用协作、真实观测包、同设备性能与物理验收继续保留。

## 5. 可直接使用的第 58 轮提示词

```text
继续第58轮，读取AGENTS.md、默认工作流、本设计、第57轮记录及原R0–R7完成核验。
preflight保护旧dirty，核对最终受测源码和原始方法树；不提交推送合并。
追踪composer→ScanDiagnosticsBuilder→结果页面/建议→归档与研究导出的真实调用链。
先固定原因顺序、组合、阈值、动态文本碰撞、空fallback及未标定季节的原输出基线。
将零产事实判断提取为Domain具体原因枚举和纯策略，实际接入成熟零产与未标定早返回。
保留原facade签名、[String]诊断/schema/说明/顺序/未知字段及UI建议兼容。
Domain产出cloudOnly候选，Core对前序原因数组按元素等值contains抑制，不作子串搜索或两层重复分类。
固定动态文本完全相等、仅含子串但不相等、与正式原因重复三例；不trim、不去重、不改译文。
Domain不含L10n、日志、模型查询或平台缓冲；不反向解析中文，不加空接口或第二套状态。
仅fused、零权重、深度否决、两次取整、校准nil身份及各分支缺省值均保持。
检查App Sources唯一和完整Domain门禁，执行定向、full/Release及独立只读复审。
核对方法树、归档/批量回放、canonical校准字节、全部告警、最终源码和旧dirty保护。
记录实际证据与下一轮候选；整体目标继续active，真实观测/物理资源等未证明项继续开放。
```
