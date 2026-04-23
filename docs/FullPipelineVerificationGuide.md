# FruitTreeScanner 全流程验证指南

## 目标

验证从 YOLOv8 COCO 预训练模型 → CoreML → iOS App 集成的完整流程。

---

## Step 1: 在 Google Colab 中导出 CoreML 模型

### 1.1 打开 Google Colab

访问: https://colab.research.google.com

### 1.2 上传验证脚本

1. 点击 "文件" → "上传笔记本"
2. 选择 `Scripts/verify_pipeline.ipynb`
3. 或直接新建代码单元，粘贴以下代码：

```python
# 安装依赖
!pip install ultralytics -q

# 加载 COCO 预训练模型并导出 CoreML
from ultralytics import YOLO
model = YOLO('yolov8s.pt')
coreml_path = model.export(format='coreml')
print(f"导出成功: {coreml_path}")
```

### 1.3 下载模型

运行代码后，点击生成的 `.mlmodel` 文件下载。

---

## Step 2: 添加模型到 Xcode 项目

### 2.1 重命名模型文件（可选）

如果下载的文件名是 `yolov8s.mlmodel`，建议改名为 `FruitsDetector.mlmodel`（与代码中的默认名称一致）。

### 2.2 添加到 Xcode

1. 打开 `FruitTreeScanner.xcodeproj`
2. 将 `.mlmodel` 文件拖入 `FruitTreeScanner/Core/` 文件夹
3. 确保 "Target" 勾选了 `FruitTreeScanner`
4. Xcode 会自动编译模型（需要几秒钟）

---

## Step 3: 修改代码支持 COCO 类别

### 3.1 更新 FruitModels.swift

在 `FruitModels.swift` 中添加 COCO 映射（**重要！**）：

```swift
// MARK: - COCO 类别映射 (用于 COCO 预训练模型)

// COCO 数据集中的水果类别 ID
enum COCOFruit: Int, CaseIterable {
    case apple = 77
    case orange = 78
    case banana = 52
    case broccoli = 39

    /// 映射到 FruitCategory
    var fruitCategory: FruitCategory? {
        switch self {
        case .apple: return .apple
        case .orange: return .orange
        default: return nil
        }
    }
}

extension FruitCategory {
    /// 从 COCO 类别 ID 获取 FruitCategory
    static func fromCOCO(_ cocoID: Int) -> FruitCategory? {
        return COCOFruit(rawValue: cocoID)?.fruitCategory
    }
}
```

### 3.2 更新 ImageDetector.swift 的映射逻辑

当前 `ImageDetector.swift` 的 `categoryMapping` 只支持英文标签，但 COCO 模型输出的是类别索引。需要修改 `mapObjectObservationsToFruits` 方法：

```swift
// 在 ImageDetector.swift 中，将此方法替换：

private func mapObjectObservationsToFruits(observations: [VNRecognizedObjectObservation], timestamp: TimeInterval) -> [DetectedFruit] {
    var detectedFruits: [DetectedFruit] = []

    for observation in observations {
        guard observation.confidence >= config.minConfidence else { continue }
        guard let topLabel = observation.labels.first else { continue }

        // 首先尝试用 FruitCategory 名称匹配
        if let category = self.categoryMapping[topLabel.identifier.lowercased()] {
            let fruit = DetectedFruit(
                category: category,
                boundingBox: observation.boundingBox,
                confidence: topLabel.confidence,
                timestamp: timestamp
            )
            detectedFruits.append(fruit)
        }
        // 如果没有匹配，尝试从 identifier 中解析 COCO 类别
        else if let category = FruitCategory.fromCOCO(observation.identifier) {
            let fruit = DetectedFruit(
                category: category,
                boundingBox: observation.boundingBox,
                confidence: topLabel.confidence,
                timestamp: timestamp
            )
            detectedFruits.append(fruit)
        }
    }

    return detectedFruits
}
```

---

## Step 4: 构建并运行

### 4.1 构建项目

```bash
xcodebuild -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### 4.2 在真机上测试（推荐）

模拟器无法访问相机，必须用真机：
1. 用 USB 连接 iPhone
2. 在 Xcode 中选择真机设备
3. 运行 App
4. 对着苹果或橙子扫描
5. 点击导出按钮查看结果

---

## Step 5: 验证结果解读

### 5.1 预期输出

```
扫描结果:
- apple: 5 个 (fused=3, imageOnly=2)
- orange: 3 个 (fused=1, imageOnly=2)
总计: 8 个水果
```

### 5.2 结果说明

| 标记 | 含义 |
|------|------|
| fused | RGB 和 LiDAR 点云都检测到，最可靠 (权重 1.0) |
| imageOnly | 只有 RGB 检测到，可能遮挡区域 (权重 0.5) |
| cloudOnly | 只有点云检测到，可能是误检 (权重 0.3) |

### 5.3 可能的问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 检测不到水果 | 水果过小/光照差 | 增加光照，确保水果占比 >10% |
| 只有 cloudOnly | 图像检测失败 | 检查 CoreML 模型是否正确加载 |
| 计数不稳定 | 检测框重叠 | 调整 NMS 阈值 |

---

## Step 6: 进入自定义训练

全流程验证通过后，下一步是训练自定义水果检测模型：

1. 拍摄 50+ 张/类水果照片
2. 在 Roboflow 标注
3. 运行 `Scripts/train_yolov8.py`
4. 导出 CoreML 并替换当前模型

详见: `docs/FruitDetectionModelGuide.md`

---

## 快速检查清单

- [ ] Colab 成功导出 .mlmodel
- [ ] 模型文件添加到 Xcode 项目
- [ ] 构建成功（无编译错误）
- [ ] 真机运行 App
- [ ] 能看到 AR 相机画面
- [ ] 对着水果扫描
- [ ] 点击导出按钮
- [ ] 查看检测结果
