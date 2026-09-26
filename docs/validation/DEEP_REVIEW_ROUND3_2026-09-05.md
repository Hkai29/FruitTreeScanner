# 第三轮：停止、暂停与排空的证据丢失

## P1：停止使在途证据失效，flush 无法补回

位置：ScanCoordinatorWorkflows.swift:45-70、212-226；ScanCoordinator.swift:353-360。

stopRecording 关闭证据门并推进 generation。已经出队的推理返回后被 production generation guard 丢弃。flushPendingDetections 等待的是 Task<Void>，没有保存被丢弃结果；下一次 processQueue 只能处理尚未出队的帧。

确定性检查调用真实生产提交入口：同一目标、对齐深度、间隔 0.5 s、置信度 0.99 的两次观测，第一条在停止前提交，第二条在停止并进入 finishing 后使用原 generation 提交，随后执行 flush。结果 input=2、retained=1、stable=0；两条原始观测直接稳定匹配得到 stable=1。

这是生命周期/提交边界的动态复现，未通过真实 CoreML 推理时序触发。其结果足以证明生产提交规则会损失可形成稳定轨迹的证据；不能将其夸大为所有扫描都会零产量。

## P1：同一扫描暂停再继续，也拒绝暂停前的在途结果

位置：ScanCoordinatorWorkflows.swift:196-215；ScanCoordinator.swift:344-360。

resumeRecordingPreservingCapture 保留同一 scanIdentity，代码注释明确希望保留在途任务。但暂停与恢复各推进一次 evidence generation，原任务仍然被拒绝。

动态结果：sameIdentity=true、oldGenerationAccepted=false、retained=0。这与上一问题共享代次策略根因，不应统计为完全独立的算法缺陷。

修复方向：区分正常暂停/完成与新扫描/系统中断/取消。只允许同一扫描中已经合法接收的帧完成提交，维持旧扫描及被中断证据的拒绝；不能简单取消 generation guard 或把所有 finishing 结果无条件接纳。

## P2：排空等待超时被当成空队列

位置：ImageDetectorQueue.swift:202-213。

drainPendingFrames 最多等待 6×25 ms，随后不论 preparing 是否结束都只返回 frames。模拟“已选中帧持续准备”的确定性检查得到 returnedEmpty=true、preparationStillPending=true。返回接口没有区分真正空队列与等待超时，完成流程可能提前建立估算快照。

这里验证的是超时处理分支，不是实际设备复制耗时。真实重载情况下的发生频率与最终漏计程度仍待测量。修复应提供可取消、可识别扫描代次的准备完成信号，或显式报告超时/不完整证据，不能无限等待。

## 验证与范围

- 新增 3 项缺陷行为检查；ScanFusionYieldBuilderTests 全组 39 项通过，约 7.04 s。
- 检查断言当前缺陷行为，用于保留复现证据；“测试通过”不表示以上问题已修复。正式修复时必须改成正确行为的回归断言。
- 日志：`/tmp/fts-deep3.log`；xcresult：`/tmp/fts-repair-build/Logs/Test/Test-FruitTreeScanner-2026.09.05_23-11-21-+0800.xcresult`。
- 本轮只新增测试和报告，未修改生产逻辑，保留此前全部修改及可靠融合限制；git diff --check 通过。未重新跑全量或 Release，未进行真机扫描，未提交或推送。

发布判断：**needs changes**。
