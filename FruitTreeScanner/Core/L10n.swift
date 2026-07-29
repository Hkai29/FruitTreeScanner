// L10n.swift
// 本地化辅助 - 提供类型安全的字符串访问

import Foundation

enum L10n {
    // MARK: - Scan
    enum Scan {
        static let estimating = NSLocalizedString("scan.estimating", value: "正在估算产量…", comment: "Yield estimation progress")
        static let skipGuide = NSLocalizedString("scan.skip_guide", value: "跳过引导", comment: "Skip scan guide button")
        static let recording = NSLocalizedString("scan.recording", value: "录制中", comment: "Recording status")
        static let noPointCloud = NSLocalizedString("scan.no_point_cloud", value: "请先录制一段点云后再测量", comment: "No point cloud notice")
        static let exportFailed = NSLocalizedString("scan.export_failed", value: "点云导出失败（文件写入错误），请检查存储空间后重试", comment: "PLY export failure")
        static let coverageComplete = NSLocalizedString("scan.coverage_complete", value: "覆盖完成", comment: "Scan coverage complete toast")
        static let scanning = NSLocalizedString("scan.scanning", value: "扫描中", comment: "Scanning status")
        static let detecting = NSLocalizedString("scan.detecting", value: "检测中...", comment: "Detecting camera resolution")
        static let interruptionTitle = NSLocalizedString("scan.interruption_title", value: "扫描已中断", comment: "Scan interruption alert title")
        static let interruptionMessage = NSLocalizedString("scan.interruption_message", value: "相机或 AR 跟踪在扫描过程中被中断。为避免混合不连续的扫描数据，请重新开始本次扫描。", comment: "Scan interruption alert message")
        static let sessionFailureTitle = NSLocalizedString("scan.session_failure_title", value: "扫描会话发生错误", comment: "AR session failure alert title")
        static let restartAfterInterruption = NSLocalizedString("scan.restart_after_interruption", value: "重新开始", comment: "Restart interrupted scan action")
        static let discardAfterInterruption = NSLocalizedString("scan.discard_after_interruption", value: "放弃扫描", comment: "Discard interrupted scan action")
        static let interruptionAccessibilityHint = NSLocalizedString("scan.interruption_accessibility_hint", value: "重新开始会清除本次扫描数据；放弃不会生成扫描结果。", comment: "Scan interruption recovery accessibility hint")
    }

