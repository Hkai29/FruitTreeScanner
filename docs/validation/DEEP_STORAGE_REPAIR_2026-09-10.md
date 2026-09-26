# 保存与恢复链路深度排查及修复

决定：**mergeable**（本轮保存链路修复及模拟器验证范围）。确认并修复 4 项问题，新增 8 个回归测试。最终完整 iOS 模拟器测试 **524 项通过、0 失败、0 跳过**；generic iOS Release 未签名构建成功；`git diff --check` 通过。

本轮接续[上一轮修复](/Users/reece24/FruitTreeScanner/docs/validation/SELF_REVIEW_REPAIR_2026-09-09.md)，沿扫描完成、异步估算、保存重试、文件发布、历史重读和批量研究导出追踪状态边界。实际代码修改收敛在保存服务、伴随文件读取器和测试三个文件，没有扩展为算法或界面重写。

## 按严重程度排列的发现与修复

### P1：恢复旧文件再次失败时，最后一份有效备份被删除

旧流程先复制旧 JSON、CSV 和完成标记到 staging，再发布新文件。发布异常时，回滚中的删除和复制错误被 `try?` 吞掉；外层 `defer` 无条件删除 staging。同时，即使旧 JSON 没恢复成功，旧完成标记也仍可能被复制回去。

故障注入复现：新 JSON 发布后让 CSV 发布失败，再让旧 JSON 的恢复复制失败。修复前剩余 staging 数为 **0**，旧完成标记却重新出现；此时旧 JSON 的有效备份已被清理。这个测试实际写入模拟器临时文件，并在文件操作边界注入错误。

[发布与回滚流程](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanResultExportService.swift:351)现按以下顺序处理：先撤下完成标记，逐个恢复数据文件，全部恢复成功后才恢复旧完成标记；若任一步恢复失败，保留本次 staging，并通过 `RecoveryRequiredError` 返回恢复目录、原发布错误和失败文件名。普通成功或完整回滚仍清理本次 staging。

回归还逐个注入 JSON、CSV、完成标记的发布失败，包括关闭 CSV 导出时先删除旧 CSV 的情形，验证旧事务的每个文件都恢复为原字节，且仍可读取。

### P1：版本号未变的损坏内容仍被当作完整结果

旧读取器只验证 JSON、CSV 与完成标记中的版本号一致；清单还可声明额外的不存在文件而不被拒绝。旧保存重试同样依赖版本标签，未核对文件内容是否等于当前请求。

初次复现中，分别修改 JSON 备注、CSV 树编号、清单必需文件列表后，读取器三次都返回 **complete**。摘要数量未变时，损坏的详细证据还可能进入批量研究导出。

修复后：

- [保存服务](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanResultExportService.swift:89)生成 v2 完成标记，记录每个必需伴随文件的 SHA-256 摘要。
- [读取器](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/PLYCompanionResultReader.swift:66)核对必需文件集合、重复项、版本和摘要；校验使用已读取的同一份数据，后续解析不会再次读取另一版本的 CSV。内容不符返回 invalid，不提供可靠摘要或校准基线。
- [保存重试](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanResultExportService.swift:334)逐字节比较预期 JSON、CSV 和完成标记。损坏文件会重新发布；JSON-only 保存也会清理同名过期 CSV。
- 回归覆盖摘要字段保持不变、详细证据被改动时，实际批量研究导出拒绝该记录；重新保存修复文件后可正常导出。

### P2：遗留 staging 目录使相同请求无法再次保存

旧 staging 名称由扫描名及内容版本固定生成。异常退出遗留该目录后，对相同文件和结果再次保存会使用同一路径。

复现预置含旧 JSON 备份的遗留目录，旧代码抛出 **NSCocoaErrorDomain Code=516 / File exists**，后续发布未执行。

[临时发布目录](/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/ScanResultExportService.swift:116)现使用每次尝试独有的 UUID，名称长度也不随扫描文件名增长。测试确认新结果成功写入，遗留目录中的旧备份保持原字节；不会为了重试而覆盖或删除此前的恢复副本。

### P2：合法的换行备注导致每次重试都重新发布文件

CSV 写入器正确引用包含换行的字段，但旧幂等检查按物理换行拆分，只检查第二行末尾的版本号。备注有换行时，它把完整 CSV 判成未完成事务。

复现相同请求保存两次：本应只发布第一次的三个文件，实际发布次数由 **3 增至 6**。现在完整比较预期 CSV 字节，保留引号、逗号和多行字段；回归确认两次调用后发布次数仍为 **3**。

## 兼容性和明确边界

