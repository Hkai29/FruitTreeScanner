# FruitTreeScanner 界面设计系统（MiniMax Code 主导）

> 本文件是本次原生前端重建的唯一视觉依据。所有页面必须使用同一套令牌与组件，
> 不得引入新的色相、新的圆角语义、装饰性渐变或带插图的磁贴。
>
> 实现位置：`FruitTreeScanner/Design/`。可读性下限由
> `FruitTreeScannerTests/DesignSystemContrastTests.swift` 强制。

---

## 0. 竞品研究：真正采用与舍弃的细节

不是"高级/克制"这类形容词，而是从具体成品界面里挑出来的可执行条目。

### 0.1 Things 3（culturedcode.com/things/features/）

官方在改版说明里反复描述的界面特征：

| 原话 | 我的处理 |
| --- | --- |
| "it smoothly transforms into a clear white piece of paper"（打开待办后变成一张白纸） | **采用**：详情在原位展开，列表本身保持安静。点云视口、结果页都是"同一页里换内容"，不跳到新卡片堆。 |
| "those fields are neatly tucked away in the corner until you need them"（次要字段收起，用到才出现） | **采用**：首页第一屏只留必要读数（今日产量、扫描数、树体数）；树号、冠幅、文件大小等进入详情页才出现。档案行保留一行元数据，其余折叠。 |
| "The events are neatly grouped at the top of their Today list. With your to-dos below, your whole day is laid out before you." | **采用**：按**类别**分组，而不是一条扁平长列表。果园空间按"数字 → 证据 → 空间 → 工具"分层，档案按地块/标签/状态分组。 |
| "Headings"作为一级结构，可拖拽重排 | **采用（受限）**：分区标签就是我们的 heading 层，工具分组可整体收起。 |
| "Progress Pies — See the progress of your projects at a glance" | **舍弃**：进度环在本产品里会暗示"完成度"，而覆盖度是**质量**不是进度。改用分段电平表（InstrumentMeter），不做环形进度。 |
| "Slim Mode — collapse your sidebar to cut out distractions" | **采用**：底部动作带只在果园空间出现，档案/分析页不占用底部，减少干扰。 |
| "It never feels messy or overbearing, no matter the length of your list" | **采用**：列表行高与字号在全应用固定，不随内容长度变化。 |

### 0.2 Polycam（poly.cam，App Store 描述与第三方实测）

| 原话 / 事实 | 我的处理 |
| --- | --- |
| 先选捕捉模式（空间 / 物体 / 平面图 / 航拍），再进入带引导的取景器 | **采用**：采集方式是一等入口（新建扫描 / 快速采集），引导页用编号步骤而非图片说明。 |
| 捕捉后立即给出 3D 预览 + 分享/编辑选项 | **采用**：点云是主视觉，读数条与工具条浮在视口上，而不是把点云缩成一张缩略图卡片。 |
| 设备端工具：裁切、旋转、重设比例、**量测** | **采用**：量测是视口内的一种模式（MeasurementToolOverlay），不是设置项。 |
| 导出 .obj/.fbx/.stl + 彩色点云 .dxf/.ply | **采用**：点云是一等交付物，导出入口在读数条上。 |
| 平面图测量与卷尺误差 2cm 以内；"accuracy over visual effects" | **采用**：点云视口不加任何装饰性着色/辉光；颜色只来自真实 PLY 或真实高度/密度着色。 |

### 0.3 中文高密度数据排版（东方财富 / 同花顺 / 雪球 的版式研究）

来源：站酷《信息获取与适老化系统体验升级——信息获取：以证券交易为例的信息展示优化》，
研究对象为同花顺、东方财富、雪球、牛牛、腾讯自选股等。