    // MARK: - Result
    enum Result {
        static let yieldTitle = NSLocalizedString("result.yield_title", value: "估算产量", comment: "Yield result title")
        static let fruitCount = NSLocalizedString("result.fruit_count", value: "果实数量", comment: "Fruit count label")
        static let avgDiameter = NSLocalizedString("result.avg_diameter", value: "平均直径", comment: "Average diameter label")
        static let avgVolume = NSLocalizedString("result.avg_volume", value: "平均体积", comment: "Average volume label")
        static let confidence = NSLocalizedString("result.confidence", value: "置信度", comment: "Confidence label")
        static let method = NSLocalizedString("result.method", value: "估算方法", comment: "Estimation method label")
        static let scanResult = NSLocalizedString("result.scan_result", value: "扫描结果", comment: "Scan result header")
        static let confidenceHigh = NSLocalizedString("result.confidence_high", value: "高置信度", comment: "High confidence")
        static let confidenceMedium = NSLocalizedString("result.confidence_medium", value: "中等置信度", comment: "Medium confidence")
        static let confidenceManualReview = NSLocalizedString("result.confidence_manual_review", value: "需人工复核", comment: "Needs manual review")
        static let confidenceLow = NSLocalizedString("result.confidence_low", value: "低置信度", comment: "Low confidence")
        static let fruit = NSLocalizedString("result.fruit", value: "果实", comment: "Fruit pill label")
        static let pointCloud = NSLocalizedString("result.point_cloud", value: "点云", comment: "Point cloud pill label")
        static let methodLabel = NSLocalizedString("result.method_label", value: "方法", comment: "Method pill label")
        static let methodEstimate = NSLocalizedString("result.method_estimate", value: "估算", comment: "Estimation method fallback")
        static let continueNext = NSLocalizedString("result.continue_next", value: "继续扫描下一棵", comment: "Continue scanning next tree")
        static let backToHome = NSLocalizedString("result.back_to_home", value: "返回主界面", comment: "Return to home")
        static let fruitVolumeMethod = NSLocalizedString("result.fruit_volume_method", value: "果实体积法", comment: "Fruit volume method section")
        static let correctedFruitCount = NSLocalizedString("result.corrected_fruit_count", value: "校正后果实数", comment: "Corrected fruit count")
        static let visualCount = NSLocalizedString("result.visual_count", value: "视觉计数", comment: "Visual detection count")
        static let correctionFactor = NSLocalizedString("result.correction_factor", value: "总校正系数", comment: "Total correction factor")
        static let visibleWeight = NSLocalizedString("result.visible_weight", value: "可见部分重量", comment: "Visible part weight")
        static let correctedWeight = NSLocalizedString("result.corrected_weight", value: "校正后重量", comment: "Corrected weight")
        static let measuredDiameter = NSLocalizedString("result.measured_diameter", value: "实测平均直径", comment: "Measured average diameter")
        static let crownVolumeMethod = NSLocalizedString("result.crown_volume_method", value: "冠层体积法", comment: "Crown volume method section")
        static let crownYield = NSLocalizedString("result.crown_yield", value: "冠层回归产量", comment: "Crown regression yield")
        static let crownVolume = NSLocalizedString("result.crown_volume", value: "冠层体积", comment: "Crown volume")
        static let treeHeight = NSLocalizedString("result.tree_height", value: "树高", comment: "Tree height")
        static let crownNotTrained = NSLocalizedString("result.crown_not_trained", value: "路线A模型未训练，需采集称重数据后训练", comment: "Route A model not trained")
        static let algorithmParams = NSLocalizedString("result.algorithm_params", value: "算法参数", comment: "Algorithm parameters section")
        static let fruitCategory = NSLocalizedString("result.fruit_category", value: "水果类别", comment: "Fruit category")
        static let pointCloudSize = NSLocalizedString("result.point_cloud_size", value: "点云大小", comment: "Point cloud size")
        static let colorFilter = NSLocalizedString("result.color_filter", value: "颜色过滤", comment: "Color filter")
        static let occlusionK = NSLocalizedString("result.occlusion_k", value: "遮挡校正 K", comment: "Occlusion correction K")
        static let unit = NSLocalizedString("result.unit_count", value: "个", comment: "Count unit")
        static let unitPoints = NSLocalizedString("result.unit_points", value: "点", comment: "Points unit")
    }