- `_result.json` 和 CSV 的现有字段及数据口径保留；升级为 v2 的是 `_complete.json` 完成标记。
- 当前读取器继续接受已有 v1 事务和无事务的旧 JSON/CSV。v1 没有内容摘要，只能沿用其旧验证能力；再次执行保存时升级为 v2。没有批量改写用户历史文件。
- 仅识别 v1 完成标记的旧版 App 不识别 v2。新文件应由更新后的 App 读取；回归验证的是当前版本对旧文件的兼容。
- 摘要覆盖 JSON 和声明的 CSV，不覆盖 PLY 点云正文。它用于发现内容不一致，不改变融合、估产或校准算法。
- 回滚失败保留恢复副本，后续成功重试也不自动删除之前的副本。本轮未增加自动恢复旧备份的界面。
- 保留只有 `.fused` 参与可靠估产的规则、深度/置信度门槛、零产量及扫描诊断、此前的会话恢复和异步代次保护。

## 验证证据

| 验证 | 结果 |
| --- | --- |
| 修复前故障复现 | 4 个测试方法均失败，7 处失败记录，其中 1 处为捕获到的目录冲突错误 |
| 修复后导出、点云解析、文件模型回归 | 202 项通过，0 失败、0 跳过 |
| 完整 iOS 模拟器 XCTest | 524 项通过，0 失败、0 跳过；XCTest 约 13.31 秒，退出码 0 |
| generic iOS Release 未签名构建 | BUILD SUCCEEDED，退出码 0 |
| 差异检查 | git diff --check 通过 |

新增测试位于 [BatchExportServiceTests.swift:15](/Users/reece24/FruitTreeScanner/FruitTreeScannerTests/BatchExportServiceTests.swift:15)，覆盖内容损坏与重试修复、多行 CSV 幂等、遗留目录、回滚失败备份保留、v1/v2 兼容与缺失摘要、各发布阶段失败、JSON-only 过期 CSV，以及研究导出详细证据完整性。

环境：仓库指定 Xcode beta，Xcode 27.0 / Build 27A5194q；模拟器 `FruitTreeScanner-iPhone-17-iOS27`，ID `C722B4F0-E16F-4C14-84A1-8C796DB0FE11`。

本机首次构建遇到 Metal 工具链未就绪，随后 `xcrun metal --version` 确认可执行。另一轮停在 `ibtool` 的共享池锁，进程采样显示 `IBCLIServerRegistryCopyDequeuedPipes → __ulock_wait`。本轮停止自己启动的挂起构建，使用命令级 `IBToolNeverDeque=YES` 后完成真实编译和测试；没有修改全局 Xcode 选择或项目配置来绕过检查。

最终命令（该临时目录完成后已清理）：

```sh
IBToolNeverDeque=YES \
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -derivedDataPath /private/tmp/fts-deep-repair-20260910.vvc2203w/DerivedData \
  -resultBundlePath /private/tmp/fts-deep-repair-20260910.vvc2203w/full.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO

IBToolNeverDeque=YES \
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild build -project FruitTreeScanner.xcodeproj -scheme FruitTreeScanner \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/fts-deep-repair-20260910.vvc2203w/DerivedData \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

既有测试目标 iOS 最低版本与 XCTest 库版本的链接警告、未使用变量警告仍存在。本轮没有把这些警告或模拟器 CoreML 后端日志当作测试结果；以实际 XCTest 和结果包摘要为准。

## 工作区与清理

- 分支 `codex/fix-outdoor-canopy-depth`，HEAD `c3ca0b2685b862717456120a26a34a937877c0df` 未变。没有提交、推送、暂存、切换分支或回退其他修改。
- 修复开始时保存了 275 个源文件及工程文件的轻量基线。本轮只修改其中 3 个，其余 272 个逐字节不变；另新增本报告。
- 基线已有差异 SHA-256：`cf9be18df32d94ec64287911343661ac45176c79e68e4a7f4893931728d635f3`。
- 仅本轮相对基线补丁 SHA-256：`ab514a35f669c01346db6ecc6f15565fbeb24ec7b87008d254c6130b2244b60a`。
- 一个临时 DerivedData 目录；构建、日志、结果包和基线合计清理前约 885 MiB，结束后删除并核验不存在。测试故障文件均在各自临时目录内清理，没有删除用户扫描记录、旧构建目录或历史恢复副本。未下载模型或数据集，模拟器最终恢复为关闭状态。

剩余限制：验证使用真实文件操作与可控故障注入，没有执行实体设备断电、进程被系统强制终止或真实磁盘耗尽实验；也没有进行真机按钮端到端操作。本轮没有重新测量 LiDAR 扫描精度。

最终决定：**mergeable**（本轮修复范围）。
