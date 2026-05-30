# FruitTreeScanner 项目规范

## 行为准则

### 01. 编码前思考
不假设，不藏困惑，有矛盾就摆出来，不确定就问

### 02. 简洁优先
用户没要的功能不加，200行能写成50行就重写

### 03. 精准修改
只碰必须碰的，不顺手改格式，不重构没坏的东西

### 04. 目标驱动
把修 bug 翻译成先写复现测试，再让它通过

---

## 项目架构

```
FruitTreeScanner/
├── App/                    # 入口
├── Core/                   # 核心算法
│   ├── PointCloudFusion.swift    # 多模态融合
│   ├── PointCloudCluster.swift   # DBSCAN 聚类
│   ├── YieldEstimator.swift      # 产量估算
│   ├── ImageDetector.swift       # CoreML/Vision 检测
│   ├── FusionValidator.swift     # 融合验证
│   └── Renderer.swift            # Metal 渲染
├── Views/                  # SwiftUI 视图
├── Components/             # 组件 (暗色主题)
│   ├── GlassCard.swift          # 玻璃拟态卡片
│   ├── FingerGlowOverlay.swift  # 手指光效
│   └── HUDPill.swift            # HUD 数据胶囊
├── Design/                # 设计系统
│   ├── Theme.swift              # 基础主题
│   └── Theme+Dark.swift         # 暗色扩展
└── GPS/                   # GPS 记录
```

## 核心算法流程

1. **扫描采集** → ARKit + LiDAR 点云
2. **颜色过滤** → RGB 阈值筛选
3. **点云聚类** → DBSCAN 算法
4. **球体拟合** → 尺寸验证
5. **融合验证** → RGB 检测 + 点云候选匹配
6. **产量估算** → 体积 × 密度

## 设计系统

- **暗色主题**: `Design.Colors.Dark.*`
- **发光色**: `Design.Colors.harvest` (#FF9500)
- **间距**: `Design.Space.*`
- **圆角**: `Design.Radius.*`