    // MARK: - Dashboard
    enum Dashboard {
        static let title = NSLocalizedString("dashboard.title", value: "果园概览", comment: "Dashboard title")
        static let todayScans = NSLocalizedString("dashboard.today_scans", value: "扫描数量", comment: "Today's scans count")
        static let totalYield = NSLocalizedString("dashboard.total_yield", value: "总产量", comment: "Total yield")
        static let recentScans = NSLocalizedString("dashboard.recent_scans", value: "最近扫描", comment: "Recent scans section")
        static let noScans = NSLocalizedString("dashboard.no_scans", value: "还没有扫描记录", comment: "Empty scan history")
        static let settingsAccessibilityLabel = NSLocalizedString("dashboard.settings_accessibility_label", value: "设置", comment: "Dashboard settings accessibility label")
        static let workbenchTitle = NSLocalizedString("dashboard.workbench_title", value: "果园扫描工作台", comment: "Dashboard hero title")
        static let workbenchSubtitle = NSLocalizedString("dashboard.workbench_subtitle", value: "LiDAR 采集 · 点云记录 · 产量分析", comment: "Dashboard hero subtitle")
        static let fieldMode = NSLocalizedString("dashboard.field_mode", value: "现场", comment: "Dashboard field mode badge")
        static let today = NSLocalizedString("dashboard.today", value: "今日", comment: "Dashboard today metric")
        static let yield = NSLocalizedString("dashboard.yield", value: "产量", comment: "Dashboard yield metric")
        static let trees = NSLocalizedString("dashboard.trees", value: "树体", comment: "Dashboard trees metric")
        static let startScan = NSLocalizedString("dashboard.start_scan", value: "新建扫描", comment: "Dashboard start scan action")
        static let quickCapture = NSLocalizedString("dashboard.quick_capture", value: "快速采集", comment: "Dashboard quick scan action")
        static let tools = NSLocalizedString("dashboard.tools", value: "功能", comment: "Dashboard tools section")
        static let scanMode = NSLocalizedString("dashboard.mode.scan", value: "扫描", comment: "Dashboard scanning tool group")
        static let historyMode = NSLocalizedString("dashboard.mode.history", value: "历史", comment: "Dashboard history tool group")
        static let analyticsMode = NSLocalizedString("dashboard.mode.analytics", value: "分析", comment: "Dashboard analytics tool group")

        static let calibrationTitle = NSLocalizedString("dashboard.action.calibration.title", value: "校准参数", comment: "Dashboard calibration action title")
        static let calibrationDescription = NSLocalizedString("dashboard.action.calibration.description", value: "水果尺寸、聚类与误差记录", comment: "Dashboard calibration action description")
        static let importFileTitle = NSLocalizedString("dashboard.action.import_file.title", value: "导入点云", comment: "Dashboard point cloud import action title")
        static let importFileDescription = NSLocalizedString("dashboard.action.import_file.description", value: "加入已有 PLY 扫描文件", comment: "Dashboard point cloud import action description")
        static let scanHistoryTitle = NSLocalizedString("dashboard.action.scan_history.title", value: "扫描记录", comment: "Dashboard scan history action title")
        static let scanHistoryDescription = NSLocalizedString("dashboard.action.scan_history.description", value: "查看、删除和分享记录", comment: "Dashboard scan history action description")
        static let pointCloudTitle = NSLocalizedString("dashboard.action.point_cloud.title", value: "点云查看", comment: "Dashboard point cloud viewer action title")
        static let pointCloudDescription = NSLocalizedString("dashboard.action.point_cloud.description", value: "打开最近或指定点云", comment: "Dashboard point cloud viewer action description")
        static let tagManagementTitle = NSLocalizedString("dashboard.action.tag_management.title", value: "地块标签", comment: "Dashboard plot and tag management action title")
        static let tagManagementDescription = NSLocalizedString("dashboard.action.tag_management.description", value: "维护地块、标签和状态", comment: "Dashboard plot and tag management action description")
        static let batchExportTitle = NSLocalizedString("dashboard.action.batch_export.title", value: "批量导出", comment: "Dashboard batch export action title")
        static let batchExportDescription = NSLocalizedString("dashboard.action.batch_export.description", value: "导出多条扫描数据", comment: "Dashboard batch export action description")
        static let yieldReportTitle = NSLocalizedString("dashboard.action.yield_report.title", value: "产量报告", comment: "Dashboard yield report action title")
        static let yieldReportDescription = NSLocalizedString("dashboard.action.yield_report.description", value: "汇总果数和重量", comment: "Dashboard yield report action description")
        static let compareTitle = NSLocalizedString("dashboard.action.compare.title", value: "树体对比", comment: "Dashboard tree comparison action title")
        static let compareDescription = NSLocalizedString("dashboard.action.compare.description", value: "横向比较扫描结果", comment: "Dashboard tree comparison action description")
        static let trendsTitle = NSLocalizedString("dashboard.action.trends.title", value: "趋势", comment: "Dashboard trends action title")
        static let trendsDescription = NSLocalizedString("dashboard.action.trends.description", value: "观察产量变化", comment: "Dashboard trends action description")
        static let mapTitle = NSLocalizedString("dashboard.action.map.title", value: "果园地图", comment: "Dashboard orchard map action title")
        static let mapDescription = NSLocalizedString("dashboard.action.map.description", value: "按位置查看树体", comment: "Dashboard orchard map action description")