| 结论 | 我的处理 |
| --- | --- |
| "iOS 端文字基本以苹方为主，**数字字体以 din 为多数**" | **采用**：中文正文用系统字（苹方），**所有数字用等宽数字字形**（`.monospacedDigit()` / SF Mono），数字与正文是两个字面体系。 |
| "固定盒子间距，盒子宽度根据字段调整" | **采用（修正实现）**：读数条各列宽度固定，但**数值在列内右对齐**，小数点成列；不同字段宽度不同（产量比计数宽）。 |
| "第一屏内仅展示最新价和涨跌幅即可" | **采用**：首页第一屏只给今日产量 + 两个辅助计数，其余进详情。 |
| "在涨跌幅处用色块做视觉吸引" | **采用（换形）**：不画色块，改用**证据等级竖栏**（实线/虚线/点线/空心）——同样把最强视觉权重给最关键的那个数字，但线型能表达可靠度。 |
| 字号 34、行高 104 经盲测选定；行高与字号全列表统一 | **采用**：行高与字号是全应用固定量级，不随内容伸缩；触达目标 ≥44pt。 |
| 中文正文行距 1.50–1.70，"垂直韵律"= 所有纵向间距是同一基数 a 的整数倍 | **采用**：间距基数 4pt，所有纵向留白都是 4 的倍数；长文正文（帮助页、说明段）显式设置 1.5 倍行距。 |
| WCAG：正文 4.5:1、大字 3:1 | **采用**：写进回归测试。 |
| "避免使用蓝色和紫色"（老年用户对蓝/紫的辨识下降更明显） | **采用**：主色不是蓝也不是紫，而是**信号青 #0E6B78**——偏绿一侧、明度接近绿，兼顾可辨识与仪器感。钢蓝只用于中性信息，从不作为主操作或状态色。 |

### 0.4 雪球 12.0（作为反例明确舍弃）

雪球的改版策略是："加大字号和内容间距、删减掉不必要的信息、**调大卡片圆角**"，
并把主色饱和度与亮度提高，追求"年轻、活泼、亲和力"。

**舍弃圆角与高饱和两点。** 理由：雪球是消费级社交产品，亲和力是目标；本产品是
戴手套、单手、日光下的野外测量仪器，需要的是**精确感而不是亲和感**。
因此本系统的圆角压在 6/10/12（控件/卡片/面板），主色只有一种低饱和信号青，
不给卡片加投影，靠发丝线和明度差分层。

**舍弃"高饱和主色"这一点。** 饱和色块在日光下会降低文字对比度，而本产品大量
读数必须在强光下可读。所有正文级颜色都被回归测试锁定在 4.5:1 以上。

### 0.5 本次研究带来的三处结构性修改（不是换色）

1. **结果页：可靠性等级排在估产数字之前。** 依据"第一屏只给最关键的那个数"与
   "最强视觉权重给关键值"。先看到"这条结论能不能用"，再看到"是多少"。
2. **首页有数据态：点云成为主视觉。** 依据 Things 的"一张白纸"与 Polycam 的
   "捕捉后立即给出 3D 预览"。首页不再是统计条 + 地图 + 工具列表的设置页结构，
   而是"数字 → 这棵树的证据 → 空间位置 → 工具"。
3. **首页无数据态：测绘网格空板 + 一句下一步。** 依据"删减掉不必要的信息"与
   "0 干扰"。空状态不画不存在的图表，只说明现在有什么、下一步做什么。

---

## 1. 产品本质与不可越界的边界

这是**果园三维测量仪器**，不是照片识别 App，也不是通用数据看板。

三条真实主线：果园档案（果园→地块→树→季节→扫描）、点云证据（ARKit 位姿 +
LiDAR 深度 + Metal 点云 + CoreML 检测 + 2D→3D 投影/融合验证）、估产与诊断。

### 绝对禁止

- 禁止把 `.fused` 之外的证据显示成"可靠""已确认"。
- 禁止删除或弱化 `zeroYieldReasons`、扫描诊断、置信度诊断、debug 状态。
- 禁止修改扫描/融合/估产算法、阈值、生命周期、持久化与导出逻辑。
- 禁止在没有记录支撑的地方画曲线、地图点、覆盖率环或插画。
- 禁止装饰性渐变、发光、玻璃拟态、彩色胶囊徽章。
- 禁止用 `imageOnly`/`cloudOnly`/被拒证据参与可靠估产统计。
- 禁止为界面好看而改动后端存储格式。

### 来源标注（2026-10-19 修正）

`ScanFileRecord.requiresSourceValidation` 是**导出前重新校验**用的标记
（`ScanRepository.makeSummary` 对所有实际档案都置 true），**与采集来源无关**，
因此不得用于推断"设备实采 / 导入"。

