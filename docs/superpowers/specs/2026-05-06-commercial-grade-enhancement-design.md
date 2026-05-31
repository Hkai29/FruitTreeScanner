# FruitTreeScanner 商业级增强设计

## 目标

增强模式：保留自研 LiDAR 扫描 + 果实检测特色，扫描交互/稳定性/算法向商业 3D Scanner App 看齐，利用 ARMeshAnchor 获取网格，支持导入外部扫描结果。

## 阶段一：基础体验对齐（优先）

### 1.2a PointCloudView 性能修复
- 问题：为每个点创建 SCNNode，200万点 = OOM 崩溃
- 方案：用自定义 SCNGeometry + SCNGeometrySource 批量渲染点云
- 验证：加载 100 万点 PLY 不崩溃，帧率 > 30fps

### 1.2b detectedFruits 双路写入统一
- 问题：processDetectionQueue() 和 imageDetector delegate 都写 detectedFruits
- 方案：移除 delegate 回调，只保留定时器驱动
- 验证：编译通过，扫描时日志无重复检测

### 1.2c GPU/CPU 竞争修复
- 问题：extractColoredPoints() 直接读 Metal buffer，与 GPU 写入无同步
- 方案：在 renderFrame() 的 commandBuffer 完成回调中标记 snapshotReady，估算线程等待该标记后再读取
- 验证：连续扫描 30 秒无崩溃

### 1.2d SettingsStore 线程安全
- 问题：被主线程/后台 Task/Metal 线程同时访问
- 方案：加 @MainActor，非主线程访问走 MainActor.run
- 验证：编译通过，Thread Sanitizer 无警告

### 1.1 扫描交互改进
- HUD 改为：覆盖率 + 面积 + 点数
- 覆盖率基于 ARMeshAnchor 网格面积计算
- 覆盖率停滞时提示用户移动方向

### 1.3 扫描流程优化
- 覆盖率 > 85% 自动提示"扫描完成"
- 连续扫描模式：完成一棵后自动递增编号
- 估算可取消

## 阶段二：网格重建 + 多格式导出

### 2.1 ARMeshAnchor 集成
- ARWorldTrackingConfiguration.sceneReconstruction = .mesh
- 扫描时点云 + 半透明网格同时显示
- 扫描后可选"点云视图"或"网格视图"

### 2.2 多格式导出
- Binary PLY（体积缩小 4 倍）
- OBJ + MTL（从 ARMeshAnchor）
- USDZ（AR Quick Look）
- STL（3D 打印）

### 2.3 外部文件导入
- 从文件 App/AirDrop/iCloud 导入 PLY/OBJ
- 解析后跑果实检测 pipeline

## 阶段三：高级功能

### 3.1 离线重处理
- 保存原始点云 + 相机参数
- 调参后重新跑 pipeline

### 3.2 校准数据反馈算法
- 校准记录 → 自动调整遮挡校正/球形度/颜色阈值
- ≥5 组校准数据启用

### 3.3 路线A 训练
- 采集 DBH/树高/冠幅/实际产量
- 最小二乘拟合，≥10 组启用

### 3.4 FruitType/FruitCategory 合并
- 统一为单一 enum，新增水果只改一处

## 架构重构

ScanCoordinator 拆分为：
- ScanSession — ARSession 生命周期
- PointCloudCollector — 点云采集 + 双缓冲
- MeshCollector — ARMeshAnchor 管理
- DetectionPipeline — 图像检测
- FusionPipeline — 聚类 + 融合验证
- YieldPipeline — 产量估算

## 实施原则

- 一步一步，每步做 debug 验证
- 每步完成后编译 + 运行确认
- 不跳跃，不批量修改