        static let viewAll = NSLocalizedString("dashboard.view_all", value: "查看全部", comment: "View all recent scans")
        static let emptyDescription = NSLocalizedString("dashboard.empty_description", value: "完成第一次扫描后，这里会显示最近树体、产量和点云入口。", comment: "Dashboard recent scans empty-state description")
        static let startFirstScan = NSLocalizedString("dashboard.start_first_scan", value: "开始第一次扫描", comment: "Dashboard first scan action")
        static let todayOverview = NSLocalizedString("dashboard.today_overview", value: "今日概览", comment: "Dashboard daily overview section")
        static let treeIDs = NSLocalizedString("dashboard.tree_ids", value: "树编号", comment: "Dashboard unique tree identifiers statistic")

        private static let historyAccessibilityLabel = NSLocalizedString("dashboard.history_accessibility_label", value: "扫描历史", comment: "Dashboard scan history accessibility label without a count")
        private static let historyAccessibilityOne = NSLocalizedString("dashboard.history_accessibility_one", value: "扫描历史，1条记录", comment: "Dashboard scan history accessibility label for one record")
        private static let historyAccessibilityCount = NSLocalizedString("dashboard.history_accessibility_count", value: "扫描历史，%d条记录", comment: "Dashboard scan history accessibility label with record count")
        private static let scanUnitOne = NSLocalizedString("dashboard.scan_unit_one", value: "次", comment: "Dashboard scan count unit for one scan")
        private static let scanUnitOther = NSLocalizedString("dashboard.scan_unit_other", value: "次", comment: "Dashboard scan count unit for multiple scans")
        private static let treeUnitOne = NSLocalizedString("dashboard.tree_unit_one", value: "棵", comment: "Dashboard tree count unit for one tree")
        private static let treeUnitOther = NSLocalizedString("dashboard.tree_unit_other", value: "棵", comment: "Dashboard tree count unit for multiple trees")
        private static let quickActionAccessibility = NSLocalizedString("dashboard.quick_action_accessibility", value: "%@，%@", comment: "Dashboard quick action accessibility label containing title and description")
        private static let viewPointCloudAccessibility = NSLocalizedString("dashboard.view_point_cloud_accessibility", value: "查看 %@ 点云", comment: "View a tree point cloud accessibility label")
        private static let fruitCountOne = NSLocalizedString("dashboard.fruit_count_one", value: "%d 个果实", comment: "Dashboard fruit count for one fruit")
        private static let fruitCountOther = NSLocalizedString("dashboard.fruit_count_other", value: "%d 个果实", comment: "Dashboard fruit count for multiple fruits")

        static func scanHistoryAccessibilityLabel(recordCount: Int) -> String {
            switch recordCount {
            case ...0:
                return historyAccessibilityLabel
            case 1:
                return historyAccessibilityOne
            default:
                return String(format: historyAccessibilityCount, recordCount)
            }
        }

        static func quickActionAccessibilityLabel(title: String, description: String) -> String {
            String(format: quickActionAccessibility, title, description)
        }

        static func scanCountUnit(_ count: Int) -> String {
            count == 1 ? scanUnitOne : scanUnitOther
        }

        static func treeCountUnit(_ count: Int) -> String {
            count == 1 ? treeUnitOne : treeUnitOther
        }