界面只陈述可证实的事实：

| 状态 | 标签 | 依据 |
| --- | --- | --- |
| `archivedScan` | 已存档点云 | 档案中存在该记录，且结果文件已保存 |
| `archivedWithoutResult` | 已存档点云 · 无结果文件 | 档案中存在该记录，但没有可核验的结果 |
| `externalFile` | 外部 PLY 文件 | 档案中没有对应记录 |

**不使用"设备实采"字样**，因为 App 内没有可证实的采集来源字段。

### 评审证据的边界（2026-10-20 补充）

界面评审用的那批截图里，**所有读数都是合成的**：产量、果数、树高、范围、日期与 GPS 坐标
都来自评审夹具（合成 PLY + 合成归档记录），**不是现场测量**。真实的是组件、Store、
解析与聚合逻辑本身。因此：

- 截图证明的是**原生布局与交互形态**，不等于 App 端到端导航已在真机跑通；
- `PointCloudBounds` 是点云的**外接包围盒**，不是实测冠幅——界面与画布都不得写成"冠幅"；
- 模拟器没有地理底图瓦片，果园地图只能证明点位与面板结构，不能证明底图渲染；
- 真机 LiDAR / ARKit 采集与 iOS 16 兼容环境按要求继续暂缓。

---

## 2. 颜色语义（严格，2026-10-19 按实测对比度修正）

浅色工作区（`Design.Colors.Workspace`）：

| 令牌 | 值 | 职责 | 白底对比 | 纸底对比 |
| --- | --- | --- | --- | --- |
| `background` | `#F4F3EF` | 纸面页底 | — | — |
| `surface` | `#FFFFFF` | 承载面 | — | — |
| `surfaceQuiet` | `#FAF9F6` | 行内次级块 | — | — |
| `inset` | `#EDEBE5` | 凹陷区、输入框底 | — | — |
| `line` | `#DFDDD6` | 1px 发丝线 | — | — |
| `lineSoft` | `#EAE8E2` | 更弱分隔 | — | — |
| `lineStrong` | `#C9C6BC` | 强分隔 | — | — |
| `ink` | `#151A1C` | 主要文字 | 17.55 | 15.81 |
| `secondary` | `#4C565B` | 次要文字 | 7.53 | 6.78 |
| `muted` | `#5E6A70` | 三级文字（日期、单位） | 5.57 | 5.01 |
| `faint` | `#7E888D` | **仅装饰**（箭头、图标） | 3.62 | 3.26 |
| `accent` | `#0E6B78` | 信号青：操作、选中、进行中 | 6.19 | 5.57 |
| `accentSoft` | `#E4F0F1` | 信号青浅底 | — | — |
| `attention` | `#8F5B0E` | 琥珀：待复核、警告 | 5.72 | 5.15 |
| `attentionSoft` | `#F8EFDC` | 琥珀浅底 | — | — |
| `failure` | `#A3382A` | 锈红：失败、不可用、被拒 | 6.65 | 5.99 |
| `failureSoft` | `#F8E8E5` | 锈红浅底 | — | — |
| `reliable` | `#2C6A46` | 深绿：**可靠融合**（仅结果页） | 6.45 | 5.81 |
| `reliableSoft` | `#E5F0E8` | 深绿浅底 | — | — |
| `information` | `#3F5B70` | 钢蓝：中性信息 | 7.14 | 6.43 |

深色画布（`Design.Colors.Dark`）：`bgDeep #0E1214`、`bgSurface #161B1E`、
`bgElevated #1E2529`、`controlSurface #1B2225`、`glassBorder #2C3438`、
`glow`/`lidar` `#17B2C4`、`textPrimary #F0F3F3`、`textSecondary #9EA9AC`、
`textMuted #829095`（深底 5.27）、`success #6FC08C`、`warning #E0A94A`、
`error #E58B7B`、`info #8FB6CC`。

**修正记录**（实测反馈：muted 在纸底仅 3.42，attention 仅 4.03）：

