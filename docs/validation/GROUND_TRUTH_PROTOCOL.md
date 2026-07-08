# FruitTreeScanner 真实果园 Ground Truth 协议

评估日期：2026-07-02
关联文档：`./COMMERCIAL_READINESS_REVIEW.md`、`./REAL_DEVICE_ACCEPTANCE.md`

## 目的

FruitTreeScanner 是否能商业化，最终取决于估算结果是否可信。UI、点云、导出和历史记录只能证明工具链存在；真实商业价值必须通过真实果园样本、人工基准值和可复现误差指标证明。

这份协议定义如何采集 ground truth、如何记录扫描条件、如何计算误差，以及什么结果可以进入客户试点。

## 核心问题

每一次验证都要回答四个问题：

1. App 估算的果数/产量和真实值差多少？
2. 同一棵树重复扫描的波动有多大？
3. 哪些场景会失败或低置信度？
4. App 是否能主动识别“不该相信结果”的情况？

如果不能回答这些问题，就不能声称已经商业级。

## 样本设计

### 最小试点数据集

| 项目 | 最低要求 | 推荐要求 |
|---|---:|---:|
| 树数量 | 30 棵 | 100 棵 |
| 品种 | 1 个明确品种 | 2-3 个品种 |
| 每棵扫描次数 | 2 次 | 3 次 |
| 采集人员 | 1 人 | 2-3 人 |
| 光照条件 | 2 种 | 3 种以上 |
| Ground truth | 人工果数或采摘重量 | 果数 + 重量 |

### 样本分层

每批样本应覆盖：

- 小树 / 中等树 / 大树；
- 低遮挡 / 中遮挡 / 高遮挡；
- 稀疏结果 / 中等结果 / 高挂果量；
- 晴天强光 / 阴天柔光 / 傍晚弱光；
- 正常树形 / 偏冠 / 枝叶密集。

如果只测试好扫、无遮挡、光照理想的树，结果不能代表商业场景。

## 树体元数据

每棵树必须记录：

```text
tree_id:
plot_id:
row_id:
variety:
growth_stage:
scan_date:
operator:
device_model:
os_version:
weather:
light_condition:
tree_height_estimate_m:
canopy_width_estimate_m:
occlusion_level: low / medium / high
notes:
```

## 扫描协议

每棵树至少扫描两次：

1. 标准扫描：采集员按 App 引导完成一圈或主要可见面。
2. 重复扫描：同一人间隔 1-3 分钟重新扫描。
3. 推荐附加：第二名采集员再扫一次，用于判断操作员差异。

每次扫描记录：

```text
scan_id:
tree_id:
operator:
start_time:
duration_seconds:
point_count:
coverage_percent:
depth_status:
exportable_point_status:
app_count_estimate:
app_yield_kg_estimate:
confidence_label:
diagnostic_warnings:
ply_filename:
result_record_id:
```

扫描规则：

- 不允许为了让结果好看而重扫到满意为止。
- 如果扫描失败，要保留失败记录并标注原因。
- 如果 App 提示低质量或不可导出，仍应记录该状态。
- 每棵树的扫描顺序应固定，避免只选容易样本。

## Ground truth 获取方式

### 方式 A：人工果数

适用于果数较少或可见性较高的树。

要求：

- 至少两人独立计数；
- 两人差异 > 5% 时复核；
- 记录最终确认值；
- 标注是否有遮挡区域无法目测。

### 方式 B：采摘重量

适用于商业产量验证。

要求：

- 每棵树独立采摘和称重；
- 称重设备精度至少 0.1 kg；
- 记录包装/篮筐皮重；
- 记录落果、病果、未成熟果是否计入。

### 方式 C：抽样平均果重

如果只统计果数但要估算重量，应记录平均单果重：

- 每棵树随机抽取至少 20 个果；
- 或每个品种/地块抽取至少 100 个果；
- 记录平均值和标准差；
- 不允许用单个默认重量代表全部场景。

## 数据表结构

建议用 CSV/Excel 建立三张表。

### `trees.csv`

| 字段 | 含义 |
|---|---|
| tree_id | 树体唯一编号 |
| plot_id | 地块 |
| variety | 品种 |
| growth_stage | 生长/成熟阶段 |
| height_m | 树高估计 |
| canopy_width_m | 冠幅估计 |
| occlusion_level | 遮挡等级 |

