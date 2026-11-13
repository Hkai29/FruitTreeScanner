# 批量导出应用编排与临时文件所有权设计

2026-10-08，第 59 轮后续设计。**第 60 轮已实施并验证，本轮 mergeable；整体 needs changes / active**。实际结果见 [第六十轮执行记录](REFACTOR_ITERATIONS_2026-09-27.md#第六十轮批量导出应用编排文件所有权与验证就绪门禁)。对应原蓝图的批量导出 Application 入口与 R6/R7 责任边界。Plan 地块/标签、Dashboard 启动、真实观测及物理资源验收继续开放。

## 1. 真实调用链与根因

```text
DashboardView → BatchExportView
  → makeExportRequestSnapshot（已提交记录选择、格式、选项、当前地块名称）
  → performExport 的 SwiftUI @State Task / generation
  → BatchExportService.export → utility detached worker
  → ScanRepository.validateBatchRecord（写前/写后核对）
  → CSV / Excel XML / research JSON writer
  → 页面检查取消、generation、请求快照 → 分享 URL
  → clear / disappear / 迟到完成 → managed 临时文件清理
```

当前 `Views/BatchExportView+Actions.swift` 直接拥有任务创建/取消、generation、await 后发布判断和临时文件删除；`BatchExportView` 同时持有对应 `@State`。已有 service 负责有界写入、当前记录验证和受管目录，页面仍承担跨步骤业务所有权。根因是长任务和文件副作用与 UI 生命周期耦合。相同页面身份下，SwiftUI 的 `@State` 会跨 body 重建保留；不能把 View 值重建直接当作任务状态丢失，也未据此复现数据丢失。

地块/标签核查另发现：Start/Quick/Rescan 的 `ScanLaunchRequest` 携带分类，Dashboard 在激活时写入独立 TagStore，但 ScanView/ScanPlanFactory 未把分类传入 ScanPlan。后续需明确冻结的扫描分类与可编辑树分类之间的消费契约；不能仅添加无人消费的 Plan 字段就将该项关闭。本轮后续优先处理已有实际长任务和文件副作用的应用编排。

## 2. 最小完整边界

| 位置 | 职责 |
|---|---|
| Application | 一个具体 `BatchExportWorkflow`，主 actor 拥有当前 task、attempt/generation、忙碌状态、已完成 URL 和失败事实；不依赖 SwiftUI/UIViewController |
| Application 长任务边界 | 具体 operations 值：异步执行现有导出服务、清理受管临时产物；AppDependencies 装配生产操作，可用受控 continuation 测试迟到完成 |
| UI 请求适配 | 保留原 `BatchExportRequestSnapshot` 构造、选择/格式/选项和地块名称解析；向 workflow 提交冻结请求，并提供原同步请求等值复核 |
| UI 展示 | 从 workflow 投影忙碌/文件/失败；保留分享 sheet、Activity 完成反馈、原错误分类与本地化说明。删除迁移后重复的 task/generation/结果状态 |
| 既有 service / repository / writers | 保留 utility worker、取消传播、当前 revision/source 校验、流式格式、受管目录和原输出字节；不混入 writer 重写或存档 schema 迁移 |

操作接口只用于真实异步服务/文件清理边界，不为普通 helper 新建 protocol。页面必须实际使用 workflow；不保留第二条生产 performExport 路线，也不将长期副作用换个名字留在 View 的 Task 内。

workflow 按页面身份稳定拥有，例如以 `@StateObject` 管理，不能在 body 重建时重新创建。AppDependencies 装配生产 operations，Dashboard 打开批量导出页时实际传入；保留既有 store/tagStore 初始化入口，保证原宿主测试和调用方兼容。

服务中的 `shouldKeepFile = true` 和返回结果构成临时文件所有权交接：服务清理尚未交接的失败/取消产物，workflow 接管成功返回的 URL。任务取消、页面消失或页面 owner 释放后仍可能迟到返回；接收结果的任务必须通过已捕获的受管清理操作删除这份 URL，不能因 `weak self == nil` 直接返回而泄漏文件。不得用强引用形成永久任务环来延长页面寿命。

## 3. 必须保持的完整行为

| 场景 | 现有契约 |
|---|---|
| 请求 | 只包含 complete 且被选择的记录，保持顺序；记录、格式、全部选项及 plotNameByTreeID 纳入等值快照 |
| 启动 | 空请求不启动；替换任务先取消旧任务并推进 generation；已导出文件按原流程清除 |
| 成功发布 | await 后依次拒绝 Task 已取消、旧 generation、当前请求不等值；只有服务完成且上述检查通过才发布 URL 并打开分享 |
| 失败发布 | CancellationError 不显示失败；其他错误保留原取消/generation 检查与分类。原失败分支没有额外请求等值检查，纯迁移不能悄悄改变它 |
| defer | 只有当前 generation 的任务能清空自己的 handle 和忙碌状态；旧完成/失败不能覆盖新任务 |
| 取消/离开 | 推进失效身份，取消任务；页面离开同时清理已完成的临时文件；迟到返回的临时结果不能发布或影响新任务 |
| 来源变化 | 历史记录、地块/assignment 变化按原回调取消和失效；选择/选项交互、重试、全选/清空规则保持 |
| 文件 | 只通过现有受管清理入口删除临时导出，不删除源 PLY、metadata/manifest、外部或其它 session 文件；实际文件完成后才验证内容 |
| 分享 | 取消分享不报失败；只有失败活动的标准化 URL 与当前导出 URL 相等才显示原分享错误，迟到旧活动不影响新导出 |
| 数据 | writer/格式、完整性校验、未知研究字段、canonical 校准字节、独立标签/设置存储及 fused-only 估产保持 |

冻结请求的复核必须在主 actor 上同步完成，继续覆盖所有实际可变输入，不能以只检查 selected IDs 替代完整等值。所有 UI 改动只服务所有权迁移，保留现有布局、文案、accessibility IDs 和失败恢复。检查实际 SwiftUI 发布时机；全 Passed 不能掩盖非法视图更新告警。

## 4. 证据与实施顺序

1. 读取默认工作流和第 59 轮最终证据，preflight 保存原件与 dirty 摘要。真实检查上述页面/service/repository/临时目录链路。
2. 复用现有 `BatchExportServiceTests`、`BatchExportShareLifecycleTests`、`BatchExportFailureFeedbackTests` 的原输出与原生宿主基线；这些类实际分散在 BatchExportServiceTests.swift 与 DashboardSummaryTests.swift，不按类名臆造文件。
3. 补充缺失契约再运行原实现基线；以明确状态/服务返回为完成边界，检查文件内容及原档未变，不按临时文件出现或固定延时判断成功。
4. 建立 workflow/生产 operations 装配并接通 Dashboard 和页面，按页面身份稳定持有 workflow，保留旧 store/tagStore 初始化兼容入口。完整迁移 task/generation/结果所有权；保留原请求构造和成功/失败判断差异。移除失去消费者的 UI 状态和旧实现。
5. 用受控异步操作验证 A 取消后 B 启动、A 迟到成功/失败、旧 defer、请求变更、离开/owner 释放后的迟到 URL 清理、取消后重试及分享晚回调。完成/清理均等真实边界，断言新任务和源档不受影响；不以重试到通过掩盖竞争。
6. 运行 storage/ui 相关定向、full/Release、完整 Domain 门禁及可行 iOS 原生交互走查。核对原方法集合、实际 warnings、格式与存档回放、最后受测摘要及旧 dirty 保护。
7. 独立只读复审任务所有权、取消/发布/文件清理边界、页面消失与错误反馈。阻塞项修复后重跑，记录剩余物理/真实观测及 Plan 分类缺口。

若迁移中证实新的行为缺陷，先保存失败回归与原始证据，再在同一所有权问题内修复；不通过减少快照校验、取消检查或临时目录保护获得通过。

## 5. 可直接使用的第 60 轮提示词

```text
继续第60轮，读取AGENTS.md、默认工作流、本设计、第59轮记录和原R0–R7完成核验。
preflight核对最终受测源码/方法树并保存原件、保护旧dirty；不提交推送合并。
追踪BatchExportView→冻结请求→service utility worker→仓储写前/写后校验→writer→分享/清理链路。
先运行原实现的服务、分享生命周期、错误恢复基线，缺失契约先固定原输出，不臆造测试类所在文件。
把批量导出的完整长任务/generation/忙碌/结果文件/失败事实所有权交给具体Application workflow。
由AppDependencies装配现有异步导出和受管清理操作，Dashboard实际传入页面，保留旧store/tagStore初始化兼容入口。
按页面身份稳定拥有workflow，body重建不能新建；只在真实长任务/文件边界注入，不加空协议。
页面只构造原冻结请求、同步复核完整请求等值并投影状态/分享/错误说明；实际调用workflow并删除重复旧路线。
保留成功的取消+generation+请求等值检查、失败原有取消/generation检查及CancellationError静默语义。
保留旧defer仅收尾当前任务、来源变化失效、离开清理、重试/选择/选项/地块映射和分享URL匹配。
明确service成功返回URL时的所有权交接，页面离开或owner释放后的迟到URL也须清理，weak self为nil不能直接漏掉文件。
用受控完成验证A取消/B启动/A迟到成功失败/旧defer/请求变化/离开/owner释放/重试，源档和新任务必须保持。
文件必须服务完成后验证，不用固定等待/文件出现/反复重试代替真实完成边界。
保留service/writer/repository格式、校验、受管目录与取消传播，不删除源档或外部文件。
保持现有UI布局、本地化、accessibility与独立小型存储，不扩大到Plan分类或Dashboard重写。
运行相关定向、full/Release、Domain门禁和可行iOS交互，核对原方法、runtimeWarnings及最终摘要。
独立只读复审后记录实际证据与下一轮候选；Plan分类/真实观测/物理资源未证明项继续开放，整体active。
```