        static func viewPointCloudAccessibilityLabel(treeID: String) -> String {
            String(format: viewPointCloudAccessibility, treeID)
        }

        static func fruitCountLabel(_ count: Int) -> String {
            String(format: count == 1 ? fruitCountOne : fruitCountOther, count)
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = NSLocalizedString("settings.title", value: "设置", comment: "Settings title")
        static let fruitType = NSLocalizedString("settings.fruit_type", value: "水果类型", comment: "Fruit type setting")
        static let scanQuality = NSLocalizedString("settings.scan_quality", value: "扫描质量", comment: "Scan quality setting")
        static let autoExportCSV = NSLocalizedString("settings.auto_export_csv", value: "自动导出 CSV", comment: "Auto export CSV toggle")
    }

    // MARK: - Diagnostics
    enum Diagnostics {
        static let modelNotLoaded = NSLocalizedString("diag.model_not_loaded", value: "模型未加载", comment: "CoreML model not loaded")
        static let depthUnavailable = NSLocalizedString("diag.depth_unavailable", value: "深度不可用", comment: "Depth data unavailable")
        static let insufficientPoints = NSLocalizedString("diag.insufficient_points", value: "点云数量不足", comment: "Too few point cloud points")
        static let noImageFrames = NSLocalizedString("diag.no_image_frames", value: "未处理图像检测帧", comment: "No image frames processed")
        static let noDetections = NSLocalizedString("diag.no_detections", value: "图像检测无结果", comment: "No detections from image")
        static let confidenceFiltered = NSLocalizedString("diag.confidence_filtered", value: "候选被置信度过滤", comment: "Candidates filtered by confidence")
        static let unmappedLabels = NSLocalizedString("diag.unmapped_labels", value: "模型标签未映射到水果类别", comment: "Model labels not mapped")
        static let noCandidates = NSLocalizedString("diag.no_candidates", value: "点云聚类无候选", comment: "No clustering candidates")
        static let fusionFailed = NSLocalizedString("diag.fusion_failed", value: "融合验证失败", comment: "Fusion validation failed")
        static let cloudOnlyRejected = NSLocalizedString("diag.cloud_only_rejected", value: "cloudOnly 保守模式未接受候选", comment: "Cloud only conservative mode rejected")
    }

    // MARK: - Quality
    enum Quality {
        static let tooDark = NSLocalizedString("quality.too_dark", value: "过暗", comment: "Too dark lighting")
        static let dark = NSLocalizedString("quality.dark", value: "偏暗", comment: "Dark lighting")
        static let normal = NSLocalizedString("quality.normal", value: "正常", comment: "Normal lighting")
        static let bright = NSLocalizedString("quality.bright", value: "偏亮", comment: "Bright lighting")
        static let tooBright = NSLocalizedString("quality.too_bright", value: "过曝", comment: "Too bright/overexposed lighting")
    }

    // MARK: - Voxel Discovery
    enum VoxelTrend {
        static let collecting = NSLocalizedString("voxel.collecting", value: "收集中...", comment: "Collecting voxel data")
        static let discovering = NSLocalizedString("voxel.discovering", value: "持续发现新区域", comment: "Actively discovering new areas")
        static let stabilizing = NSLocalizedString("voxel.stabilizing", value: "趋于稳定", comment: "Discovery rate stabilizing")
        static let complete = NSLocalizedString("voxel.complete", value: "覆盖完成", comment: "Coverage complete")
    }

    // MARK: - Export
    enum Export {
        static let csvDescription = NSLocalizedString("export.csv_desc", value: "通用数据格式，兼容所有表格软件", comment: "CSV format description")
        static let excelDescription = NSLocalizedString("export.excel_desc", value: "Microsoft Excel 兼容格式", comment: "Excel format description")
        static let noGrouping = NSLocalizedString("export.no_grouping", value: "不分组", comment: "No grouping option")
        static let byFruitType = NSLocalizedString("export.by_fruit_type", value: "按水果类型", comment: "Group by fruit type")
        static let byDate = NSLocalizedString("export.by_date", value: "按日期", comment: "Group by date")
        static let byPlot = NSLocalizedString("export.by_plot", value: "按地块", comment: "Group by plot")
        static let noRecords = NSLocalizedString("export.no_records", value: "没有可导出的记录", comment: "No exportable records")
    }