### `scans.csv`

| 字段 | 含义 |
|---|---|
| scan_id | 扫描唯一编号 |
| tree_id | 对应树体 |
| operator | 采集员 |
| device_model | 设备 |
| duration_seconds | 扫描时长 |
| point_count | 点云数量 |
| coverage_percent | 覆盖率 |
| app_count_estimate | App 果数估算 |
| app_yield_kg_estimate | App 产量估算 |
| confidence_label | App 置信度 |
| warnings | 诊断提示 |
| result_record_id | App 记录 ID |

### `ground_truth.csv`

| 字段 | 含义 |
|---|---|
| tree_id | 树体 |
| true_count | 人工确认果数 |
| true_yield_kg | 实际称重 |
| count_method | 计数方法 |
| weight_method | 称重方法 |
| avg_fruit_weight_g | 平均果重 |
| reviewer | 复核人 |
| notes | 备注 |

## 指标计算

### 果数误差

```text
count_error = app_count_estimate - true_count
absolute_count_error = abs(count_error)
count_percentage_error = abs(count_error) / true_count
```

### 产量误差

```text
yield_error_kg = app_yield_kg_estimate - true_yield_kg
absolute_yield_error_kg = abs(yield_error_kg)
yield_percentage_error = abs(yield_error_kg) / true_yield_kg
```

### 批次指标

必须输出：

- MAE：平均绝对误差；
- MAPE：平均绝对百分比误差；
- RMSE：大误差惩罚；
- Bias：是否系统性高估/低估；
- Repeatability：同一棵树多次扫描的结果波动；
- Failure Rate：无法估算或低质量结果比例。

## 商业试点门槛

首轮试点不要求完美，但必须诚实。

最低建议门槛：

| 指标 | 最低门槛 |
|---|---:|
| 主流程完成率 | ≥ 90% |
| 记录持久化成功率 | 100% |
| 可导出文件成功率 | ≥ 95% |
| 果数 MAPE | 先记录，不承诺 |
| 产量 MAPE | 先记录，不承诺 |
| 重复扫描变异系数 | 先记录，不承诺 |
| 低置信度识别 | 必须能标出风险 |

商业宣传前建议门槛：

| 指标 | 建议门槛 |
|---|---:|
| 主流程完成率 | ≥ 98% |
| Crash-free 扫描会话 | ≥ 99% |
| 果数 MAPE | 按品种公开 |
| 产量 MAPE | 按品种公开 |
| 低质量扫描拦截率 | 可解释且可复核 |
| 失败场景说明 | 必须写入用户文档 |

## 失败案例分类

每个失败结果必须归类：

- 光照问题；
- 遮挡过高；
- 扫描距离不合适；
- 移动过快；
- 点云稀疏；
- 图像检测失败；
- 点云聚类失败；
- 融合不一致；
- App 崩溃或状态错误；
- Ground truth 本身不可靠。

失败案例不是坏事。商业级产品需要知道边界，不能把所有结果都包装成可信。

## 验证报告模板

每批样本完成后输出：

```text
批次编号：
日期：
果园：
品种：
树数量：
扫描次数：
设备：
采集员：

主流程完成率：
崩溃次数：
导出成功率：

果数 MAE：
果数 MAPE：
产量 MAE：
产量 MAPE：
Bias：
重复扫描波动：

主要失败原因：
最可信场景：
最不可信场景：
下一轮改进：
是否允许客户试点：是 / 否
```

## 版本管理

每批 ground truth 数据必须绑定：

- App commit；
- 模型版本；
- 参数版本；
- 设备型号；
- iOS/iPadOS 版本；
- 数据采集日期。

如果模型或估算参数变化，旧结果不能直接和新结果混算，必须重新标记版本。

## 下一步

建议先完成一批 10-15 棵树的小样本预试验。目标不是追求漂亮误差，而是发现：

1. 哪些操作用户容易做错；
2. 哪些场景 App 会低质量；
3. 当前估算是系统性高估还是低估；
4. 需要优先修 UI 流程、点云质量还是算法模型。

只有这批预试验完成后，才值得继续大规模优化算法或商业化包装。
