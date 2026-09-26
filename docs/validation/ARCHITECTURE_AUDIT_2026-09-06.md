# 扫描—产量架构检查

> 本文保留修复前证据，当前修复状态见 [ARCHITECTURE_REPAIR_2026-09-06.md](ARCHITECTURE_REPAIR_2026-09-06.md)。

## P1：证据身份未穿过模块边界，估重再次进行贪心关联

FusionValidator.swift 已选出 candidate，并知道 candidate.id；构造 ValidatedFruit 时却新建独立 UUID，只携带位置、类别、置信度、来源和直径。DetectionDeduplicator 又可移动融合位置。ScanYieldEstimateHelpers.swift:99-107 因缺少源候选身份，重新用 10 cm 最近邻且不放回地分配几何候选。

确定性边界探针：两个候选位于 x=0/0.18 m，直径 6/10 cm；两个 fused 结果位于 x=0.085/0 m。按前一顺序估重 0.29613274 kg、匹配到 1 个几何；反转同一集合后为 0.54119176 kg、匹配到 2 个几何。匹配失败部分退回默认单果重量。

这个测试直接作用于估重接口，证明接口不满足集合排列不变量；未证明真实扫描一定产生该位置组合，也不是实测总体误差率。架构修复应保留源 candidate/track 身份及合并后的证据成员，使估重消费明确关联。不能简单扩大匹配距离或只排序输入来掩盖歧义。

## P1：检测置信度和重量可信度混在一个等级中

ScanYieldEstimateHelpers.estimateQuality 只接收 ValidatedFruit；没有几何质量、默认重量占比或校准证据输入。相邻 computeYieldFromValidatedFruits 在匹配失败时使用平均重量，且不生成对应 FruitMassEstimate。新传入的 measuredDiameter 也未在此回退路径使用。

探针输入 6 个 confidence=1 的 fused 结果（都带 6 cm measuredDiameter），候选为空：得到 1.2 kg，massEstimates=0、meanDiameter=0；estimateQuality 返回 high。YieldResultComposer 随后只按覆盖/遮挡风险进一步调整，未依据这次质量回退降级。

这证明质量接口可以把完全依赖默认重量的结果评价为 high；不是声称任意覆盖情况下最终 UI 都显示 high。需要分开记录检测证据、几何测量、默认重量回退、遮挡与校准的可靠性，并定义最终质量合成规则。

## P1：校准无算法版本隔离

CalibrationRecord.swift:5-13 没有算法、模型、参数或原始/已校准结果版本；YieldCalibrationCorrector:133-169 只按水果品类匹配，随后用 actualYield/estimatedYield 的中位比率生成修正系数。

因此旧算法的误差补偿可以被用于更新后的几何和遮挡算法。此次修复改变了这两条链路，风险已具有具体触发条件。但没有读取用户真实校准样本证明当前已有受影响记录，也没有量化其实际偏差。

应引入可追溯的估算版本、参数快照、校准来源与兼容规则。旧记录不能静默删除；不兼容记录应明确隔离或重新评估。

## 共同根因与验证

模块已经分文件，但核心传输对象压缩掉了关联身份和质量来源；下游只能重新匹配、回退及推断。优先完善证据数据契约，比增加更多服务类更直接。

- 本轮新增两个缺陷行为探针，YieldEstimatorTests 40 项通过。断言记录当前缺陷，不能称为修复通过；正式修复时应改成正确不变量断言。
- 日志 `/tmp/fts-architecture-audit.log`；git diff --check 通过。
- 未修改生产逻辑，保留前轮全部修改及融合限制；未运行全量、Release 或真机；未提交或推送。
- 判断：**needs changes**。
