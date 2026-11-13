#!/usr/bin/env python3
"""Build the local, interactive, page-by-page design canvas.

Reads a directory of native screenshots and emits one self-contained HTML file
that explains the rebuilt design page by page: the native render, what changed
and why, which design-system components were used, and where the data behind
each screen comes from.

Screenshots are embedded as base64 so the canvas is a single portable file.

Usage:
    python3 tools/build_design_canvas.py \
        --screenshots <dir> --output <path.html> [--title "..."]
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import mimetypes
import sys
from pathlib import Path

# ---------------------------------------------------------------- page model

PAGES = [
    {
        "id": "workspace",
        "group": "工作台",
        "title": "果园空间 / 档案 / 分析",
        "subtitle": "三个工作区共用一套骨架：产品身份 → 分区标签 → 承载面 → 底部动作带",
        "shots": [("01-workspace-orchard", "果园空间"), ("02-workspace-archive", "档案"), ("03-workspace-analysis", "分析")],
        "notes": [
            "顶部只保留产品身份（果树扫描 / ORCHARD LIDAR SCANNER）与两个工具入口；内容用小标签分区，不再出现标题套标题。",
            "页面底是暖中性纸面 #F4F3EF，承载面为纯白 + 1px 发丝线。浅色层级完全不用投影。",
            "底部动作带承载页面唯一的主操作（新建扫描），信号青实心；快速采集为描边次操作。辅助大字号时两个动作改为竖排。",
            "三个分栏共用同一套分栏组件，选中项用 2pt 信号青指示线表达，不只靠变色。",
        ],
        "components": ["TopNavigationBar", "WorkspaceTabBar", "InstrumentSectionLabel", "InstrumentPanel", "InstrumentDatum", "DashboardToolGroup", "InstrumentSurveyPlate"],
        "data": "今日/累计读数是 ScanHistoryStore 对**评审夹具**（合成归档记录）的真实聚合算法结果，不是现场测量。「今日概览」只统计当天，每个指标都写明「今日」。无记录时显示测绘网格空板。",
    },
    {
        "id": "workspace-empty",
        "group": "工作台",
        "title": "空状态",
        "subtitle": "没有记录时不画任何不存在的图",
        "shots": [("24-workspace-empty", "果园空间 · 空"), ("25-archive-empty", "档案 · 空")],
        "notes": [
            "空状态用测绘网格空板：上半是淡网格，下半是干净的说明区，角标像图纸标记。",
            "只说明现在有什么、下一步做什么，不画空图表、不画示意地图。",
            "「档案」空状态与「果园空间」空状态是两种不同的文案，不合并。",
        ],
        "components": ["InstrumentSurveyPlate", "InstrumentEmptyState"],
        "data": "真实的空档案状态（运行截图前把模拟器里的扫描记录移走，扫描原档一个没删）。",
    },
    {
        "id": "large-type",
        "group": "适配",
        "title": "辅助大字号",
        "subtitle": "同一套语言在 accessibility 字号下重新排布",
        "shots": [
            ("largetype-01-workspace-orchard", "果园空间 · 大字号"),
            ("largetype-03-workspace-analysis", "分析 · 大字号"),
        ],
        "notes": [
            "辅助大字号时读数改为竖排，面板标签与指标分行，不再横向挤压。",
            "主操作（新建扫描 / 快速采集）在辅助大字号下改为竖排，按钮文字不再被挤成两行；"
            "产品身份副标题在大字号下隐藏，避免截断成省略号。",
            "产品标识行与分区标签保持可见，触控目标不因字号而缩小。",
        ],
        "components": ["WorkspaceTabBar", "InstrumentPanel", "InstrumentDatum", "PointCloudTopBar"],
        "data": "评审夹具归档记录 + 模拟器 accessibility 字号（真实排版引擎，真实 Dynamic Type）。",
    },
    {
        "id": "adaptive",
        "group": "适配",
        "title": "横屏与平板",
        "subtitle": "同一套原生布局，在更扁、更宽的空间里重新排布",
        "shots": [
            ("landscape-01-workspace-orchard", "横屏 · 果园空间"),
            ("ipad-01-workspace-orchard", "平板竖屏 · 果园空间"),
        ],
        "notes": [
            "横屏与平板走的是同一份 SwiftUI 布局代码，差别只有可用空间与断点，不是另画一套。",
            "内容区有最大宽度上限：宽屏下读数不会无限拉伸，而是居中留白。",
            "这两张是**宿主窗口尺寸**下的布局验证：证明同一套 SwiftUI 布局在横屏/平板尺寸下会重新排布，"
            "**不宣称**真实 iPadOS 设备验收、也未在实体设备上验证。",
        ],
        "components": ["DashboardHomeLayoutView", "InstrumentPanel", "InstrumentDatum", "TopNavigationBar"],
        "data": "与工作台相同的评审夹具记录，只是窗口尺寸不同。",
    },
    {
        "id": "point-cloud",
        "group": "点云",
        "title": "点云视口",
        "subtitle": "深色仪器画布 + 真实解析读数 + 可证实的来源标注",
        "shots": [
            ("17-point-cloud", "点云视口"),
            ("30-point-cloud-tools", "点云工具"),
            ("31-point-cloud-measure", "点云测量"),
        ],
        "notes": [
            "顶部读数条给出真实解析出的点数、点云高度与**外接范围**（PointCloudBounds 是点云的包围盒，不是实测冠幅——冠幅需要真实冠层测量，这里不声称有）。数值使用等宽数字。",
            "来源标注只陈述可证实的事实：「已存档点云 / 已存档点云·无结果文件 / 外部 PLY 文件」。requiresSourceValidation 是导出前重新校验标记，与采集来源无关，因此不用于推断采集设备。",
            "左下角是按**统一比例**画出的点云外接范围示意 + 比例尺。它表达 AABB 范围，不是被假设的树形剪影。",
            "工具条、视角切换、颜色图例统一到深色仪器语言：信号青表示可执行，琥珀表示需要注意。",
        ],
        "components": ["PointCloudTopBar", "InstrumentExtentDiagram", "PointCloudProfileCard", "PointCloudToolsEntry", "PointCloudViewModePicker"],
        "data": "PLY 的解析、点数与包围盒都是真实计算结果；但这份 PLY 本身是为界面评审生成的合成样例，文件头带 not_app_lidar_or_yield_evidence 标记。原始点数据未被修改。",
    },
    {
        "id": "scan",
        "group": "采集",
        "title": "采集 HUD",
        "subtitle": "覆盖度是第一读数",
        "shots": [("20-scan-hud", "采集读数条与控制条")],
        "notes": [
            "顶部读数条把覆盖度放在第一位，并在同一列下方给出分段电平表——连续量交给电平表表达。",
            "覆盖度、果实数、质量、深度四个读数等宽对齐；质量与深度用状态点强化。",
            "底部控制条把工具行与主操作行分开，录制/结束用锈红与信号青区分。",
            "覆盖度面板的五个分项共用同一色相，颜色只承载整体状态，不再是彩虹色阶。",
        ],
        "components": ["ScanStatusBar", "InstrumentMeter", "ScanBottomControlBar", "CoverageMapView", "ScanGuidanceOverlay"],
        "data": "模拟器没有 ARKit 位姿与 LiDAR 深度，无法进入真实采集界面。此图是 DEBUG 下的**设计评审预览**：真实的 ScanStatusBar / ScanBottomControlBar / CoverageMapView 组件 + 一份合成读数快照，界面上有明确标注。",
    },
    {
        "id": "result",
        "group": "结果",
        "title": "结果与诊断",
        "subtitle": "可靠性等级用线型表达，诊断一条不少",
        "shots": [("21-result", "可靠融合"), ("22-result-review", "待复核"), ("23-result-no-estimate", "无可靠估产")],
        "notes": [
            "**可靠性先于产量**：先回答「这条结论能不能用」，再回答「是多少」。这是本轮研究带来的结构性修改，不是换色。",
            "可靠性等级来自 ResultReliabilityPresentation——判定逻辑与 .fused 证据结构是真的，数值是评审夹具。以竖栏线型表达：实线=可靠、虚线=待复核、点线=不可靠、空心=无可靠估产。",
            "只有结果页会出现深绿「可靠」，因为只有那里有融合诊断结构；档案记录不声称融合可靠性。",
            "zeroYieldReasons、关键质量读数与建议全部保留，没有为了好看而删减。保存失败时恢复面板与重试入口保持可达。",
        ],
        "components": ["ResultReliabilityPanel", "InstrumentTierRail", "InstrumentDatum", "InstrumentStatStrip", "ResultSectionCard", "InstrumentPanel"],
        "data": "同样是 DEBUG 下的设计评审预览：真实的 ResultView + 合成 YieldResult（含 .fused 诊断字段结构），三种可靠性状态各一张，三张图互不相同。",
    },
    {
        "id": "history",
        "group": "档案",
        "title": "扫描历史",
        "subtitle": "完整性语义必须完整可见",
        "shots": [("06-history", "扫描历史")],
        "notes": [
            "每行以证据等级竖线开头：实线=结果完整、虚线=需复核、点线=需恢复。颜色只做强化。",
            "完整性说明沿用既有文案（结果完整 / 待恢复 / 结果损坏），并保留具体的失败原因与「重扫」恢复入口。",
            "筛选用 InstrumentChip，搜索与筛选规则完全沿用既有实现。",
        ],
        "components": ["InstrumentScanRow", "InstrumentTierMark", "InstrumentTierBadge", "InstrumentChip", "InstrumentRowGroup"],
        "data": "记录来自 ScanHistoryStore；等级判定复用 ScanHistoryRecordPresentation 与既有的 ResultReviewPolicy。",
    },
    {
        "id": "calibration",
        "group": "工具",
        "title": "校准参数",
        "subtitle": "真实读取、真实统计、真实误差",
        "shots": [("04-calibration", "算法校准"), ("26-calibration-add", "添加校准记录")],
        "notes": [
            "校准记录与误差统计按 CalibrationRecordPersistence 的真实读取结果计算，不写死任何数值；没有足够记录时区块仍然显示并说明原因。",
            "面板用 InstrumentPanel + 发丝线分区，参数值用等宽数字并保留单位。",
        ],
        "components": ["InstrumentPanel", "InstrumentRowGroup", "InstrumentFormRow", "InstrumentTextField"],
        "data": "CalibrationRecord / FruitParametersStore 的真实值。",
    },
    {
        "id": "import",
        "group": "工具",
        "title": "导入点云",
        "subtitle": "单文件导入，真实失败原因",
        "shots": [("05-import", "导入文件")],
        "notes": [
            "保持既有单文件导入行为：一次一个 .ply，取消与错误生命周期不变。",
            "处理中只给出真实状态文字（正在处理 + 文件名）与不确定进度指示——导入过程没有可测量的完成度，因此不显示任何百分比。",
            "导入规则用发丝线分隔的列表，说明导入后会去哪里、元数据如何保留、同名如何处理。",
        ],
        "components": ["InstrumentPanel", "InstrumentNotice", "InstrumentRowGroup", "InstrumentSectionLabel"],
        "data": "PLYImportService 的真实校验与导入结果。",
    },
    {
        "id": "tag-management",
        "group": "档案",
        "title": "地块 / 标签 / 树木",
        "subtitle": "真实关系，不渲染档案里不存在的关系",
        "shots": [
            ("07-tag-management", "地块与标签"),
            ("27-plot-edit", "地块编辑表单"),
            ("28-tag-edit", "标签编辑表单"),
            ("29-tree-tagging", "树体归档 · 地块/标签/状态"),
        ],
        "notes": [
            "地块、标签与状态全部来自 TagStore，创建/编辑/取消门控保持不变。",
            "「树体归档」是**结果页里嵌入的快速归档组件**（QuickTaggingCard）：把这一棵树归到地块、挂上标签、标状态；它不是独立页面，评审时单独挂出来看排版。",
            "地块/标签编辑表单与快速归档组件用的是**完全隔离的** TagStore，评审不会写入或清空模拟器上的既有元数据。",
            "状态概览用读数条，条目用发丝线分隔的列表。",
        ],
        "components": ["InstrumentPanel", "InstrumentRowGroup", "InstrumentChip", "InstrumentFormRow"],
        "data": "TagStore 的真实读取结果。树体归档那张图为评审临时写入了一份地块/标签夹具，截完已清理。",
    },
    {
        "id": "batch-export",
        "group": "档案",
        "title": "批量导出",
        "subtitle": "真实记录选择、真实格式、真实进度与取消",
        "shots": [("08-batch-export", "批次导出")],
        "notes": [
            "记录选择与格式选项分区呈现，计数为真实选择结果。",
            "导出格式、进度、取消、失败恢复与分享入口保持原有行为，导出文件内容与格式未变。",
        ],
        "components": ["InstrumentSegmented", "InstrumentChip", "InstrumentProgress", "InstrumentRowGroup", "InstrumentStatStrip"],
        "data": "BatchExportService 在评审夹具记录上的真实选择与导出流程。",
    },
    {
        "id": "yield-report",
        "group": "分析",
        "title": "产量报告",
        "subtitle": "只画真实记录支撑的图形",
        "shots": [("09-yield-report", "产量报告")],
        "notes": [
            "汇总读数与条形图全部来自真实记录；没有记录支撑的曲线与插画一律不画。",
            "条形图用统一色相，长度按真实最大值归一。",
        ],
        "components": ["InstrumentBarChart", "InstrumentStatStrip", "InstrumentDatum", "InstrumentPanel"],
        "data": "YieldReportData / DashboardAggregationSnapshot 对评审夹具的真实汇总（算法真实，输入是合成记录）。",
    },
    {
        "id": "trends",
        "group": "分析",
        "title": "产量趋势",
        "subtitle": "按日聚合的真实趋势",
        "shots": [("10-trends", "产量趋势")],
        "notes": [
            "趋势图按真实扫描日期聚合作图，基线明确、坐标克制。",
            "端点读数使用等宽数字。",
        ],
        "components": ["InstrumentTrendChart", "InstrumentPanel", "InstrumentStatStrip"],
        "data": "TrendsData 对评审夹具记录的真实按日聚合。",
    },
    {
        "id": "compare",
        "group": "分析",
        "title": "树体对比",
        "subtitle": "同一套读数语言用于横向比较",
        "shots": [
            ("11-compare", "未选择记录"),
            ("11b-compare-selected", "已选两条记录 · 真实对比"),
        ],
        "notes": [
            "对比页沿用同一套读数与面板语言，差异用真实数值与等级线表达。",
        ],
        "components": ["InstrumentPanel", "InstrumentDatum", "InstrumentTierBadge", "InstrumentBarChart"],
        "data": "HistoricalCompareModels 对评审夹具记录的真实对比（空态与已选两条两条状态各一张）。",
    },
    {
        "id": "orchard-map",
        "group": "档案",
        "title": "果园地图",
        "subtitle": "只画带定位的树体",
        "shots": [("12-orchard-map", "果园地图")],
        "notes": [
            "地图上只出现有真实 GPS 的记录；没有定位的档案在列表中照常可见，并有明确的替代路径说明。",
            "选中标记用方角与描边表示，保持仪器语汇。",
        ],
        "components": ["OrchardMapView", "InstrumentPanel", "InstrumentStatStrip"],
        "data": "OrchardMapData 对评审夹具坐标的真实解析：底图与 6 个点位在本轮正常渲染，但坐标是合成的，不是任何真实果园的位置。",
    },
    {
        "id": "settings",
        "group": "设置",
        "title": "设置 / 品种",
        "subtitle": "分组 + 真实参数值 + 草稿-提交语义",
        "shots": [
            ("13-settings", "设置"),
            ("14-variety", "品种参数库"),
            ("15-variety-edit", "品种参数编辑（草稿—提交）"),
        ],
        "notes": [
            "设置使用原生 List 承载选择/开关/滑杆行为，外观统一为纸面 + 发丝线。",
            "所有参数值来自真实 Store，编辑仍是草稿-提交：取消丢弃、确认才落盘。",
            "品种参数库显示真实品种与真实参数，改过的参数有明确标记。",
        ],
        "components": ["GlassRow", "GlassToggleRow", "GlassSliderRow", "InstrumentSheetHeader", "InstrumentFormRow"],
        "data": "SettingsStore / FruitParametersStore / TagStore 的真实值。",
    },
    {
        "id": "help",
        "group": "设置",
        "title": "使用帮助",
        "subtitle": "可读的长文",
        "shots": [("16-help", "使用帮助")],
        "notes": [
            "长文使用 1.5 倍行距（中文行距 1.50–1.70 的研究结论），段落之间保持 4pt 基准的垂直韵律。",
            "章节标题使用仪器式小标签，正文保持安静的纸面。",
        ],
        "components": ["InstrumentRowGroup", "InstrumentSectionLabel"],
        "data": "无数据；为操作说明文本。",
    },
    {
        "id": "start",
        "group": "采集",
        "title": "建档与快速采集",
        "subtitle": "分步向导，编号即流程",
        "shots": [
            ("18-start-scan", "第 1 步 · 果树编号"),
            ("18b-start-plot", "第 2 步 · 地块归档"),
            ("18c-start-season", "第 3 步 · 估算阶段"),
            ("18d-start-tags", "第 4 步 · 标签分组"),
            ("18e-start-confirm", "第 5 步 · 启动前检查"),
            ("19-quick-scan", "快速采集"),
        ],
        "notes": [
            "步骤进度用编号与发丝线表达，返回与下一步的位置固定，每屏只有一个主操作。",
            "树号使用等宽输入，地块/季节/标签只列出档案中真实存在的选项。",
            "快速采集单独成页，明确说明它记录什么、不记录什么。",
        ],
        "components": ["InstrumentFormRow", "InstrumentTextField", "InstrumentChip", "InstrumentSegmented", "InstrumentPanel"],
        "data": "TagStore 的真实地块与标签；季节为真实枚举。",
    },
    {
        "id": "launch",
        "group": "采集",
        "title": "启动页",
        "subtitle": "去掉插画与渐变文字",
        "shots": [("00-launch", "启动页")],
        "notes": [
            "启动页改为深色仪器底 + 淡测绘网格，与工作区的测区空板同一套语言。",
            "产品名用系统字体的半粗字重，不再用斜体渐变文字和果实插画。",
            "应用图标改为**点云树**：树干与树冠由离散点构成，正是本产品测量树体的方式，配一条比例尺。",
        ],
        "components": ["LaunchScreen", "LaunchScreenV2.storyboard"],
        "data": "无数据；仅为品牌与启动过渡。",
    },
]

# ---------------------------------------------------------------- rendering

CSS = """
:root {
  --paper: #F4F3EF;
  --surface: #FFFFFF;
  --inset: #EDEBE5;
  --line: #DFDDD6;
  --line-strong: #C9C6BC;
  --ink: #151A1C;
  --ink-2: #4C565B;
  --ink-3: #5E6A70;
  --accent: #0E6B78;
  --accent-soft: #E4F0F1;
  --attention: #8F5B0E;
  --failure: #A3382A;
  --reliable: #2C6A46;
  --dark: #0E1214;
  --radius: 10px;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: var(--paper);
  color: var(--ink);
  font: 15px/1.6 -apple-system, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
  -webkit-font-smoothing: antialiased;
}
.shell { display: grid; grid-template-columns: 268px 1fr; min-height: 100vh; }
nav {
  position: sticky; top: 0; align-self: start; height: 100vh; overflow-y: auto;
  background: var(--surface); border-right: 1px solid var(--line); padding: 26px 18px 40px;
}
nav .brand { font-size: 19px; font-weight: 650; letter-spacing: -0.2px; }
nav .mark {
  font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 1.6px; text-transform: uppercase;
  color: var(--ink-3); margin-top: 7px;
}
nav .rule { height: 1px; background: var(--line); margin: 18px 0 16px; }
nav .group {
  font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 1.2px; text-transform: uppercase;
  color: var(--ink-3); margin: 20px 0 8px;
}
nav a {
  display: block; padding: 8px 10px; margin: 1px 0; border-radius: 6px;
  color: var(--ink-2); text-decoration: none; font-size: 14px;
}
nav a:hover { background: var(--inset); color: var(--ink); }
nav a.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
main { padding: 34px 40px 80px; max-width: 1180px; }
header.page { margin-bottom: 26px; }
header.page h1 { font-size: 27px; font-weight: 650; letter-spacing: -0.3px; margin: 0 0 6px; }
header.page p { margin: 0; color: var(--ink-2); max-width: 68ch; }
section.page { margin: 0 0 56px; scroll-margin-top: 24px; }
section.page > h2 {
  font-size: 20px; font-weight: 650; margin: 0 0 4px; display: flex; align-items: baseline; gap: 10px;
}
section.page > h2 .tag {
  font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 1.2px; text-transform: uppercase;
  color: var(--accent); background: var(--accent-soft); padding: 4px 7px; border-radius: 4px;
}
section.page > .sub { color: var(--ink-2); margin: 0 0 18px; max-width: 68ch; }
.shots { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 16px; }
figure {
  margin: 0; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius);
  overflow: hidden;
}
figure img { display: block; width: 100%; height: auto; }
figcaption {
  padding: 9px 12px; font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 1.1px;
  text-transform: uppercase; color: var(--ink-3); border-top: 1px solid var(--line);
  display: flex; justify-content: space-between; align-items: center;
}
figcaption .count { color: var(--ink-3); font-weight: 500; letter-spacing: 0.4px; text-transform: none; }
.cols { display: grid; grid-template-columns: 1.35fr 1fr; gap: 20px; margin-top: 20px; }
.card {
  background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); padding: 16px 18px;
}
.card h3 {
  margin: 0 0 10px; font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 1.2px;
  text-transform: uppercase; color: var(--ink-3);
}
.card ul { margin: 0; padding-left: 18px; }
.card li { margin-bottom: 7px; }
.card li:last-child { margin-bottom: 0; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip {
  font: 500 12px/1 -apple-system, sans-serif; background: var(--inset); border: 1px solid var(--line);
  color: var(--ink-2); padding: 5px 8px; border-radius: 5px;
}
.note {
  background: var(--surface); border: 1px solid var(--line); border-left: 3px solid var(--accent);
  border-radius: 6px; padding: 12px 14px; color: var(--ink-2); font-size: 14px;
}
.legend { display: flex; flex-wrap: wrap; gap: 18px; margin-top: 26px; }
.legend .item { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); }
.legend .swatch { width: 12px; height: 12px; border-radius: 3px; border: 1px solid var(--line-strong); }
footer {
  border-top: 1px solid var(--line); margin-top: 40px; padding-top: 18px;
  color: var(--ink-3); font-size: 13px;
}
@media (max-width: 900px) {
  .shell { grid-template-columns: 1fr; }
  nav { position: static; height: auto; border-right: 0; border-bottom: 1px solid var(--line); }
  .cols { grid-template-columns: 1fr; }
  main { padding: 24px 20px 60px; }
}
"""

JS = """
const links = Array.from(document.querySelectorAll('nav a'));
const sections = Array.from(document.querySelectorAll('section.page'));
const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    links.forEach((l) => l.classList.toggle('active', l.getAttribute('href') === '#' + entry.target.id));
  });
}, { rootMargin: '-20% 0px -70% 0px' });
sections.forEach((s) => observer.observe(s));
links.forEach((l) => l.addEventListener('click', () => {
  links.forEach((x) => x.classList.remove('active'));
  l.classList.add('active');
}));
"""


def embed(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def required_shots():
    """Every screenshot the canvas needs, enumerated up front."""
    return [(page["id"], key, label) for page in PAGES for key, label in page["shots"]]


def build(screenshot_dir: Path, output: Path, title: str):
    index = {}
    for candidate in sorted(screenshot_dir.iterdir()):
        if candidate.suffix.lower() in {".png", ".jpg", ".jpeg"}:
            index[candidate.stem] = candidate
    # also accept the "<name>-<index>.png" pattern used by the gallery
    for candidate in sorted(screenshot_dir.iterdir()):
        if candidate.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            continue
        stem = candidate.stem
        for sep in ("-", "_"):
            if sep in stem:
                index.setdefault(stem.rsplit(sep, 1)[0], candidate)

    # --- enumerate every requirement first, so nothing can be skipped silently ---
    required = required_shots()
    missing = []
    present = {}
    for page_id, key, label in required:
        path = index.get(key)
        if path is None:
            missing.append(f"{page_id}: {key}  (expected file {key}.png)")
        else:
            present.setdefault(page_id, []).append((key, label, path))

    used = sum(len(v) for v in present.values())
    nav_html = []
    body_html = []

    groups = []
    for page in PAGES:
        if page["group"] not in groups:
            groups.append(page["group"])

    for group in groups:
        nav_html.append(f'<div class="group">{html.escape(group)}</div>')
        for page in PAGES:
            if page["group"] != group:
                continue
            if page["id"] not in present:
                # No screenshot for this page: it must not appear in the navigation,
                # and it has already been recorded in `missing`.
                continue
            nav_html.append(
                f'<a href="#{page["id"]}">{html.escape(page["title"])}</a>'
            )

            figures = []
            for key, label, path in present[page["id"]]:
                figures.append(
                    f'<figure><img alt="{html.escape(label)}" src="{embed(path)}">'
                    f'<figcaption><span>{html.escape(label)}</span>'
                    f'<span class="count">{path.name}</span></figcaption></figure>'
                )

            notes = "".join(f"<li>{html.escape(n)}</li>" for n in page["notes"])
            chips = "".join(f'<span class="chip">{html.escape(c)}</span>' for c in page["components"])

            body_html.append(
                f'<section class="page" id="{page["id"]}">'
                f'<h2><span class="tag">{html.escape(page["group"])}</span>{html.escape(page["title"])}</h2>'
                f'<p class="sub">{html.escape(page["subtitle"])}</p>'
                f'<div class="shots">{"".join(figures)}</div>'
                f'<div class="cols">'
                f'<div class="card"><h3>设计与实现说明</h3><ul>{notes}</ul></div>'
                f'<div class="card"><h3>使用的设计系统组件</h3><div class="chips">{chips}</div>'
                f'<h3 style="margin-top:18px">数据来源</h3><div class="note">{html.escape(page["data"])}</div></div>'
                f'</div></section>'
            )

    legend = (
        '<div class="legend">'
        '<div class="item"><span class="swatch" style="background:#0E6B78"></span>信号青：操作 / 选中 / 进行中</div>'
        '<div class="item"><span class="swatch" style="background:#8F5B0E"></span>琥珀：待复核 / 警告</div>'
        '<div class="item"><span class="swatch" style="background:#A3382A"></span>锈红：失败 / 不可用</div>'
        '<div class="item"><span class="swatch" style="background:#2C6A46"></span>深绿：可靠融合（仅结果页）</div>'
        '<div class="item"><span class="swatch" style="background:#3F5B70"></span>钢蓝：中性信息</div>'
        '</div>'
    )

    if missing:
        banner = (
            '<div class="incomplete">此画布不完整：缺少以下必需截图。'
            + "".join(f"<code>{html.escape(m)}</code>" for m in missing)
            + '</div>'
        )
    else:
        banner = ""

    document = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{CSS}
.incomplete {{ background:#F8E8E5; border:1px solid #A3382A; color:#8E2F22;
  padding:14px 16px; border-radius:8px; margin-bottom:20px; }}
.incomplete code {{ display:block; font-family: ui-monospace, Menlo, monospace; font-size:12px; }}
.notice {{ background:#F3F1EA; border:1px solid #C9C4B6; color:#2A3033;
  padding:12px 14px; border-radius:8px; margin:14px 0 0; line-height:1.65; font-size:13px; }}
</style>
</head>
<body>
<div class="shell">
<nav>
  <div class="brand">果树扫描 · 界面重建</div>
  <div class="mark">Orchard LiDAR Scanner</div>
  <div class="rule"></div>
  {''.join(nav_html)}
</nav>
<main>
  <header class="page">
    {banner}
    <h1>{html.escape(title)}</h1>
    <p>逐页说明重建后的原生界面。截图来自 iPhone 17 Pro 模拟器上的原生渲染，
       每一页都标注了设计决定、所用设计系统组件以及数据来源。
       证据等级一律用线型（实线/虚线/点线/空心）表达，颜色只作强化。</p>
    <p class="notice"><strong>关于这批数据：</strong>本画布里的**全部**读数——产量、果数、
       树高、范围、日期与 GPS 坐标——都来自为界面评审生成的<strong>合成夹具</strong>
       （合成 PLY + 合成归档记录），<strong>不是现场测量</strong>。
       真实的是<strong>组件、Store、解析与聚合逻辑</strong>：点云由真实 PLY 解析器解析、
       统计由真实聚合器算出、页面由真实 SwiftUI 组件渲染。
       这些截图证明的是<strong>原生布局与交互形态</strong>，
       不等于 App 端到端导航已在真机上跑通，也不构成任何果园的实测结论。</p>
    {legend}
  </header>
  {''.join(body_html)}
  <footer>
    <p>重建范围：工作台、档案、分析、建档与快速采集、扫描采集、结果与诊断、点云浏览与测量、
       历史与筛选、校准、地块/标签/树木、导入、批量导出、报告/趋势/对比、地图、设置/相机/品种、帮助。</p>
    <p>业务逻辑、融合与估产不变量、参数阈值、生命周期、持久化与导出格式均未改动。
       模拟器不具备真实 LiDAR 采集能力；采集 HUD 与结果页预览是 DEBUG 下的设计评审预览，
       画面上都有明确标注。真机验收按要求暂缓。</p>
    <p><strong>已知限制：</strong>① 果园地图那张的底图与点位在本轮正常渲染（高德底图 + 评审夹具点位），但点位坐标是<strong>合成</strong>的，不代表任何真实果园；
       ② PointCloudBounds 是点云的<strong>外接包围盒</strong>，不是实测冠幅——本画布不声称有冠层测量；
       ③ 这里的"真实"指组件与算法路径真实，不指数据来自现场；
       ④ 横屏/平板两张是**宿主窗口尺寸**下的布局验证，不等于真实 iPadOS 设备验收。</p>
  </footer>
</main>
</div>
<script>{JS}</script>
</body>
</html>
"""
    if missing:
        incomplete_path = output.with_name(output.stem + ".incomplete.html")
        incomplete_path.write_text(document, encoding="utf-8")
        return used, missing, incomplete_path
    output.write_text(document, encoding="utf-8")
    return used, missing, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", default="果树扫描 · 原生界面重建逐页说明")
    args = parser.parse_args()
    count, missing, written = build(args.screenshots, args.output, args.title)
    print(f"embedded {count} screenshot(s)")
    if missing:
        print(
            f"\nMISSING REQUIRED SCREENSHOTS ({len(missing)}) — the canvas is NOT complete:",
            file=sys.stderr,
        )
        for item in missing:
            print(f"  - {item}", file=sys.stderr)
        print(
            f"\nAn incomplete draft was written to {written}. "
            "Re-run the gallery workflow until every required screenshot exists.",
            file=sys.stderr,
        )
        return 1
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