| 令牌 | 原值 | 新值 | 原因 |
| --- | --- | --- | --- |
| `muted` | `#79858A` | `#5E6A70` | 日期、单位、状态等正文级小字必须 ≥4.5:1 |
| `attention` | `#A66A12` | `#8F5B0E` | 复核状态文字必须 ≥4.5:1 |
| `faint` | `#A6AFB3` | `#7E888D` | 降为装饰专用；文字用法全部改到 `muted` |
| `Dark.textMuted` | `#6E7A7E` | `#829095` | HUD 小标签在深底需 ≥4.5:1 |
| `Design.Colors.harvest` / `.warning` | `#A66A12` | `#8F5B0E` | 旧别名与新语义保持同色 |

回归测试：`FruitTreeScannerTests/DesignSystemContrastTests.swift`（6 项，
覆盖浅色/深色/实心按钮/旧别名一致性）。

---

## 3. 排版

- 标题：`title2/title3` + `.semibold`。
- 小标签：`instrumentLabel()`（caption2 semibold + 字距 0.6 + 次级墨色）。
- 正文：`.body` / `.subheadline` / `.footnote` 语义字样，**必须支持动态字号**。
- 数字：`.monospacedDigit()`，等宽对齐；标识符用 `.system(_:design: .monospaced)`。
- 长文正文（帮助页、说明段）显式 1.5 倍行距（中文行距 1.50–1.70 的结论）。
- 禁止写死 `Font.system(size:)`（深色 HUD 的 `hudLabel/hudValue` 除外）。

## 4. 形状与层级

- 圆角：控件 6、卡片 10、面板 12、sheet 16。**不用大圆角**（见 0.4）。
- **浅色层级不用投影**，用发丝线 + 背景明度差表达。
- 卡片只用于"一个具体对象"（一条记录、一棵树、一个工具面板）；
  分组用小标签 + 发丝线，不要给每个分区套白卡。
- 页面左右边距 20pt，内容最大宽度 1080pt（iPad 居中）。

## 5. 组件清单

- `InstrumentComponents.swift`
  `InstrumentSectionLabel` `InstrumentPanel` `InstrumentDarkPanel`
  `InstrumentDatum` `InstrumentInlineDatum` `InstrumentMeter` `InstrumentMeterRow`
  `InstrumentIdentifier` `InstrumentTierMark` `InstrumentTierRail` `InstrumentTierBadge`
  `InstrumentRow` `InstrumentRowGroup` `InstrumentChevron` `InstrumentEmptyState`
  `InstrumentStatStrip` `InstrumentToolButton` `InstrumentSegmented`
  `InstrumentExtentDiagram` `InstrumentPageHeader`
- `InstrumentRecords.swift`
  `InstrumentScanRow` `InstrumentSurveyPlate` `InstrumentToolCell`
- `InstrumentCharts.swift`
  `InstrumentTrendChart` `InstrumentBarChart`
- `InstrumentForms.swift`
  `.instrumentListStyle()` `.instrumentSectionHeader(_:)` `InstrumentFormRow`
  `InstrumentTextField` `InstrumentChip` `InstrumentProgress` `InstrumentSheetHeader`
  `InstrumentNotice`
- `InstrumentEvidence.swift`
  `InstrumentEvidenceTier`（结果页，来自 `ResultReliabilityPresentation`）
  `InstrumentRecordTier` / `InstrumentRecord.tier(for:)`（档案记录）

按钮样式：`WorkspacePrimaryButtonStyle` `WorkspaceSecondaryButtonStyle`
`WorkspaceQuietButtonStyle` `ScaleButtonStyle`。

### 尺度示意（2026-10-19 修正）

`InstrumentExtentDiagram` 取代了原先的 `CanopyProfileGlyph`。

- **舍弃**：用通用椭圆当"树形剪影"。它既不是实测轮廓，也通过夹取宽高比再乘 2
  破坏了真实比例。
- **采用**：按**统一比例**画出被测量的**外接范围**（AABB）矩形 + 同一比例下的
  比例尺。矩形长宽比就是真实宽高比，比例尺可与矩形对照读数。
- **注意**：`PointCloudBounds` 是整份点云的 AABB，**不等于**分割后的冠层尺寸。
  因此界面上只说"点云范围"，不说"冠层"。

## 6. 证据等级的画法

**结果页**用 `ResultReliabilityPresentation`（真实 `.fused` 诊断）：

