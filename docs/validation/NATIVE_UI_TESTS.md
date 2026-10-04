# 原生确认框验证

`FruitTreeScannerUITests` 使用 XCTest 的真实触摸，验证品种参数重置确认的取消、重置、保留其他品类及重新启动后的持久化。它与默认单元测试 scheme 分开，避免在已有模拟器上写入默认偏好。

在仓库根目录运行：

```sh
python3 tools/validate_native_ui.py --output-root /private/tmp
python3 -B -m unittest discover -s tools/tests -p test_validate_native_ui.py
```

验证入口新建独立 iOS 模拟器，向测试进程传入其 UUID。测试在启动应用前核对 UUID 与专用设备名；直接运行 scheme 而缺少该凭证会失败。退出时仅关闭并删除本次创建的设备，不重置已有设备。运行期间保持源码不变。

证据目录保存命令退出码、日志、`.xcresult`、summary、结果树和源码快照。通过必须满足退出 0、明确的通过数、零失败/跳过/expected failure、关键方法所属测试类及 target 完全匹配、设备清理成功和源码不变。失败结果包也必须留存并解析。

检查结果包中的取消确认框、重置后重开及重启截图。标准偏好的根所有权、独立根草稿保存和已捕获 ScanPlan 的冻结由 `DashboardSummaryTests` 验证；原生测试不代替这些单元回归，也不证明 LiDAR 质量或真实估产精度。
