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

    // MARK: - Scan Readiness
    enum ScanReadiness {
        enum Key: String {
            case checkingTitle = "scan.readiness.checking.title"
            case checkingMessage = "scan.readiness.checking.message"
            case arUnsupportedTitle = "scan.readiness.ar_unsupported.title"
            case arUnsupportedMessage = "scan.readiness.ar_unsupported.message"
            case metalUnavailableTitle = "scan.readiness.metal_unavailable.title"
            case metalUnavailableMessage = "scan.readiness.metal_unavailable.message"
            case lidarUnavailableTitle = "scan.readiness.lidar_unavailable.title"
            case lidarUnavailableMessage = "scan.readiness.lidar_unavailable.message"
            case cameraDeniedTitle = "scan.readiness.camera_denied.title"
            case cameraDeniedMessage = "scan.readiness.camera_denied.message"
            case cameraRestrictedTitle = "scan.readiness.camera_restricted.title"
            case cameraRestrictedMessage = "scan.readiness.camera_restricted.message"
            case openSettings = "scan.readiness.open_settings"
            case back = "scan.readiness.back"

            fileprivate var fallback: String {
                switch self {
                case .checkingTitle:
                    return "正在检查设备能力"
                case .checkingMessage:
                    return "正在确认相机、ARKit 和深度扫描链路。"
                case .arUnsupportedTitle:
                    return "当前设备不支持 AR 扫描"
                case .arUnsupportedMessage:
                    return "FruitTreeScanner 需要 ARKit 才能采集点云。请使用支持 ARKit 的 iPhone 或 iPad。"
                case .metalUnavailableTitle:
                    return "图形渲染不可用"
                case .metalUnavailableMessage:
                    return "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。"
                case .lidarUnavailableTitle:
                    return "当前设备没有 LiDAR 深度"
                case .lidarUnavailableMessage:
                    return "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。"
                case .cameraDeniedTitle:
                    return "相机权限未开启"
                case .cameraDeniedMessage:
                    return "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。"
                case .cameraRestrictedTitle:
                    return "相机权限受限"
                case .cameraRestrictedMessage:
                    return "系统限制了相机访问，当前无法开始扫描。"
                case .openSettings:
                    return "打开设置"
                case .back:
                    return "返回"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static var openSettings: String {
            text(.openSettings)
        }

        static var back: String {
            text(.back)
        }
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
        static let todayScans = NSLocalizedString("dashboard.today_scans", value: "今日扫描", comment: "Today's scans count")
        static let totalYield = NSLocalizedString("dashboard.total_yield", value: "总产量", comment: "Total yield")
        static let recentScans = NSLocalizedString("dashboard.recent_scans", value: "最近扫描", comment: "Recent scans section")
        static let noScans = NSLocalizedString("dashboard.no_scans", value: "暂无扫描记录", comment: "Empty scan history")
    }

    // MARK: - Scan History
    enum History {
        static let navigationTitle = NSLocalizedString("history.navigation_title", value: "扫描历史", comment: "Scan history navigation title")
        static let headerTitle = NSLocalizedString("history.header.title", value: "扫描记录", comment: "Scan history header")
        static let headerSubtitle = NSLocalizedString("history.header.subtitle", value: "按时间、地块和状态查看所有扫描文件。", comment: "Scan history header description")
        static let emptyTitle = NSLocalizedString("history.empty.title", value: "暂无扫描记录", comment: "Empty scan history title")
        static let emptyMessage = NSLocalizedString("history.empty.message", value: "完成扫描或导入 PLY 后，点云文件、果数和产量会按时间保存在这里。", comment: "Empty scan history description")
        static let filteredEmptyTitle = NSLocalizedString("history.filtered_empty.title", value: "没有符合筛选的记录", comment: "Filtered scan history empty title")
        static let filteredEmptyMessage = NSLocalizedString("history.filtered_empty.message", value: "切换地块或状态筛选后再查看。", comment: "Filtered scan history empty description")
        static let startScan = NSLocalizedString("history.action.start_scan", value: "开始扫描", comment: "Start scan action")
        static let importPLY = NSLocalizedString("history.action.import_ply", value: "导入 PLY", comment: "Import PLY action")
        static let clearAll = NSLocalizedString("history.action.clear_all", value: "清空全部", comment: "Clear all scan history action")
        static let clear = NSLocalizedString("history.action.clear", value: "清空", comment: "Confirm clearing scan history action")
        static let allPlots = NSLocalizedString("history.filter.all_plots", value: "全部地块", comment: "All plots filter")
        static let plotFallback = NSLocalizedString("history.filter.plot_fallback", value: "地块", comment: "Missing plot filter fallback")
        static let allStatuses = NSLocalizedString("history.filter.all_statuses", value: "全部状态", comment: "All statuses filter")
        static let deleteAlertTitle = NSLocalizedString("history.alert.delete.title", value: "删除扫描记录", comment: "Delete scan record alert title")
        static let deleteAlertMessage = NSLocalizedString("history.alert.delete.message", value: "将删除这条记录关联的 PLY 点云、CSV 和结果文件。", comment: "Delete scan record alert message")
        static let clearAlertTitle = NSLocalizedString("history.alert.clear.title", value: "清空全部扫描记录", comment: "Clear scan history alert title")
        static let clearAlertMessage = NSLocalizedString("history.alert.clear.message", value: "将删除当前所有扫描记录及其关联文件，此操作无法撤销。", comment: "Clear scan history alert message")
        static let previewPointCloud = NSLocalizedString("history.row.preview_point_cloud", value: "预览点云", comment: "Preview point cloud action")
        static let rescanTree = NSLocalizedString("history.row.rescan_tree", value: "复扫这棵", comment: "Rescan tree action")
        static let markReview = NSLocalizedString("history.row.mark_review", value: "标记待复核", comment: "Mark scan record for review action")
        static let sharePointCloud = NSLocalizedString("history.row.share_point_cloud", value: "分享点云", comment: "Share point cloud action")
        static let deleteRecord = NSLocalizedString("history.row.delete_record", value: "删除记录", comment: "Delete scan record action")
        static let moreActions = NSLocalizedString("history.row.more_actions", value: "更多操作", comment: "More scan record actions")
        static let unknownSize = NSLocalizedString("history.row.unknown_size", value: "未知大小", comment: "Unknown scan file size")
        static let uncounted = NSLocalizedString("history.row.uncounted", value: "未计数", comment: "Scan record has no fruit count")

        static func statusLocalizationKey(for status: ScanStatus) -> String {
            switch status {
            case .notScanned:
                return "history.filter.status.not_scanned"
            case .scanned:
                return "history.filter.status.scanned"
            case .reviewing:
                return "history.filter.status.reviewing"
            case .completed:
                return "history.filter.status.completed"
            }
        }

        static func statusName(for status: ScanStatus) -> String {
            let fallback: String
            switch status {
            case .notScanned:
                fallback = "未扫描"
            case .scanned:
                fallback = "已扫描"
            case .reviewing:
                fallback = "复查中"
            case .completed:
                fallback = "已完成"
            }
            return NSLocalizedString(
                statusLocalizationKey(for: status),
                value: fallback,
                comment: "Localized scan status"
            )
        }

        static func fruitCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString("history.row.count_format", value: "%d 个", comment: "Fruit count in scan history"),
                count
            )
        }

        static func yieldKilograms(_ kilograms: Float) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString("history.row.yield_format", value: "%.1f kg", comment: "Yield in scan history"),
                Double(kilograms)
            )
        }

        static func fileSizeMegabytes(_ megabytes: Double) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString("history.row.file_size_format", value: "%.1f MB", comment: "Point cloud file size"),
                megabytes
            )
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
