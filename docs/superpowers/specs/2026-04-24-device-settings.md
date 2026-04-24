# 设备设置规格说明书 (Device Settings Specification)

## 1. 概述

本文档描述 FruitScanner iOS 应用的"设备"设置界面的设计规范。该界面用于配置与硬件相关的扫描参数，包括传感器校准和相机配置。

### 1.1 现有系统分析

| 组件 | 文件 | 说明 |
|------|------|------|
| 渲染器 | `FruitTreeScanner/Core/Renderer.swift` | 使用 Metal 渲染点云，`cameraResolution` 从 `ARFrame.camera.imageResolution` 获取 |
| AR 会话 | `FruitTreeScanner/Views/ScanView.swift` | `ScanCoordinator.bind()` 中配置 `ARWorldTrackingConfiguration`，启用 `.sceneDepth` |
| 设置存储 | `FruitTreeScanner/Core/SettingsStore.swift` | 使用 `UserDefaults` 持久化，`Keys` 枚举管理所有键 |
| 校准界面 | `FruitTreeScanner/Views/CalibrationView.swift` | 现有视图用于**算法校准**（聚类参数、HSV阈值），非传感器校准 |
| 设置界面 | `FruitTreeScanner/Views/SettingsView.swift` | 现有实现为静态列表，无展开/折叠功能 |

### 1.2 关键约束

- ARKit `ARWorldTrackingConfiguration` 不直接暴露帧率配置；帧率由系统根据设备自动选择
- 相机分辨率受设备硬件限制，iPhone 12+ 支持 1080p@60fps 或 4K@30fps 录制
- `Renderer.cameraResolution` 是只读的，从当前 `ARFrame` 动态读取

---

## 2. 视图结构

### 2.1 页面层级

```
NavigationStack
└── DeviceSettingsView (设备)
    ├── Section: 校准 (Calibration) [可展开/折叠]
    │   ├── NavigationLink → SensorCalibrationView (传感器矫正)
    │   └── NavigationLink → CameraCalibrationSettingsView (矫正相机设置)
    │
    └── Section: 分辨和帧率 (Resolution and Frame Rate) [可展开/折叠]
        ├── SettingRow: 分辨率 (Resolution) → 展示当前值，点击弹出 Picker
        └── SettingRow: 帧率 (Frame Rate) → 展示当前值，点击弹出 Picker
```

### 2.2 新增视图文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `DeviceSettingsView.swift` | View | 设备设置主视图，包含两个可折叠 Section |
| `SensorCalibrationView.swift` | View | 陀螺仪/加速计校准界面（跳转自校准 Section） |
| `CameraCalibrationSettingsView.swift` | View | 分辨率和帧率设置界面 |

### 2.3 复用组件

以下现有组件可直接复用：

- `SettingsSection(title:)` — 分组容器
- `SettingsToggle(...)` — 开关行
- `SettingsNavRow(...)` — 导航行
- `SettingsRow(...)` — 带 Slider 的行

---

## 3. 功能说明

### 3.1 校准 (Calibration) Section

#### 3.1.1 传感器矫正 (Sensor Calibration)

**功能**：对设备的陀螺仪和加速计进行校准，确保扫描过程中的姿态测量准确。

**用户流程**：
1. 用户点击"传感器矫正"行
2. 导航至 `SensorCalibrationView`
3. 显示校准引导 UI（等待设备稳定、画 8 字等标准动作）
4. 校准完成后标记 `sensorCalibrationDone = true`

**持久化**：
- UserDefaults key: `sensorCalibrationDone` (Bool, 默认 false)

**注意**：现有 `CalibrationView.swift` 是**算法校准**（聚类参数调整），与传感器校准不同。本设置项不导航至现有 `CalibrationView`。

#### 3.1.2 矫正相机设置 (Camera Calibration Settings)

**功能**：配置 AR 相机的分辨率和帧率参数，用于点云采集。

**用户流程**：
1. 用户点击"矫正相机设置"行
2. 导航至 `CameraCalibrationSettingsView`
3. 显示分辨率和帧率选择器
4. 选择后自动保存至 UserDefaults

**持久化**：
- `cameraCalibrationResolution` (String, 默认 "1080p", 值: "720p" | "1080p" | "4K")
- `cameraCalibrationFPS` (String, 默认 "60", 值: "30" | "60" | "120")

**注意**：
- ARKit 的 `ARWorldTrackingConfiguration` 不直接支持设置视频分辨率和帧率
- 实际分辨率由系统根据设备能力自动选择
- 此设置作为**用户偏好记录**，UI 可供用户选择，但实际效果受硬件限制

### 3.2 分辨率和帧率 (Resolution and Frame Rate) Section

#### 3.2.1 分辨率 (Resolution)

**选项**：
- 720p (1280 x 720)
- 1080p (1920 x 1080) — 默认
- 4K (3840 x 2160)

**UI 组件**：Picker (菜单样式)，点击后在下拉菜单中选择

#### 3.2.2 帧率 (Frame Rate)

**选项**：
- 30fps — 默认
- 60fps
- 120fps (仅 Pro 设备支持)

**UI 组件**：Picker (菜单样式)，点击后在下拉菜单中选择

**注意**：
- 120fps 选项应在非 Pro iPhone 上灰显
- ARKit 实际帧率由系统决定，此设置仅记录用户偏好

---

## 4. 展开/折叠行为

使用 SwiftUI `@State` 跟踪展开状态，动画使用 `easeInOut(duration: 0.2)`。

展开/折叠状态**不持久化**——每次进入设置页面默认为展开状态。

---

## 5. 数据持久化

### 5.1 UserDefaults Keys

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `sensorCalibrationDone` | `Bool` | `false` | 传感器校准是否完成 |
| `cameraCalibrationResolution` | `String` | `"1080p"` | 用户偏好的相机分辨率 |
| `cameraCalibrationFPS` | `String` | `"60"` | 用户偏好的帧率 |

### 5.2 SettingsStore 扩展

在 `SettingsStore.swift` 的 `Keys` 枚举中添加 3 个新 key，对应添加 3 个属性。

---

## 6. UI 布局

- **背景色**：`Design.Colors.bgBase` (#FAF8F5)
- **Section 背景**：`Design.Colors.bgSurface` (白色)
- **Section 圆角**：`Design.Radius.large` (16pt)
- **Section 间距**：`Design.Space.lg` (24pt)
- **Section 内边距**：`Design.Space.md` (16pt)
- **文字颜色**：标题 `Design.Colors.charcoal`，副标题 `Design.Colors.slate`
- **图标颜色**：`Design.Colors.forest` (#3D6B5C)
- **导航箭头**：`Design.Colors.pebble` (#C8C5C0)

---

## 7. 实现检查清单

- [ ] 在 `SettingsStore.Keys` 中添加 3 个新 key
- [ ] 在 `SettingsStore` 中添加 3 个新属性
- [ ] 创建 `DeviceSettingsView.swift`
- [ ] 创建 `SensorCalibrationView.swift`
- [ ] 创建 `CameraCalibrationSettingsView.swift`
- [ ] 在 `SettingsView.deviceSection` 中替换为 `DeviceSettingsView`
- [ ] 验证展开/折叠动画流畅
- [ ] 验证 Picker 交互正常
- [ ] 验证 UserDefaults 持久化正确