    // MARK: - Fruit Names
    enum Fruit {
        static func name(for category: FruitCategory) -> String {
            NSLocalizedString("fruit.\(category.rawValue)", value: category.displayName, comment: "Fruit name: \(category.rawValue)")
        }
    }

    // MARK: - Fruit Category Verification
    enum FruitCategoryVerification {
        static let selectionTitle = NSLocalizedString("fruit_category_selection_title", value: "目标水果", comment: "Fruit category selection title")
        static let currentSelection = NSLocalizedString("fruit_category_current_selection", value: "当前选择", comment: "Current fruit category selection")
        static let fixedForScan = NSLocalizedString("fruit_category_fixed_for_scan", value: "本次扫描固定使用此类别；识别结果只作校验。", comment: "Selected category remains fixed during a scan")
        static let mismatchTitle = NSLocalizedString("fruit_category_mismatch_title", value: "水果种类可能不一致", comment: "Fruit category mismatch alert title")
        static let continueAction = NSLocalizedString("fruit_category_continue_action", value: "继续扫描", comment: "Continue scanning action")
        static let stopAndSwitchAction = NSLocalizedString("fruit_category_stop_and_switch_action", value: "停止并切换", comment: "Stop and switch fruit category action")
        static let selectedAccessibilityLabel = NSLocalizedString("fruit_category_selected_accessibility_label", value: "水果种类", comment: "Fruit category picker accessibility label")
        static let selectedAccessibilityHint = NSLocalizedString("fruit_category_selected_accessibility_hint", value: "选择后将固定用于本次扫描，不会被自动识别结果替换。", comment: "Fruit category picker accessibility hint")
        static let mismatchAccessibilityHint = NSLocalizedString("fruit_category_mismatch_accessibility_hint", value: "停止当前扫描、清除本次扫描数据，并为下一次扫描设置为 %@。", comment: "Stop and switch accessibility hint")

        static func mismatchMessage(selected: FruitCategory, detected: FruitCategory) -> String {
            String(
                format: NSLocalizedString(
                    "fruit_category_mismatch_message",
                    value: "当前选择：%@\n\n连续识别结果更像%@。继续按%@扫描，还是停止并切换为%@？",
                    comment: "Fruit category mismatch message"
                ),
                Fruit.name(for: selected),
                Fruit.name(for: detected),
                Fruit.name(for: selected),
                Fruit.name(for: detected)
            )
        }

        static func selectionAccessibilityValue(_ category: FruitCategory) -> String {
            String(
                format: NSLocalizedString(
                    "fruit_category_selected_accessibility_value",
                    value: "%@, selected",
                    comment: "Selected fruit category accessibility value"
                ),
                Fruit.name(for: category)
            )
        }

        static func switchAccessibilityHint(to category: FruitCategory) -> String {
            String(format: mismatchAccessibilityHint, Fruit.name(for: category))
        }
    }

    // MARK: - Common
    enum Common {
        static let cancel = NSLocalizedString("common.cancel", value: "取消", comment: "Cancel button")
        static let confirm = NSLocalizedString("common.confirm", value: "确认", comment: "Confirm button")
        static let done = NSLocalizedString("common.done", value: "完成", comment: "Done button")
        static let delete = NSLocalizedString("common.delete", value: "删除", comment: "Delete button")
        static let save = NSLocalizedString("common.save", value: "保存", comment: "Save button")
        static let share = NSLocalizedString("common.share", value: "分享", comment: "Share button")
    }
}
