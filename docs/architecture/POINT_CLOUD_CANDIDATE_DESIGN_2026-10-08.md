# 点云候选管线与纯算法依赖闭包设计

2026-10-08，第 58 轮后续设计。**第 59 轮已实施并验证**；实际证据与剩余项见 [第 59 轮记录](REFACTOR_ITERATIONS_2026-09-27.md#第五十九轮完整点云候选管线与纯算法依赖闭包)。延续原 R4/R7 的领域责任与资源边界；本设计没有关闭真实观测、物理资源、应用协作和设备验收。

## 1. 真实缺口与生产调用链

当前 `Core/PointCloudCandidatePipeline.run` 执行颜色过滤、统计离群点去除和 DBSCAN 聚类，但接收整个 `ScanFusionYieldBuilder.Input`，间接耦合 Renderer、检测诊断和估产装配。实际需要的只有点值、有效颜色过滤器、聚类配置和本次扫描的点云实验配置。

```text
Renderer.finalPointCloud → 冻结点云/扫描参数
  → ScanYieldEstimationController 的后台任务
  → ScanFusionYieldBuilder → PointCloudCandidatePipeline
  → PointCloudDenoiser → KDTree
  → PointCloudCluster → KDTree
  → FusionEvidencePipeline → ReliableYieldEvidence → 数值估产/结果装配
```

`PointCloudCluster`、`PointCloudClusterAnalysis`、`KDTree` 只依赖纯值及 Foundation/simd，可以与候选编排一起形成可独立编译的依赖闭包。聚类主体调用的 `analyzeCluster` 及颜色、尺寸、球形度、特征值分析定义在 `PointCloudClusterAnalysis.swift` 的 extension，必须连同该文件完整迁移。`PointCloudDenoiser` 则混有两个 `RendererPointSample` 专用重载；该点类型位于 `RendererPointCloudExport.swift`，与 Metal/GPU 导出职责相邻。整文件搬迁会把 Renderer 依赖带进 Domain，必须按真实依赖切开。

## 2. 最小责任设计

| 位置 | 交付职责 |
|---|---|
| Domain/PointCloud | 不可变 `PointCloudCandidateInput`：`[ColoredPoint]`、已解析的 `ColorFilter?`、`ClusterConfig`、`PointCloudExperimentConfig` |
| Domain/PointCloud | 当前候选 output 和具体管线，依次执行过滤、原 SOR、原聚类；保留全部阶段输出及诊断统计 |
| Domain/PointCloud | 原 `KDTree`、`PointCloudCluster` 与完整 `PointCloudClusterAnalysis` extension、通用去噪统计/result/泛型算法及 unchangedResult，维持原算法与可见 API |
| Core 适配 | 保留 `PointCloudCandidatePipeline.run(ScanFusionYieldBuilder.Input)` 重载，解析 `colorFilter ?? fruitCategory?.colorFilter` 后调用纯值管线 |
| Core Renderer 适配 | 在 `extension PointCloudDenoiser` 保留两个 `RendererPointSample` 重载、默认参数和 `$0.position` 适配 |
| 现有采集/应用层 | 保持 GPU 缓冲、采样预算、revision/cache/identity、后台调度及取消准入的现有所有权 |

实际 builder 必须经过这个纯值入口；不增加无人使用的平行管线、空协议或第二套算法。Core 中的深度候选与品类过滤保持原职责，不随点云闭包一起搬走。有效颜色过滤器只解析一次，Domain 无需重新解释目标品类优先级。

## 3. 行为与资源契约

| 契约 | 必须保留的原行为 |
|---|---|
| 颜色过滤 | 显式过滤器优先，nil 时才使用品类过滤器；两者都 nil 时返回原点数组；点顺序保持 |
| SOR 准入 | 最小点数为 `max(minPoints * multiplier, floor)`；达到该数才运行；不增加阈值钳位 |
| SOR 算法 | `samples.count > k + 1`、邻域/排除自己、Float/Double 累积与转换、`<= threshold`、原保留顺序和统计值保持 |
| 聚类 | 原 async 最小点数早返回、userInitiated 队列和 continuation；同步/debug API、DBSCAN 噪点/边界、局部间距、球形度、几何、权重和候选身份关联保持 |
| KDTree | 原输入索引、距离比较、等距顺序、堆与范围搜索边界保持 |
| 产量权限 | 只有 fused 准入值参与可靠估产；候选身份、一次消费、低置信度与拒绝深度禁止升级保持 |
| 资源所有权 | 不增加整云转换/额外常驻副本，保持现有数组与 COW；采样/分析预算仍由原采集入口负责 |
| 兼容 | 原 facade、Renderer 重载、阶段输出、诊断/零产原因、校准身份、存档/研究格式与 manifest 最后发布保持 |

纯算法迁移不等于解决物理峰值内存、Swift COW 实际复制或取消延迟。原 `PointCloudCluster` 内部异步执行方式保持，不顺带重写调度或声称新增协作取消。公共 builder 输入可能来自非 Renderer 调用者，不能把上游预算描述为所有输入的强制上限。

## 4. 实施与验收

1. preflight，核对第 58 轮最终受测摘要和原始方法树；保存本轮原件，保护已有 dirty，冻结范围。
2. 在原实现建立完整管线的固定预期基线：显式过滤优先/品类 fallback/无过滤、SOR 准入前一项与恰达阈值、`k+1` 边界、保留顺序/统计/离群点、空/最小点数聚类及候选几何。已有测试足够的契约直接复用，缺口才补测试。
3. 实施纯值入口与 Core 兼容适配；KDTree、聚类主体及 `PointCloudClusterAnalysis.swift` 整份逐字移动，去噪只拆 Renderer 重载，记录逐段原文保留证据。生产调用链真正经过 Domain，独立编译必须包含实际分析实现。
4. 固定数值、点身份/顺序、候选与融合的关联分别断言；UUID/时间等运行生成字段使用明确关联契约，不用跨次随机值字节相等作伪基线。
5. 新/迁移源唯一属于 App Sources。完整递归 Domain 独立编译不借 Core/Renderer、不删源或降低门禁；其余工程对象保持。
6. 运行点云、聚类、Renderer/生命周期、融合估产定向 profiles 和 full/Release。核对原方法全部保留、九项回放、校准 canonical bytes、归档/批量回放、实际 warnings 和最终源码摘要。
7. 独立只读复审输入解析、依赖闭包、边界/数值/顺序、后台执行与数组生命周期。阻塞项修复后重跑；记录真实证据及下一处原范围缺口。

## 5. 可直接使用的第 59 轮提示词

```text
继续第59轮，读取AGENTS.md、默认工作流、本设计、第58轮记录及原R0–R7完成核验。
preflight核对第58轮最终受测源码和方法树，保存原件、保护旧dirty；不提交推送合并。
追踪Renderer.finalPointCloud→后台估产→builder→点云候选→融合→结果/存档的真实链路。
交付完整点云候选纯值管线及KDTree/聚类/PointCloudClusterAnalysis/通用去噪依赖闭包，实际生产入口必须调用它。
纯值输入仅包含点、已解析颜色过滤器、聚类配置和冻结点云实验配置；有效过滤器只在Core解析一次。
保留run(builder.Input)兼容重载，不增加空协议、平行状态或无人使用的第二条路径。
先在原实现固定过滤优先级、SOR准入和k+1边界、点顺序/统计及候选几何的通过基线。
KDTree/PointCloudCluster/PointCloudClusterAnalysis.swift整份逐字迁移，保留分析extension的API和Sources唯一归属。
泛型去噪进入Domain，两个RendererPointSample重载留Core适配，不把Renderer类型拉入领域层。
保留所有数值/距离/等距/密度/球形度/候选身份规则、async早返回、QoS和原同步/debug API。
保留GPU/cache/revision/identity/采样预算和取消准入；不新增整云转换或擅自改变调度。
仅fused、深度否决、零产诊断、校准身份、旧schema及manifest最后发布均保持。
完整Domain门禁不得借Core/Renderer或排除新源；检查App Sources唯一归属。
执行相关定向、full/Release及独立只读复审，核对原方法、回放、canonical字节、告警和最终摘要。
记录实际证据与下一轮候选；整体保持active，不以目录迁移宣称真实资源或设备验收完成。
```
