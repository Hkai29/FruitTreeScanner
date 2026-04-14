# FruitTreeScanner — 果树 LiDAR 采集 App

基于 [ios-depth-point-cloud](https://github.com/Waley-Z/ios-depth-point-cloud)（MIT License）改造

---

## 功能

- iPad Pro LiDAR 实时点云采集
- 输入树木编号（T001~T100），自动写入 PLY header
- GPS 坐标自动记录
- 导出标准 ASCII PLY 文件（与 Python/Open3D 直接兼容）
- 扫描历史管理 + AirDrop 一键分享

---

## 改动说明（相对原始项目）

| 文件 | 改动 |
|------|------|
| `Renderer.swift` | maxPoints 500k→200万；savePointCloud 加 treeID/GPS 参数；PLY header 加元数据 |
| `Utils.swift` | 新增 `makeTreeFileName()` |
| `ScanView.swift` | 原 UIKit ViewController 改写为 SwiftUI |
| `StartView.swift` | 新增（树木编号输入界面）|
| `ScanHistoryView.swift` | 新增（历史记录 + AirDrop 分享）|
| `GPSRecorder.swift` | 新增（CoreLocation GPS 采集）|

原始文件直接复用（不改动）：
- `Helpers.swift` / `MetalBuffer.swift` / `Shaders.metal`

---

## PLY 输出格式

```
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
...
```

Python 读取：
```python
import open3d as o3d
pcd = o3d.io.read_point_cloud("T001_20260714_103020_lat22.5678_lon114.1234.ply")
```

---

## 如何导入 Xcode

1. 新建 Xcode 项目（SwiftUI App 模板，iOS 16+）
2. 将本目录所有 `.swift` 文件拖入项目
3. 从原始项目复制 `Shaders.metal`（Metal GPU shader，点云投影核心）
4. 在 `Info.plist` 添加权限：
   - `NSCameraUsageDescription`（相机）
   - `NSLocationWhenInUseUsageDescription`（GPS）
5. 连接 iPad Pro，运行

---

## 设备要求

- iPad Pro 2020+ 或 iPhone 12 Pro+（必须有 LiDAR）
- iOS 16.0+
- Xcode 15+

---

## License

改造代码：MIT  
原始 ios-depth-point-cloud：Apple 示例代码 / MIT