| 等级 | 线型 | 颜色 |
| --- | --- | --- |
| reliable | 实线 | `reliable` 深绿 |
| review | 虚线 | `attention` 琥珀 |
| unreliable | 点线 | `failure` 锈红 |
| noReliableEstimate | 空心 | `failure` 锈红 |

**档案记录**只有 confidence 与落盘状态，没有 `.fused` 诊断，
因此 `InstrumentRecord.tier(for:)` 只给出 `.complete`（实线/中性）、
`.review`（虚线/琥珀）、`.damaged`（点线/锈红）。
复核判定复用 `ResultReviewPolicy.needsReview`，不另立标准。
**不要**在档案记录上写"可靠融合"。

## 7. 页面骨架

- 浅色页：`.workspacePage()`。
- 主操作：底部动作带，每屏最多一个主操作（信号青实心）。
- 空状态：`InstrumentEmptyState` 或 `InstrumentSurveyPlate`。
- 工具列表：`DashboardToolGroup`（面板 + 发丝线分隔条目），不用带插图的磁贴。
- **密排列表行**（扫描档案行）：行内动作一律用**文字动作**——图标 + 文字，
  无填充、无描边；两个动作之间用发丝线分隔，菜单为纯图标。
  命中区仍不小于 44pt（视觉可更轻，命中不可更小）。
  理由：档案页是读数列表，整块描边白按钮会让页面被成排的按钮压住，
  读数反而退成背景。状态色只落在图标上，文字保持墨色。

## 8. 深色采集与点云页

- 采集画布与点云视口保持深色，与浅色页共享字形与状态语义。
- HUD 用 `Design.Colors.Dark`，标签 `hudLabel`，值 `hudValue`。
- 点云几何用 `Design.Colors.Dark.lidar`。
- 深色画布上的**实心按钮一律"亮底 + 墨字"**（信号青、浅锈红都是亮色底，
  文字用 `Dark.bgDeep`）。浅锈红 `#E58B7B` 配白字只有 2.6:1，达不到 AA；
  这一点由 `DesignSystemContrastTests.testDarkFilledButtonsUseInkOnLightFill` 守住。
- 模拟器没有真实 LiDAR：展示点云时必须标注来源（见 1. 来源标注），
  不得把样例说成实扫。

## 9. 触达区域（野外可操作性）

戴手套、单手、日光下操作，因此：

- 触达区域**实际不小于 44×44pt**。视觉尺寸可以更小，但命中区域不能更小。
- 做法：视觉件保持原尺寸（筛选片 32pt、输入框 44pt、工具按钮 44×44），
  在视觉件之外补足透明命中区，并把 `contentShape` 放在补足之后。
- 由 `FruitTreeScannerUITests/DesignReviewGalleryTests.testVerifyTouchTargets`
  实际测量控件 frame 来核验，不靠肉眼判断。

## 10. 品牌与图标

- 应用图标与启动图标是**点云树**：树干与树冠由离散点构成，信号青 + 琥珀树干，
  底部一条比例尺。它描述的是本产品测量树体的方式，而不是一棵卡通果树。
- 启动故事板（`LaunchScreenV2.storyboard`）与 SwiftUI 启动页使用同一套语言：
  深色仪器底 + 淡测绘网格 + 系统字体半粗的产品名 + 小字副标题。
  不使用斜体渐变文字、果实插画或绿色顶底色带。
- 生成脚本：`tools/generate_app_icon.py`（确定性输出，可复现）。

## 11. 验收流程（脚本化，可复现）

| 脚本 | 作用 |
| --- | --- |
| `tools/seed_ui_review_fixtures.py` | 在模拟器里生成**合成**扫描档案（带真实 GPS、树号、时间、产量）。文件头带 `not_app_lidar_or_yield_evidence`，不是实机采集。原有档案只会被移开，不会被删除。 |
| `tools/run_design_gallery.py` | 四个 pass（populated / empty / largetype / previews）分别跑 UI 测试，保留各自的结果包与截图目录；跑前记录并跑后**还原**真实的字号与真实档案。 |
| `tools/extract_gallery_screenshots.py` | 用 `xcresulttool export attachments` + manifest 按附件名取图，缺任何一项都算失败。 |
| `tools/build_design_canvas.py` | 先枚举**全部**必需截图，缺任何一张（包括整页缺失）都 exit 1，并只写 `*.incomplete.html` 作为草稿。 |
| `tools/check_localization.py` | 校验每个 `NSLocalizedString` 键在 en/zh 都有条目，缺一即 exit 1。 |
| `tools/generate_app_icon.py` | 确定性生成点云树图标。 |
| `tools/add_xcode_sources.py` | 往 pbxproj 里安全地登记新源文件（不破坏既有条目）。 |

