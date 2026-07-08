# FruitTreeScanner

FruitTreeScanner 是一款面向果园场景的 iOS/iPadOS LiDAR 果树扫描应用。它把 ARKit 深度点云采集、CoreML 果实识别、扫描质量评估、点云查看、结果归档和批量导出整合到一个移动端工作流里，适合用于果树表型采集、田间巡检、果实数量估算和后续三维分析。

应用的目标不是只保存一份点云文件，而是让采集人员在现场完成从“选择果树、完成扫描、实时检查质量、查看点云、识别果实、生成结果、导出数据”的完整闭环。

## 核心能力

- **LiDAR 点云扫描**：基于 ARKit scene depth 和 Metal 渲染管线采集果树三维点云，支持树木编号、地块、品种、标签和 GPS 元数据。
- **实时扫描引导**：扫描页提供覆盖率、稳定性、距离、运动状态和完成度反馈，帮助采集人员减少漏扫和无效数据。
- **点云查看器**：支持自由、正面、俯视、侧面多种查看模式，按真实空间高度自动取景，并提供高度标尺、地面参考网格、缩放、颜色模式和测量入口。
- **果实识别与统计**：通过本地 CoreML 模型进行图像果实检测，并结合点云/扫描结果展示数量、置信度和估产相关指标。
- **结果报告**：扫描完成后展示成熟度更高的结果页，包括扫描质量、点云密度、果实数量、估产、置信度、环境与导出状态。
- **果园数据管理**：支持扫描历史、标签管理、品种库、地块地图、历史对比、趋势分析、校准记录和批量导出。
- **标准数据导出**：输出 ASCII PLY 点云文件和扫描结果数据，便于 Open3D、Python、GIS 或后续研究流程读取。

## App 工作流

1. 在首页选择快速扫描、历史记录、点云查看、果园地图、批量导出等功能。
2. 在扫描前录入或选择果树编号、地块、品种和标签。
3. 使用 LiDAR 扫描果树，应用实时提示覆盖率、稳定性和扫描质量。
4. 扫描过程中或扫描后查看点云，使用不同视角确认树冠高度、范围和点云密度。
5. 结合 CoreML 果实识别结果生成果实数量、估产和质量摘要。
6. 将扫描记录、点云文件、报告和元数据导出用于研究或生产分析。

## 技术栈

- **SwiftUI**：主界面、仪表盘、扫描流程、结果页和管理页面。
- **ARKit / RealityKit / SceneKit**：深度感知、相机位姿、点云采集和三维预览。
- **Metal**：扫描阶段的点云渲染、深度处理和 GPU 数据流。
- **CoreML / Vision**：本地果实识别模型加载、推理和后处理。
- **CoreLocation**：扫描记录的 GPS 坐标采集。
- **XCTest**：点云解析、检测去重、估产、扫描诊断和导出逻辑测试。

## 仓库布局

根目录只保留运行 App 必需入口和几类清晰的资产目录：

```text
FruitTreeScanner.xcodeproj   Xcode 工程
FruitTreeScanner/            iOS App 源码、资源、CoreML 运行时模型
FruitTreeScannerTests/       XCTest 单元测试与核心逻辑验证
docs/                        技术说明、实现记录、验收和验证文档
ml/                          训练数据、训练输出、模型实验资产
research/                    论文、章节草稿、LaTeX 和研究计划
tools/                       ML、论文和历史迁移辅助脚本
```

App 真正加载的模型在 `FruitTreeScanner/Core/FruitsDetector.mlpackage`。训练数据、YOLO 训练输出和历史导出模型统一放在 `ml/`，不会再摊在 GitHub 首页根目录。

## 点云数据

应用导出的 PLY 文件包含点坐标、颜色和扫描元数据，格式可被 Open3D 等工具直接读取。

```text
ply
format ascii 1.0
comment tree_id T001
comment scan_date 2026-07-14 10:30:20
comment gps_lat 22.567800
comment gps_lon 114.123400
element vertex 1234567
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
element face 0
property list uchar int vertex_indices
end_header
0.123 0.456 1.234 120 85 60
```

Python/Open3D 读取示例：

```python
import open3d as o3d

pcd = o3d.io.read_point_cloud("T001_20260714_103020_lat22.5678_lon114.1234.ply")
print(pcd)
```

## 运行要求

- iPhone 12 Pro/Pro Max 及更新机型，或配备 LiDAR 的 iPad Pro。
- iOS 16.0+。
- Xcode 15+。
- 真机运行需要相机和定位权限；LiDAR 扫描能力依赖设备硬件。

## 开发与验证

打开 `FruitTreeScanner.xcodeproj` 后选择 `FruitTreeScanner` scheme 构建运行。模拟器可用于 UI、导航、点云文件预览和基础逻辑验证；真实 LiDAR 采集与 AR 深度质量需要在支持 LiDAR 的真机上验证。

常用验证命令：

```bash
xcodebuild build \
  -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -destination 'generic/platform=iOS Simulator'

xcodebuild test \
  -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,name=<your simulator name>'
```

## 项目结构

```text
FruitTreeScanner/
  Components/       可复用 UI 与测量组件
  Core/             扫描、点云、识别、估产、导出和业务模型
  Design/           主题、颜色和视觉系统
  GPS/              定位采集
  Views/            SwiftUI 页面与流程
FruitTreeScannerTests/
  XCTest 单元测试与核心逻辑验证
docs/
  validation/      真机验收、ground truth 和商业可用性检查
  reference/       技术参考文档
ml/
  datasets/        训练数据集
  models/          训练/导出模型资产
  training-runs/   YOLO 训练输出和评估图表
research/
  paper/           LaTeX 和 Word 论文材料
  chapters/        章节草稿
  plan/            研究计划和证据地图
tools/
  ml/              训练、导出、点云分析脚本
  paper/           文档生成工具
  legacy/          历史迁移脚本
```

## 来源与许可

本项目基于 `ios-depth-point-cloud` 的 LiDAR 点云采集思路继续扩展，并面向果树扫描业务增加了 SwiftUI 工作流、点云查看、果实识别、数据管理和导出能力。项目代码按仓库许可证使用。
