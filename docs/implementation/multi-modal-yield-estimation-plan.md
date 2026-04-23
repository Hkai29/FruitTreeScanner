# FruitTreeScanner 多模态融合产量估算实现计划

## 目标

实现基于 RGB 图像 + LiDAR 点云融合的果树产量估算系统，在不破坏现有扫描功能的前提下，新增：

1. 图像检测模块（ImageDetector）— 预训练水果检测模型
2. 点云聚类模块（PointCloudCluster）— DBSCAN 3D 聚类
3. 融合验证模块（FusionValidator）— 图像检测 ↔ 点云聚类匹配
4. 计数统计模块（FruitCounter）— 各类水果计数

## 现有架构

```
ScanView.swift
    └── ScanCoordinator
            ├── Renderer (Metal/LiDAR 点云渲染)
            └── YieldEstimator (产量估算 - 待扩展)
```

## 新增模块架构

```
YieldEstimator (扩展点)
    ├── ImageDetector     — 图像水果检测
    ├── PointCloudCluster — 3D 点云聚类
    ├── FusionValidator   — 融合验证
    └── FruitCounter      — 计数统计
```

---

## 模块详细设计

### 1. ImageDetector

**职责：** 封装图像检测模型，每 N 帧采样检测一次水果

**接口：**
```swift
protocol ImageDetectorDelegate: AnyObject {
    func imageDetector(_ detector: ImageDetector, didDetect fruits: [DetectedFruit])
}

struct DetectedFruit {
    let category: FruitCategory      // 水果类别（苹果/橙子/梨/桃/樱桃）
    let boundingBox: CGRect          // 图像中的检测框
    let confidence: Float            // 置信度
    let timestamp: TimeInterval      // 检测时间戳
}

enum FruitCategory: String, CaseIterable {
    case apple, orange, pear, peach, cherry
}
```

**实现要点：**
- 使用 Vision VNRecognizeAnimalsRequest 或自定义 CoreML 模型
- 每 10 帧或每 0.5 秒检测一次（可配置）
- 检测在后台线程执行，不阻塞主线程
- 模型文件：FruitDetector.mlmodel（预训练，转换为 CoreML）

**文件位置：** `FruitTreeScanner/Services/ImageDetector.swift`

---

### 2. PointCloudCluster

**职责：** 对点云做 DBSCAN 3D 聚类，提取球形物体候选

**接口：**
```swift
protocol PointCloudClusterDelegate: AnyObject {
    func pointCloudCluster(_ cluster: PointCloudCluster, didFind candidates: [FruitCandidate])
}

struct FruitCandidate {
    let id: UUID
    let position: SIMD3<Float>        // 3D 中心位置
    let diameter: Float               // 估算直径（米）
    let sphericity: Float             // 球形度 (0-1)
    let pointCount: Int                // 包含的点数
    let clusterIndices: [Int]         // 对应的点索引
}
```

**实现要点：**
- DBSCAN 聚类，eps 自适应（近处小，远处大）
- 对每个聚类计算：
  - 包围盒 → 估算直径
  - 协方差矩阵特征值 → 球形度
- 尺寸过滤：保留 0.04m - 0.15m 直径的候选
- 球形度过滤：> 0.5

**文件位置：** `FruitTreeScanner/Services/PointCloudCluster.swift`

---

### 3. FusionValidator

**职责：** 将图像检测结果与点云聚类匹配验证

**接口：**
```swift
protocol FusionValidatorDelegate: AnyObject {
    func fusionValidator(_ validator: FusionValidator, didValidate fruits: [ValidatedFruit])
}

struct ValidatedFruit {
    let category: FruitCategory
    let position: SIMD3<Float>
    let confidence: Float
    let source: ValidationSource
}

enum ValidationSource {
    case imageOnly      // 只有图像检测
    case cloudOnly       // 只有点云聚类
    case fused           // 两者都验证通过
}
```

**匹配算法：**
1. 对每个图像检测结果：
   - 将 2D 检测框反投影到 3D 空间（利用深度图）
   - 在点云聚类中查找位置接近的候选
   - 尺寸匹配容差 ±20%
2. 通过验证的 → `ValidationSource.fused`
3. 只有图像检测的 → `ValidationSource.imageOnly`（可能是遮挡区域）
4. 只有点云聚类的 → `ValidationSource.cloudOnly`（可能是漏检）

**文件位置：** `FruitTreeScanner/Services/FusionValidator.swift`

---

### 4. FruitCounter

**职责：** 统计各类水果数量，输出最终结果

**接口：**
```swift
struct YieldResult {
    let fruitCounts: [FruitCategory: Int]
    let totalCount: Int
    let validatedFruits: [ValidatedFruit]
    let timestamp: Date
}
```

**实现要点：**
- 根据 ValidationSource 权重计算：
  - fused 权重 1.0
  - imageOnly 权重 0.5
  - cloudOnly 权重 0.3
- 输出各类水果计数
- 可选：输出带位置的 3D 水果分布图

**文件位置：** `FruitTreeScanner/Services/FruitCounter.swift`

---

## 数据流

```
1. 扫描进行中：
   ARKit Frame
       ├── RGB Image → ImageDetector（每 N 帧）
       └── LiDAR Points → PointCloudCluster（实时或事后）

2. 检测结果：
   ImageDetector → [DetectedFruit]
   PointCloudCluster → [FruitCandidate]

3. 融合验证：
   [DetectedFruit] + [FruitCandidate] → FusionValidator → [ValidatedFruit]

4. 计数输出：
   [ValidatedFruit] → FruitCounter → YieldResult
```

---

## 集成点

### 修改现有文件

**FruitTreeScanner/Services/YieldEstimator.swift**（扩展）
```swift
// 新增属性
var imageDetector: ImageDetector?
var pointCloudCluster: PointCloudCluster?
var fusionValidator: FusionValidator?
var fruitCounter: FruitCounter?
```

### 新增文件

- `FruitTreeScanner/Services/ImageDetector.swift`
- `FruitTreeScanner/Services/PointCloudCluster.swift`
- `FruitTreeScanner/Services/FusionValidator.swift`
- `FruitTreeScanner/Services/FruitCounter.swift`
- `FruitTreeScanner/Models/FruitModels.swift`（共享类型定义）
- `FruitTreeScanner/Resources/MLModels/FruitDetector.mlmodel`（预训练模型）

---

## 测试计划

1. **单元测试** — 每个模块独立测试
2. **集成测试** — 端到端数据流测试
3. **功能验证** — 扫描真实果树，验证计数准确性

---

## 风险与缓解

| 风险 | 缓解措施 |
|---|---|
| 图像检测模型不准确 | 使用学术验证过的预训练模型 |
| 点云聚类参数难调 | 提供可视化调试工具，允许手动调参 |
| 融合匹配计算量大 | 后台线程执行，分帧处理 |
| 现有功能被破坏 | 每个 PR 必须通过所有现有测试 |

---

## 优先级

1. **Phase 1：** PointCloudCluster（核心，最先完成）
2. **Phase 2：** ImageDetector（图像检测）
3. **Phase 3：** FusionValidator（融合）
4. **Phase 4：** FruitCounter（计数）
5. **Phase 5：** 集成测试

---

**版本：** 1.0
**创建日期：** 2026-04-23
