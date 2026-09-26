# 扫描交互状态审查

> 以下为修复前证据；当前状态见 [INTERACTION_REPAIR_2026-09-06.md](INTERACTION_REPAIR_2026-09-06.md)。

## P1：中断重扫遗漏旧结果缓存，重试可能保存旧扫描结果

ScanView+Actions.swift 的 startRecording 会清空 yieldResult/savedFilename/showResult，而 restartAfterInterruption:167 直接调用 coordinator.startRecording，没有这些清理。前轮修复只覆盖普通开始入口，未覆盖此入口。

可疑路径已追踪到具体调用：旧扫描估算成功但保存失败，保留缓存 → 系统中断 → 重新扫描 → 新扫描点云导出失败 → finishing 中仍有旧 yieldResult 和旧文件名 → 再次完成进入 persistResult。saveEstimatedResult 捕获的是当前 scanIdentity，缓存本身没有所属扫描身份，因此该检查不能识别旧数据，可能用旧结果结束新扫描。

边界测试确认：生命周期换成新 scanIdentity 后，retryAction 对保留的旧缓存仍返回 persistResult。此测试不等于真实 SwiftUI 端到端复现；路径中的缓存遗漏与按钮调用均由当前源码确认。

修复应统一新扫描初始化入口，并让待保存结果携带所属 scanIdentity；不能只再增加一处字段清理。

## P2：覆盖完成提示的状态跨扫描残留

ScanView+Actions.swift:57-59 将 hasShownCoverageComplete 置 true，当前源码没有任何新扫描重置路径。重复扫描仍复用同一 ScanView 时，第二轮达到 85% 也不会再触发提示。showCoverageComplete 的延时关闭也没有扫描身份校验。

这是静态状态写入/读取检查，尚未进行真实界面多轮扫描验收。应与新扫描结果、通知、测量等临时状态一起定义生命周期归属。

## P2 交互风险：重新录制直接丢弃未保存扫描

底部按钮明确叫“重新录制”，不是错误标成“继续”；但点击后直接 startRecording，无丢弃确认。Coordinator 清空检测/HUD 计数，Renderer.isRecording 的默认启动路径清空点云。相比取消操作有确认，该破坏性入口缺少相同保护。

状态测试确认：继续补扫保留 500 点计数、1 条检测及原 identity；重新录制清空为 0 并产生新 identity。未使用真实 Metal 缓冲区，实际点云清理依据 Renderer setter 的调用链确认。

## 结论与验证

共同架构问题是 View 多个入口、若干 @State 和 Coordinator 的扫描生命周期分别负责重置，没有一个完整的新扫描状态转换。重复添加布尔开关容易继续遗漏入口。

新增两项状态边界检查，ScanReadinessTests 共 7 项通过；日志 `/tmp/fts-interaction-audit.log`。git diff --check 通过。未进行截图/界面自动点击或真机 LiDAR 验收，因此不作视觉布局结论。

本轮只增加测试与报告，未修复生产逻辑；保留此前全部修改，未提交或推送。整体判断：**needs changes**。