截图工作流的三条硬规则：

1. 触发元素必须是**真实控件**，用代码里真实存在的 identifier 定位。
2. 截图前必须**确认页面真实内容已出现**（导航栏标题 / 可见正文 / 真实控件），
   不用"按钮还在不在"代替页面确认。
3. 任何一次确认失败都让测试失败，不静默跳过，也不把同一页当成多页。

**画面落定（2026-10-20 补）**：AX 元素存在不等于画面已经稳定——入场动画、转场叠影、
半透明淡入都会让像素继续变化。因此每张截图前都要求**连续两帧像素完全一致**
（`waitForStableRender`），并且：

- 建档向导每一步同时断言**步序标签**（第 N 步，共 5 步）与**本步专属标题**，
  只等标题出现会拍到上一步；
- 校准页等"正在读取校准记录"消失再拍，拍的是加载完成的真实内容；
- 结果页三态用**枚举**传参（字符串 `rawValue` 不匹配会静默退回"可靠"），
  并断言各态专属正文：可靠摘要、保存恢复面板、零估产理由；
- 同标签控件必须唯一：转场快照里残留的旧控件会让操作打到不存在的视图上。

**点云取景（2026-10-20 补）**：初始视角必须把整团点云收进**没有被 HUD 遮住**的画面。
取景按相机真实基向量把居中后的 8 个角点逐个做视锥校验（视口宽高比、FOV、轨道旋转、
近端深度、HUD 上下留白一起算）；`SCNCamera.projectionDirection` 默认 `.vertical`，
`orthographicScale` 按纵向定义，可见宽度 = scale × 视口宽高比。
`FruitTreeScannerTests/PointCloudFramingTests` 用 `SCNView.projectPoint` 做真实投影断言
（窄竖屏 / 高屏 / 横屏 / 平板 × 自由 / 正面 / 俯视 / 侧面），比复述公式更能证明没裁切。

## 12. 本轮明确的取舍

| 取舍 | 决定 | 理由 |
| --- | --- | --- |
| 今日概览是否在无记录时隐藏 | **始终显示**，读数为真实的 0 | "今天还没扫" 是信息，"没有这个板块"不是 |
| 校准页的误差统计 | **始终显示**，无记录时区块内给出说明 | 同上；隐藏会让用户以为功能不存在 |
| 校准页页尾 | 增加一段真实说明（实测数据从哪来、用来做什么） | 页面必须自带说明；也让页面在短内容下仍可滚动 |
| 采集 HUD / 结果页在模拟器无法到达 | 提供 **DEBUG 设计评审预览**（`tools/generate_app_icon.py` 同级的 `-designReviewHUD` / `-designReviewResult` 启动参数） | 评审要看到真实排版；预览在画面上明确标注"合成数据，非实机采集" |
| 浅色层级 | 不用投影 | 投影是消费级 App 的语言；仪器靠发丝线与明度差分层 |
| 圆角 | 6 / 10 / 12 | 与雪球"调大圆角"的做法相反（见 0.4） |
| 点云树形示意 | **不做** | `PointCloudBounds` 是整份点云 AABB，不是分割后的冠层；用通用椭圆冒充实测树冠会造假 |
| 点云来源 | 只写"已存档点云 / 已存档点云·无结果文件 / 外部 PLY 文件" | `requiresSourceValidation` 是导出前重新校验标记，与采集来源无关 |

## 13. 适配

- 动态字号：`@Environment(\.dynamicTypeSize)`；`isAccessibilitySize` 时改为竖排、
  允许换行、去掉固定宽度。
- 横屏：`verticalSizeClass == .compact` 时主操作移入滚动区或改为竖排。
- iPad：内容最大宽度 1080 居中；宽屏（≥780）用两栏。
- 触控目标 ≥ 44×44。
