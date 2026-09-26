# 第二轮深查、修复与 Review

## 已修复

保存失败路径存在状态与证据消费不一致：`makeYieldEstimationSnapshot` 清空检测缓存后，结果保存失败仍处于 finishing，而 canExportScan 只允许 recording/userPaused。用户无法按提示重试，简单重跑估算还会消费空证据。

- finishing 状态允许重试；点云导出失败走导出路径，已有估算结果只走保存路径。
- 估算结果在保存前缓存，保存失败不进入成功结果面板，提示点击完成重试。
- 异步导出与保存回调验证 scanIdentity 和 finishing，避免旧扫描回调改变新扫描的结果/完成状态。
- 开始新扫描时清空界面结果及文件名，防止跨扫描复用。
- Review 保留了原暂停面板条件，没有把含“继续扫描”按钮的面板暴露给 finishing；重试使用原底部完成按钮。

保留 fused 可靠证据限制、估算快照单次消费、导出事务写入方式，以及前一轮全部修改。未改动阈值、点云/模型算法。未提交、未推送。

## 验证证据

- 完整 iOS 27 模拟器测试：485 项、0 失败。新增重试分流及中断/完成/取消状态拒绝检查。
- 扩展实际导出故障注入：JSON 写入抛出 fileWriteNoPermission 时不产生完成标记；恢复后重用原请求保存成功，再保存一次内容不变。
- Release generic iOS 未签名构建成功；git diff --check 通过。
- 日志：`/tmp/fts-round2-final.log`、`/tmp/fts-round2-release.log`。
- xcresult：`/tmp/fts-repair-build/Logs/Test/Test-FruitTreeScanner-2026.09.05_23-06-30-+0800.xcresult`。

以上测试覆盖重试决策及文件事务，尚未进行真实 SwiftUI 界面失败注入/点击操作，也未测试真机 LiDAR。因此不将这些单元测试描述为完整 UI 或真机验收。

## Review 剩余问题

1. P1：`ScanCoordinatorWorkflows.swift:91-135` 历史证据仍在 MainActor 中重复稳定匹配。此次 16 目标/120 帧，1920 条活动证据，最后一次 append 105.2 ms（含 await 调度）。尚未改动；不能将后台迁移与线程安全等同，需要独立处理算法、所有权及代际校验。
2. 保存重试缓存只在当前页面内存中保留；退出页面/进程终止后的估算恢复没有在本轮实现。
3. 扫描中断、停止时在途检测及真实 LiDAR 精度仍需进一步检查与设备验收。

整体判断：**needs changes**。本轮关闭保存重试的代码路径缺陷，不代表整个 App 已完成发布验收。
