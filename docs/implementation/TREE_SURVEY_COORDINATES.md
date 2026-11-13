# 单树测量坐标与 1 米目标

入口：档案页 → 地块与标签 → 单树定位。导入前先备份测量文件。此模块维护按树号索引的树干基部坐标，独立于扫描时手机 GPS、PLY 原始点云和估产结果。

## 定位语义

- 扫描时手机坐标只是参考位置，不等于树干位置。现有 GPS 接纳策略最大报告误差为 8 米，本模块没有修改它。
- 同一树号的测量点优先用于果园地图。没有测量点时保留原手机参考坐标；未扫描树木也可在树位档案中查看并启动扫描。
- 地图误差圈采用导入文件报告的水平误差半径。RTK 固定解或全站仪且报告半径 ≤1 米，显示达到输入目标；这不是现场精度验收通过。
- 不按最近 GPS 点自动确定树号。使用者先核对树号，再从测量点启动同一树号的扫描。
- ARKit/LiDAR 的局部坐标不能直接视为同等精度的全球经纬度。本轮未实现自动树干提取、控制点配准或外置接收机的实时通讯协议。

Apple 将 `horizontalAccuracy` 定义为以米表示的位置不确定半径，`kCLLocationAccuracyBest` 仅请求可获得的最佳精度，不承诺 1 米。[Apple 定义](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)、[最佳精度请求](https://developer.apple.com/documentation/corelocation/kcllocationaccuracybest)、[世界跟踪误差](https://developer.apple.com/documentation/arkit/understanding-world-tracking)。RTK 是使用差分与载波相位的独立测量方案，其条件与普通手机定位不同：[ESA RTK Fundamentals](https://gssc.esa.int/navipedia/index.php/RTK_Fundamentals)。

## 文件约定

WGS84 GeoJSON FeatureCollection，每棵树一个 Point，坐标顺序 `[经度, 纬度]`，纬度在 -85～85 度之间。拒绝声明其他 CRS 的输入；GCJ-02、BD-09 和本地投影数据应在测量端正确转换后导入，不可只改字段名。

必填 properties：

| 字段 | 含义 |
|---|---|
| tree_id | 稳定树号，遵循现有 TreeIdentifierPolicy，最多 64 字符；导入整批不允许重复 |
| position_source | `rtk_fixed`、`total_station`、`rtk_float` 或 `device_gps` |
| horizontal_accuracy_m | 测量端报告的水平不确定半径，单位米，必须大于 0；不是小数位数 |
| measured_at | ISO 8601 测量时间，保留原始时间字符串 |
| reference | 必须为 `trunk_base`，即树干基部测量点 |
| source_note | 1～160 字，记录设备、测站或测量文件来源 |

支持 1～5000 点、文件不超过 2 MB；合并后的总档案同样受限。导入先预览，更新已有树号必须勾选确认。任意一条无效则整批不写入。保存成功后才更新内存；失败保留之前的内存与文件。主档为 App Documents 下 `TreeSurvey/positions.geojson`，采用原子替换。

原档损坏时停止覆盖，保留原字节；当前页面还没有恢复损坏原档的入口，需从备份或设备容器恢复。导出适用于正常读取的树位档案。

## 验收边界

单元测试和 iPhone Pro 模拟器证明解析、保存、树号关联及界面流程，不能证明现场 1 米定位。后续需用独立测量的树干控制点，对开放天空、冠层遮挡、不同日期复扫分别记录水平误差、误差分布和认错树情况；同时记录定位方法、报告半径与有效解状态。在此验收前不得宣传“已实现 1 米精度”。用户此前暂缓的真机验收保持暂缓，iOS 16 实际运行也保持未验收。
