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
        static let calibrationUnavailable = NSLocalizedString("scan.calibration_unavailable", value: "本地校准记录无法读取，本次扫描将不应用本地校正", comment: "Calibration records unavailable warning")
        static let restartAfterInterruption = NSLocalizedString("scan.restart_after_interruption", value: "重新开始", comment: "Restart interrupted scan action")
        static let discardAfterInterruption = NSLocalizedString("scan.discard_after_interruption", value: "放弃扫描", comment: "Discard interrupted scan action")
        static let interruptionAccessibilityHint = NSLocalizedString("scan.interruption_accessibility_hint", value: "重新开始会清除本次扫描数据；放弃不会生成扫描结果。", comment: "Scan interruption recovery accessibility hint")
    }

    // MARK: - Scan Completion
    enum ScanCompletion {
        enum Key: String {
            case statusComplete = "scan.completion.status.complete"
            case statusCoverageGood = "scan.completion.status.coverage_good"
            case statusContinueScanning = "scan.completion.status.continue_scanning"
            case statusInsufficient = "scan.completion.status.insufficient"
            case hintOtherSide = "scan.completion.hint.other_side"
            case hintBackSide = "scan.completion.hint.back_side"
            case hintVertical = "scan.completion.hint.vertical"
            case hintSparseAngles = "scan.completion.hint.sparse_angles"
            case hintTrunk = "scan.completion.hint.trunk"
            case hintDiscovering = "scan.completion.hint.discovering"
            case hintFinishBack = "scan.completion.hint.finish_back"
            case hintStable = "scan.completion.hint.stable"
            case spatialSamplesFormat = "scan.completion.spatial_samples_format"
            case metricDuration = "scan.completion.metric.duration"
            case metricCanopy = "scan.completion.metric.canopy"
            case metricAngles = "scan.completion.metric.angles"
            case metricBalance = "scan.completion.metric.balance"
            case metricStability = "scan.completion.metric.stability"
            case metricPointCloud = "scan.completion.metric.point_cloud"
            case metricStatus = "scan.completion.metric.status"
            case previewReady = "scan.completion.preview_ready"
            case nextHigh = "scan.completion.next.high"
            case nextMedium = "scan.completion.next.medium"
            case nextLow = "scan.completion.next.low"
            case resume = "scan.completion.resume"
            case finishEstimate = "scan.completion.finish_estimate"
            case toastTitle = "scan.completion.toast.title"
            case toastMessage = "scan.completion.toast.message"

            fileprivate var fallback: String {
                switch self {
                case .statusComplete: return "扫描完成"
                case .statusCoverageGood: return "覆盖良好"
                case .statusContinueScanning: return "继续扫描"
                case .statusInsufficient: return "覆盖率不足"
                case .hintOtherSide: return "补扫树冠另一侧"
                case .hintBackSide: return "补扫树冠背面"
                case .hintVertical: return "放慢补扫树冠上下层"
                case .hintSparseAngles: return "补扫稀疏视角"
                case .hintTrunk: return "从主干开始慢速环绕"
                case .hintDiscovering: return "正在发现树冠新区域"
                case .hintFinishBack: return "补树冠背面后可保存"
                case .hintStable: return "覆盖完整，可保存分析"
                case .spatialSamplesFormat: return "%d 个空间采样"
                case .metricDuration: return "时长"
                case .metricCanopy: return "树冠"
                case .metricAngles: return "视角"
                case .metricBalance: return "均衡"
                case .metricStability: return "稳定"
                case .metricPointCloud: return "点云"
                case .metricStatus: return "状态"
                case .previewReady: return "粗预览已就绪"
                case .nextHigh: return "覆盖充足，可直接完成并估算产量。"
                case .nextMedium: return "可完成分析；若树冠背面缺失，继续录制补一圈。"
                case .nextLow: return "建议继续录制，补齐树冠背面和主干遮挡区域。"
                case .resume: return "继续补扫"
                case .finishEstimate: return "完成估算"
                case .toastTitle: return "扫描覆盖充足"
                case .toastMessage: return "可以点击完成保存结果"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static func spatialSamples(_ count: Int, in bundle: Bundle = .main) -> String {
            String(format: text(.spatialSamplesFormat, in: bundle), count)
        }
    }

    // MARK: - Scan Controls
    enum ScanControls {
        enum Key: String {
            case guide = "scan.controls.guide"
            case measure = "scan.controls.measure"
            case cancel = "scan.controls.cancel"
            case startRecording = "scan.controls.start_recording"
            case stopRecording = "scan.controls.stop_recording"
            case rerecord = "scan.controls.rerecord"
            case finish = "scan.controls.finish"
            case processing = "scan.controls.processing"

            fileprivate var fallback: String {
                switch self {
                case .guide: return "引导"
                case .measure: return "测量"
                case .cancel: return "取消"
                case .startRecording: return "开始录制"
                case .stopRecording: return "停止录制"
                case .rerecord: return "重新录制"
                case .finish: return "完成"
                case .processing: return "处理中"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }
    }

    // MARK: - Scan Guidance
    enum ScanGuidance {
        enum Key: String {
            case tooFastTitle = "scan.guidance.hint.too_fast.title"
            case tooFastSubtitle = "scan.guidance.hint.too_fast.subtitle"
            case tooCloseTitle = "scan.guidance.hint.too_close.title"
            case tooCloseSubtitle = "scan.guidance.hint.too_close.subtitle"
            case tooFarTitle = "scan.guidance.hint.too_far.title"
            case tooFarSubtitle = "scan.guidance.hint.too_far.subtitle"
            case trackingLostTitle = "scan.guidance.hint.tracking_lost.title"
            case trackingLostSubtitle = "scan.guidance.hint.tracking_lost.subtitle"
            case lowLightTitle = "scan.guidance.hint.low_light.title"
            case lowLightSubtitle = "scan.guidance.hint.low_light.subtitle"
            case sparseDepthTitle = "scan.guidance.hint.sparse_depth.title"
            case sparseDepthSubtitle = "scan.guidance.hint.sparse_depth.subtitle"
            case goodPaceTitle = "scan.guidance.hint.good_pace.title"
            case goodPaceSubtitle = "scan.guidance.hint.good_pace.subtitle"
            case speedFormat = "scan.guidance.speed_format"
            case guideTitle = "scan.guide.title"
            case guideSubtitle = "scan.guide.subtitle"
            case closeGuideAccessibility = "scan.guide.close_accessibility"
            case slowCircleTitle = "scan.guide.tip.slow_circle.title"
            case slowCircleMessage = "scan.guide.tip.slow_circle.message"
            case outlineFirstTitle = "scan.guide.tip.outline_first.title"
            case outlineFirstMessage = "scan.guide.tip.outline_first.message"
            case blindSpotsTitle = "scan.guide.tip.blind_spots.title"
            case blindSpotsMessage = "scan.guide.tip.blind_spots.message"
            case measureTitle = "scan.guide.tip.measure.title"
            case measureMessage = "scan.guide.tip.measure.message"
            case defaultMode = "scan.guide.default_mode"
            case wholeTree = "scan.guide.whole_tree"
            case start = "scan.guide.start"

            fileprivate var fallback: String {
                switch self {
                case .tooFastTitle: return "移动太快"
                case .tooFastSubtitle: return "放慢脚步，让树冠和主枝有足够重叠"
                case .tooCloseTitle: return "距离太近"
                case .tooCloseSubtitle: return "后退一步，先保住整棵树轮廓"
                case .tooFarTitle: return "距离太远"
                case .tooFarSubtitle: return "靠近果树，优先补主干和果实密集区"
                case .trackingLostTitle: return "追踪丢失"
                case .trackingLostSubtitle: return "对准树干、地面或纹理清晰的枝条恢复追踪"
                case .lowLightTitle: return "光线不足"
                case .lowLightSubtitle: return "光线偏暗，果实检测和纹理质量会下降"
                case .sparseDepthTitle: return "树冠深度稀疏"
                case .sparseDepthSubtitle: return "减少天空占比，靠近树冠并放慢移动速度"
                case .goodPaceTitle: return "速度良好"
                case .goodPaceSubtitle: return "保持速度，继续绕树补齐背面盲区"
                case .speedFormat: return "%.1f m/s"
                case .guideTitle: return "果树 LiDAR 扫描"
                case .guideSubtitle: return "目标是稳定覆盖树干、树冠和果实区域；红色停止键前，先让点云绕树闭合。"
                case .closeGuideAccessibility: return "关闭扫描引导"
                case .slowCircleTitle: return "慢速环绕"
                case .slowCircleMessage: return "从树干开始，绕树一圈；每一步都让树冠和主枝保持在画面中。"
                case .outlineFirstTitle: return "先大后小"
                case .outlineFirstMessage: return "先拿到整棵树的轮廓，再补果实密集区和背光枝条，避免一开始贴太近。"
                case .blindSpotsTitle: return "补齐盲区"
                case .blindSpotsMessage: return "覆盖率到 60% 后重点看树冠背面、下层枝条和主干遮挡处。"
                case .measureTitle: return "可先测量"
                case .measureMessage: return "停止后不用立刻分析，可以先用测量确认树高、冠幅或样方距离。"
                case .defaultMode: return "默认模式"
                case .wholeTree: return "果树全株扫描"
                case .start: return "开始扫描"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static func speed(_ metersPerSecond: Float, in bundle: Bundle = .main) -> String {
            String(format: text(.speedFormat, in: bundle), Double(metersPerSecond))
        }
    }

    // MARK: - Scan Cancellation
    enum ScanCancellation {
        enum Key: String {
            case title = "scan.cancel.title"
            case continueAction = "scan.cancel.continue"
            case discard = "scan.cancel.discard"
            case message = "scan.cancel.message"

            fileprivate var fallback: String {
                switch self {
                case .title: return "取消本次扫描？"
                case .continueAction: return "继续扫描"
                case .discard: return "放弃"
                case .message: return "已采集的点云不会保存。若要保留本次采集，请点击完成。"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }
    }

    // MARK: - Scan Result Persistence
    enum ScanResultPersistence {
        enum Key: String {
            case failureTitle = "scan.result_persistence.failure.title"
            case failureMessage = "scan.result_persistence.failure.message"
            case retry = "scan.result_persistence.retry"
            case retrying = "scan.result_persistence.retrying"
            case retryHint = "scan.result_persistence.retry_hint"
            case successNotice = "scan.result_persistence.success_notice"
            case failureNotice = "scan.result_persistence.failure_notice"

            fileprivate var fallback: String {
                switch self {
                case .failureTitle: return "结果文件未保存"
                case .failureMessage: return "点云已安全保存，但果数和产量结果文件尚未保存。请在离开前重试，以保留完整记录。"
                case .retry: return "重试保存"
                case .retrying: return "正在重试…"
                case .retryHint: return "无需重新扫描，直接重试保存结果文件。"
                case .successNotice: return "结果文件已保存。"
                case .failureNotice: return "结果文件仍无法保存，请检查存储空间后重试。"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }
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

    // MARK: - Scan Export Readiness
    enum ScanExport {
        enum Key: String {
            case requirementsAction = "scan.export.requirements_action"
            case requirementsHint = "scan.export.requirements_hint"
            case lifecycleBlocked = "scan.export.blocked.lifecycle"
            case noDepth = "scan.export.blocked.no_depth"
            case waitingDepth = "scan.export.blocked.waiting_depth"
            case depthUnavailable = "scan.export.blocked.depth_unavailable"
            case noCloud = "scan.export.blocked.no_cloud"
            case tooFewPointsFormat = "scan.export.blocked.too_few_points_format"
            case preparing = "scan.export.blocked.preparing"

            fileprivate var fallback: String {
                switch self {
                case .requirementsAction:
                    return "查看要求"
                case .requirementsHint:
                    return "点击查看完成本次扫描前还需要满足的条件。"
                case .lifecycleBlocked:
                    return "当前扫描状态还不能完成，请开始录制或等待扫描恢复。"
                case .noDepth:
                    return "当前设备没有 LiDAR 深度，无法生成有效点云"
                case .waitingDepth:
                    return "LiDAR 深度帧还未到达，请移动设备继续扫描"
                case .depthUnavailable:
                    return "LiDAR 深度尚未就绪，请保持相机活跃后重试"
                case .noCloud:
                    return "尚未采集到可导出点云，请先按录制按钮并移动设备扫描"
                case .tooFewPointsFormat:
                    return "仅采集到 %lld 个点（建议至少 200+），请继续从不同角度扫描树冠"
                case .preparing:
                    return "扫描数据仍在准备中，请稍候后重试完成"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static func tooFewPoints(_ pointCount: Int, in bundle: Bundle = .main) -> String {
            String(format: text(.tooFewPointsFormat, in: bundle), Int64(pointCount))
        }

        static var requirementsAction: String {
            text(.requirementsAction)
        }

        static var requirementsHint: String {
            text(.requirementsHint)
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

    // MARK: - Quick Tagging
    enum QuickTagging {
        static let title = NSLocalizedString("quick_tagging.title", value: "快速标记", comment: "Quick tagging card title")
        static let plotLabel = NSLocalizedString("quick_tagging.plot_label", value: "地块", comment: "Plot selector accessibility label")
        static let plotPlaceholder = NSLocalizedString("quick_tagging.plot_placeholder", value: "选择地块", comment: "Plot selector placeholder")
        static let noPlot = NSLocalizedString("quick_tagging.plot_none", value: "无地块", comment: "No plot menu option")
        static let noPlotsAvailable = NSLocalizedString("quick_tagging.plot_empty", value: "暂无地块", comment: "No plots available menu item")
        static let noTags = NSLocalizedString("quick_tagging.tags_empty", value: "暂无标签，可稍后在地块标签中添加。", comment: "No tags available message")
        static let save = NSLocalizedString("quick_tagging.save", value: "保存标记", comment: "Save quick tagging action")
        static let saved = NSLocalizedString("quick_tagging.saved", value: "已保存标记", comment: "Quick tagging saved state")
        static let saveHint = NSLocalizedString("quick_tagging.save_hint", value: "保存这棵树所选的地块、标签和扫描状态。", comment: "Save quick tagging accessibility hint")
        static let tagHint = NSLocalizedString("quick_tagging.tag_hint", value: "切换这棵树的标签选择。", comment: "Tag selection accessibility hint")
        static let statusHint = NSLocalizedString("quick_tagging.status_hint", value: "设置这棵树的扫描状态。", comment: "Status selection accessibility hint")
        static let selected = NSLocalizedString("quick_tagging.selected", value: "已选择", comment: "Selected accessibility value")
        static let notSelected = NSLocalizedString("quick_tagging.not_selected", value: "未选择", comment: "Not selected accessibility value")

        static func statusLocalizationKey(_ status: ScanStatus) -> String {
            switch status {
            case .notScanned:
                return "quick_tagging.status.not_scanned"
            case .scanned:
                return "quick_tagging.status.scanned"
            case .reviewing:
                return "quick_tagging.status.reviewing"
            case .completed:
                return "quick_tagging.status.completed"
            }
        }

        static func statusName(for status: ScanStatus) -> String {
            NSLocalizedString(
                statusLocalizationKey(status),
                value: status.rawValue,
                comment: "Localized quick tagging scan status"
            )
        }

        static func selectionValue(isSelected: Bool) -> String {
            isSelected ? selected : notSelected
        }
    }

    // MARK: - Tag Management
    enum TagManagement {
        enum Key: String, CaseIterable {
            case navigationTitle = "tag_management.navigation_title"
            case headerTitle = "tag_management.header.title"
            case headerSubtitle = "tag_management.header.subtitle"
            case tabPickerLabel = "tag_management.tab_picker_label"
            case plotsTab = "tag_management.tab.plots"
            case tagsTab = "tag_management.tab.tags"
            case statusTab = "tag_management.tab.status"
            case confirmDelete = "tag_management.confirm_delete"
            case cancel = "tag_management.cancel"
            case done = "tag_management.done"
            case save = "tag_management.save"
            case addPlot = "tag_management.plot.add"
            case editPlot = "tag_management.plot.edit"
            case addTag = "tag_management.tag.add"
            case editTag = "tag_management.tag.edit"
            case plotPlaceholder = "tag_management.plot.placeholder"
            case tagPlaceholder = "tag_management.tag.placeholder"
            case nameLabel = "tag_management.name_label"
            case colorLabel = "tag_management.color_label"
            case plotsEmptyTitle = "tag_management.plot.empty.title"
            case plotsEmptyMessage = "tag_management.plot.empty.message"
            case tagsEmptyTitle = "tag_management.tag.empty.title"
            case tagsEmptyMessage = "tag_management.tag.empty.message"
            case statusEmptyTitle = "tag_management.status.empty.title"
            case statusEmptyMessage = "tag_management.status.empty.message"
            case startScan = "tag_management.start_scan"
            case treeCountOne = "tag_management.tree_count.one"
            case treeCountOther = "tag_management.tree_count.other"
            case editPlotHint = "tag_management.plot.edit_hint"
            case editTagHint = "tag_management.tag.edit_hint"
            case deletePlotAction = "tag_management.plot.delete_action"
            case deleteTagAction = "tag_management.tag.delete_action"
            case plotDeletionTitle = "tag_management.plot.delete.title"
            case tagDeletionTitle = "tag_management.tag.delete.title"
            case plotDeletionMessageOne = "tag_management.plot.delete.message.one"
            case plotDeletionMessageOther = "tag_management.plot.delete.message.other"
            case tagDeletionMessageOne = "tag_management.tag.delete.message.one"
            case tagDeletionMessageOther = "tag_management.tag.delete.message.other"
            case selected = "tag_management.selected"
            case notSelected = "tag_management.not_selected"
            case colorAccessibilityLabel = "tag_management.color.accessibility_label"
            case colorGreen = "tag_management.color.green"
            case colorAmber = "tag_management.color.amber"
            case colorBlue = "tag_management.color.blue"
            case colorRed = "tag_management.color.red"
            case colorBrown = "tag_management.color.brown"
            case colorOlive = "tag_management.color.olive"
            case colorGray = "tag_management.color.gray"
            case colorCharcoal = "tag_management.color.charcoal"

            var fallback: String {
                switch self {
                case .navigationTitle: return "标签管理"
                case .headerTitle: return "地块标签"
                case .headerSubtitle: return "维护地块、标签和扫描状态，让每棵树都有清晰归属。"
                case .tabPickerLabel: return "标签管理"
                case .plotsTab: return "地块"
                case .tagsTab: return "标签"
                case .statusTab: return "状态"
                case .confirmDelete: return "确认删除"
                case .cancel: return "取消"
                case .done: return "完成"
                case .save: return "保存"
                case .addPlot: return "添加地块"
                case .editPlot: return "编辑地块"
                case .addTag: return "添加标签"
                case .editTag: return "编辑标签"
                case .plotPlaceholder: return "输入地块名称"
                case .tagPlaceholder: return "输入标签名称"
                case .nameLabel: return "名称"
                case .colorLabel: return "颜色"
                case .plotsEmptyTitle: return "暂无地块"
                case .plotsEmptyMessage: return "添加地块后，可把果树扫描记录归到具体区域。"
                case .tagsEmptyTitle: return "暂无标签"
                case .tagsEmptyMessage: return "标签用于标记试验组、品种批次或管理状态。"
                case .statusEmptyTitle: return "暂无树体状态"
                case .statusEmptyMessage: return "开始扫描并选择地块或标签后，这里会汇总待扫描、复核中和已完成的树体数量。"
                case .startScan: return "开始扫描"
                case .treeCountOne, .treeCountOther: return "%d 棵树"
                case .editPlotHint: return "打开地块编辑页面。"
                case .editTagHint: return "打开标签编辑页面。"
                case .deletePlotAction: return "删除地块"
                case .deleteTagAction: return "删除标签"
                case .plotDeletionTitle: return "删除地块“%@”？"
                case .tagDeletionTitle: return "删除标签“%@”？"
                case .plotDeletionMessageOne, .plotDeletionMessageOther:
                    return "该操作会取消 %d 棵树的地块归属，但不会删除扫描记录。"
                case .tagDeletionMessageOne, .tagDeletionMessageOther:
                    return "该操作会从 %d 棵树移除此标签，但不会删除扫描记录。"
                case .selected: return "已选择"
                case .notSelected: return "未选择"
                case .colorAccessibilityLabel: return "颜色：%@"
                case .colorGreen: return "绿色"
                case .colorAmber: return "琥珀色"
                case .colorBlue: return "蓝色"
                case .colorRed: return "红色"
                case .colorBrown: return "棕色"
                case .colorOlive: return "橄榄色"
                case .colorGray: return "灰色"
                case .colorCharcoal: return "炭灰色"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static var navigationTitle: String { text(.navigationTitle) }
        static var headerTitle: String { text(.headerTitle) }
        static var headerSubtitle: String { text(.headerSubtitle) }
        static var tabPickerLabel: String { text(.tabPickerLabel) }
        static var plotsTab: String { text(.plotsTab) }
        static var tagsTab: String { text(.tagsTab) }
        static var statusTab: String { text(.statusTab) }
        static var confirmDelete: String { text(.confirmDelete) }
        static var cancel: String { text(.cancel) }
        static var done: String { text(.done) }
        static var save: String { text(.save) }
        static var addPlot: String { text(.addPlot) }
        static var editPlot: String { text(.editPlot) }
        static var addTag: String { text(.addTag) }
        static var editTag: String { text(.editTag) }
        static var plotPlaceholder: String { text(.plotPlaceholder) }
        static var tagPlaceholder: String { text(.tagPlaceholder) }
        static var nameLabel: String { text(.nameLabel) }
        static var colorLabel: String { text(.colorLabel) }
        static var plotsEmptyTitle: String { text(.plotsEmptyTitle) }
        static var plotsEmptyMessage: String { text(.plotsEmptyMessage) }
        static var tagsEmptyTitle: String { text(.tagsEmptyTitle) }
        static var tagsEmptyMessage: String { text(.tagsEmptyMessage) }
        static var statusEmptyTitle: String { text(.statusEmptyTitle) }
        static var statusEmptyMessage: String { text(.statusEmptyMessage) }
        static var startScan: String { text(.startScan) }
        static var editPlotHint: String { text(.editPlotHint) }
        static var editTagHint: String { text(.editTagHint) }
        static var deletePlotAction: String { text(.deletePlotAction) }
        static var deleteTagAction: String { text(.deleteTagAction) }

        static func treeCount(_ count: Int, in bundle: Bundle = .main) -> String {
            let key: Key = count == 1 ? .treeCountOne : .treeCountOther
            return String(format: text(key, in: bundle), count)
        }

        static func plotDeletionTitle(name: String, in bundle: Bundle = .main) -> String {
            String(format: text(.plotDeletionTitle, in: bundle), name)
        }

        static func tagDeletionTitle(name: String, in bundle: Bundle = .main) -> String {
            String(format: text(.tagDeletionTitle, in: bundle), name)
        }

        static func plotDeletionMessage(treeCount: Int, in bundle: Bundle = .main) -> String {
            let key: Key = treeCount == 1 ? .plotDeletionMessageOne : .plotDeletionMessageOther
            return String(format: text(key, in: bundle), treeCount)
        }

        static func tagDeletionMessage(treeCount: Int, in bundle: Bundle = .main) -> String {
            let key: Key = treeCount == 1 ? .tagDeletionMessageOne : .tagDeletionMessageOther
            return String(format: text(key, in: bundle), treeCount)
        }

        static func statusName(for status: ScanStatus, in bundle: Bundle = .main) -> String {
            bundle.localizedString(
                forKey: QuickTagging.statusLocalizationKey(status),
                value: status.rawValue,
                table: nil
            )
        }

        static func selectionValue(isSelected: Bool, in bundle: Bundle = .main) -> String {
            text(isSelected ? .selected : .notSelected, in: bundle)
        }

        static func colorName(for colorHex: String, in bundle: Bundle = .main) -> String {
            let key: Key
            switch colorHex.uppercased() {
            case "#6F8F63": key = .colorGreen
            case "#B8843A": key = .colorAmber
            case "#4D7588": key = .colorBlue
            case "#B8564B": key = .colorRed
            case "#8A7657": key = .colorBrown
            case "#6C7B58": key = .colorOlive
            case "#7E8580": key = .colorGray
            case "#34362F": key = .colorCharcoal
            default: return colorHex
            }
            return text(key, in: bundle)
        }

        static func colorAccessibilityLabel(for colorHex: String, in bundle: Bundle = .main) -> String {
            String(
                format: text(.colorAccessibilityLabel, in: bundle),
                colorName(for: colorHex, in: bundle)
            )
        }
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

    // MARK: - Batch Export
    enum BatchExport {
        static func fruitTypeLabel(_ rawValue: String, in bundle: Bundle = .main) -> String {
            guard let category = FruitCategory(rawValue: rawValue) else { return rawValue }
            return bundle.localizedString(
                forKey: "fruit.\(category.rawValue)",
                value: category.displayName,
                table: nil
            )
        }

        static func fruitCountLabel(_ count: Int, in bundle: Bundle = .main) -> String {
            let key = count == 1
                ? "batch_export.record.fruit_count_one"
                : "batch_export.record.fruit_count_other"
            let fallback = "%d 个果实"
            let format = bundle.localizedString(forKey: key, value: fallback, table: nil)
            return String(format: format, count)
        }

        static func yieldLabel(_ yieldKg: Float, in bundle: Bundle = .main) -> String {
            let format = bundle.localizedString(
                forKey: "batch_export.record.yield_format",
                value: "%.1f kg",
                table: nil
            )
            return String(format: format, Double(yieldKg))
        }

        static func unavailableMessage(
            for state: ScanPersistenceState,
            in bundle: Bundle = .main
        ) -> String {
            switch state {
            case .complete:
                return ""
            case .incomplete:
                return bundle.localizedString(
                    forKey: "batch_export.record.unavailable.incomplete",
                    value: "记录未完整保存，无法导出",
                    table: nil
                )
            case .invalid:
                return bundle.localizedString(
                    forKey: "batch_export.record.unavailable.invalid",
                    value: "记录数据无效，无法导出",
                    table: nil
                )
            }
        }

        static func recordAccessibilityLabel(
            treeID: String,
            fruitCount: Int,
            yieldKg: Float,
            in bundle: Bundle = .main
        ) -> String {
            let format = bundle.localizedString(
                forKey: "batch_export.record.accessibility.label",
                value: "%@，%@，%@",
                table: nil
            )
            return String(
                format: format,
                treeID,
                fruitCountLabel(fruitCount, in: bundle),
                yieldLabel(yieldKg, in: bundle)
            )
        }

        static func recordAccessibilityValue(
            isExportable: Bool,
            isSelected: Bool,
            persistenceState: ScanPersistenceState,
            in bundle: Bundle = .main
        ) -> String {
            guard isExportable else {
                return unavailableMessage(for: persistenceState, in: bundle)
            }
            let key = isSelected
                ? "batch_export.record.accessibility.selected"
                : "batch_export.record.accessibility.not_selected"
            let fallback = isSelected ? "已选择，可导出" : "未选择，可导出"
            return bundle.localizedString(forKey: key, value: fallback, table: nil)
        }

        static func toggleSelectionHint(in bundle: Bundle = .main) -> String {
            bundle.localizedString(
                forKey: "batch_export.record.accessibility.toggle_hint",
                value: "双击切换选择状态",
                table: nil
            )
        }
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

    // MARK: - Start Flow
    enum StartFlow {
        enum Key: String, CaseIterable {
            case cancel = "start.flow.cancel"
            case navigationTitle = "start.flow.navigation_title"
            case previous = "start.flow.previous"
            case next = "start.flow.next"
            case launching = "start.flow.launching"
            case launch = "start.flow.launch"
            case progressIdentifier = "start.flow.progress.identifier"
            case progressPlot = "start.flow.progress.plot"
            case progressSeason = "start.flow.progress.season"
            case progressTags = "start.flow.progress.tags"
            case progressConfirmation = "start.flow.progress.confirmation"
            case stepCountFormat = "start.flow.step_count_format"
            case stepCountAccessibilityFormat = "start.flow.step_count_accessibility_format"
            case stepHeaderFormat = "start.flow.step_header_format"
            case progressAccessibilityFormat = "start.flow.progress_accessibility_format"

            fileprivate var fallback: String {
                switch self {
                case .cancel: return "取消"
                case .navigationTitle: return "新建扫描"
                case .previous: return "上一步"
                case .next: return "下一步"
                case .launching: return "启动中..."
                case .launch: return "开始扫描"
                case .progressIdentifier: return "编号"
                case .progressPlot: return "地块"
                case .progressSeason: return "季节"
                case .progressTags: return "标签"
                case .progressConfirmation: return "确认"
                case .stepCountFormat: return "%1$d / %2$d"
                case .stepCountAccessibilityFormat: return "第 %1$d 步，共 %2$d 步"
                case .stepHeaderFormat: return "步骤 %1$d/%2$d"
                case .progressAccessibilityFormat: return "第 %1$d 步，共 %2$d 步：%3$@"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static var cancel: String { text(.cancel) }
        static var navigationTitle: String { text(.navigationTitle) }
        static var previous: String { text(.previous) }
        static var next: String { text(.next) }
        static var launching: String { text(.launching) }
        static var launch: String { text(.launch) }

        static var progressLabels: [String] {
            [
                text(.progressIdentifier),
                text(.progressPlot),
                text(.progressSeason),
                text(.progressTags),
                text(.progressConfirmation)
            ]
        }

        static func stepCount(currentStep: Int, totalSteps: Int, in bundle: Bundle = .main) -> String {
            String(format: text(.stepCountFormat, in: bundle), currentStep, totalSteps)
        }

        static func stepCountAccessibility(
            currentStep: Int,
            totalSteps: Int,
            in bundle: Bundle = .main
        ) -> String {
            String(format: text(.stepCountAccessibilityFormat, in: bundle), currentStep, totalSteps)
        }

        static func stepHeader(step: Int, totalSteps: Int, in bundle: Bundle = .main) -> String {
            String(format: text(.stepHeaderFormat, in: bundle), step, totalSteps)
        }

        static func progressAccessibility(
            currentStep: Int,
            totalSteps: Int,
            label: String,
            in bundle: Bundle = .main
        ) -> String {
            String(
                format: text(.progressAccessibilityFormat, in: bundle),
                currentStep,
                totalSteps,
                label
            )
        }
    }

    // MARK: - Quick Scan
    enum QuickScan {
        static let navigationTitle = NSLocalizedString("quick_scan.navigation_title", value: "快速扫描", comment: "Quick scan navigation title")
        static let headerTitle = NSLocalizedString("quick_scan.header_title", value: "快速采集", comment: "Quick scan header title")
        static let headerSubtitle = NSLocalizedString("quick_scan.header_subtitle", value: "自动生成树编号，只确认现场状态后直接进入扫描。", comment: "Quick scan header subtitle")
        static let close = NSLocalizedString("quick_scan.close", value: "关闭", comment: "Close quick scan")
        static let gpsAvailable = NSLocalizedString("quick_scan.gps_available", value: "已记录当前位置", comment: "Quick scan GPS available")
        static let gpsUnavailable = NSLocalizedString("quick_scan.gps_unavailable", value: "未锁定 GPS，仍可先扫描", comment: "Quick scan GPS unavailable")
        static let launching = NSLocalizedString("quick_scan.launching", value: "启动中...", comment: "Quick scan launch in progress")
        static let launch = NSLocalizedString("quick_scan.launch", value: "开始快速扫描", comment: "Start quick scan")
        static let treeID = NSLocalizedString("quick_scan.tree_id", value: "树编号", comment: "Quick scan tree identifier label")
        static let treeIDValid = NSLocalizedString("quick_scan.tree_id_valid", value: "可用", comment: "Quick scan tree identifier is valid")
        static let treeIDInvalid = NSLocalizedString("quick_scan.tree_id_invalid", value: "无效", comment: "Quick scan tree identifier is invalid")
        static let treeIDRequired = NSLocalizedString("quick_scan.tree_id_required", value: "必填", comment: "Quick scan tree identifier is required")
        static let treeIDPlaceholder = NSLocalizedString("quick_scan.tree_id_placeholder", value: "自动生成", comment: "Quick scan tree identifier placeholder")

        private static let treeIDEmptyError = NSLocalizedString("quick_scan.tree_id_empty_error", value: "请输入果树编号", comment: "Empty quick scan tree identifier")
        private static let treeIDTooLongError = NSLocalizedString("quick_scan.tree_id_too_long_error", value: "编号最多 %d 个字符", comment: "Quick scan tree identifier is too long")
        private static let treeIDPathMarkerError = NSLocalizedString("quick_scan.tree_id_path_marker_error", value: "编号不能使用路径标记", comment: "Quick scan tree identifier is a path marker")
        private static let treeIDForbiddenError = NSLocalizedString("quick_scan.tree_id_forbidden_error", value: "编号不能包含 /、\\、: 或换行", comment: "Quick scan tree identifier has forbidden characters")

        static func validationError(for issue: TreeIdentifierPolicy.ValidationIssue) -> String {
            switch issue {
            case .empty:
                return treeIDEmptyError
            case .tooLong(let maximumCharacterCount):
                return String(format: treeIDTooLongError, maximumCharacterCount)
            case .pathMarker:
                return treeIDPathMarkerError
            case .forbiddenCharacters:
                return treeIDForbiddenError
            }
        }
    }

    // MARK: - Start Setup
    enum StartSetup {
        enum Key: String, CaseIterable {
            case identifierTitle = "start.setup.identifier.title"
            case identifierToolSubtitle = "start.setup.identifier.tool_subtitle"
            case identifierSubtitle = "start.setup.identifier.subtitle"
            case identifierNote = "start.setup.identifier.note"
            case identifierFieldLabel = "start.setup.identifier.field_label"
            case identifierPlaceholder = "start.setup.identifier.placeholder"
            case identifierAvailable = "start.setup.identifier.status.available"
            case identifierInvalid = "start.setup.identifier.status.invalid"
            case identifierRequired = "start.setup.identifier.status.required"
            case identifierErrorEmpty = "start.setup.identifier.error.empty"
            case identifierErrorTooLong = "start.setup.identifier.error.too_long"
            case identifierErrorPathMarker = "start.setup.identifier.error.path_marker"
            case identifierErrorForbidden = "start.setup.identifier.error.forbidden"
            case plotToolTitle = "start.setup.plot.tool_title"
            case plotToolSubtitle = "start.setup.plot.tool_subtitle"
            case plotTitle = "start.setup.plot.title"
            case plotSubtitle = "start.setup.plot.subtitle"
            case plotEmptyTitle = "start.setup.plot.empty.title"
            case plotEmptyMessage = "start.setup.plot.empty.message"
            case plotCreate = "start.setup.plot.create"
            case plotNoneTitle = "start.setup.plot.none.title"
            case plotNoneSubtitle = "start.setup.plot.none.subtitle"
            case plotAssignedSubtitle = "start.setup.plot.assigned_subtitle"
            case plotAdd = "start.setup.plot.add"
            case seasonTitle = "start.setup.season.title"
            case seasonToolSubtitle = "start.setup.season.tool_subtitle"
            case seasonSubtitle = "start.setup.season.subtitle"
            case seasonNote = "start.setup.season.note"
            case seasonMatureTitle = "start.setup.season.mature.title"
            case seasonMatureSubtitle = "start.setup.season.mature.subtitle"
            case seasonOffTitle = "start.setup.season.off.title"
            case seasonOffSubtitle = "start.setup.season.off.subtitle"
            case seasonCalibrationPending = "start.setup.season.calibration_pending"
            case tagsToolTitle = "start.setup.tags.tool_title"
            case tagsToolSubtitle = "start.setup.tags.tool_subtitle"
            case tagsTitle = "start.setup.tags.title"
            case tagsSubtitle = "start.setup.tags.subtitle"
            case tagsEmptyTitle = "start.setup.tags.empty.title"
            case tagsEmptyMessage = "start.setup.tags.empty.message"
            case tagsCreate = "start.setup.tags.create"
            case tagsAdd = "start.setup.tags.add"
            case tagsSelectedCount = "start.setup.tags.selected_count"
            case confirmationToolTitle = "start.setup.confirmation.tool_title"
            case confirmationToolSubtitle = "start.setup.confirmation.tool_subtitle"
            case confirmationTitle = "start.setup.confirmation.title"
            case confirmationSubtitle = "start.setup.confirmation.subtitle"
            case confirmationUnassigned = "start.setup.confirmation.unassigned"
            case confirmationMatureSeason = "start.setup.confirmation.season.mature"
            case confirmationOffSeason = "start.setup.confirmation.season.off"
            case confirmationNone = "start.setup.confirmation.none"
            case confirmationTagSeparator = "start.setup.confirmation.tag_separator"
            case confirmationGPSAvailable = "start.setup.confirmation.gps.available"
            case confirmationGPSPending = "start.setup.confirmation.gps.pending"
            case confirmationNote = "start.setup.confirmation.note"

            fileprivate var fallback: String {
                switch self {
                case .identifierTitle:
                    return "果树编号"
                case .identifierToolSubtitle:
                    return "先建立可追踪的树体档案，后续记录会自动归到这个编号。"
                case .identifierSubtitle:
                    return "用于记录、导出和后续对比，建议与果园现场编号一致。"
                case .identifierNote:
                    return "编号会写入扫描记录和导出文件，不会影响点云采集本身。"
                case .identifierFieldLabel:
                    return "编号"
                case .identifierPlaceholder:
                    return "例：T001"
                case .identifierAvailable:
                    return "可用"
                case .identifierInvalid:
                    return "无效"
                case .identifierRequired:
                    return "必填"
                case .identifierErrorEmpty:
                    return "请输入果树编号"
                case .identifierErrorTooLong:
                    return "编号最多 %d 个字符"
                case .identifierErrorPathMarker:
                    return "编号不能使用路径标记"
                case .identifierErrorForbidden:
                    return "编号不能包含 /、\\、: 或换行"
                case .plotToolTitle:
                    return "地块归档"
                case .plotToolSubtitle:
                    return "把扫描挂到对应地块，便于之后按区域筛选和汇总。"
                case .plotTitle:
                    return "地块"
                case .plotSubtitle:
                    return "可选。用于后续按地块筛选和汇总。"
                case .plotEmptyTitle:
                    return "还没有地块"
                case .plotEmptyMessage:
                    return "这次扫描可以跳过，之后也能在标签管理中维护。"
                case .plotCreate:
                    return "创建地块"
                case .plotNoneTitle:
                    return "暂不分配"
                case .plotNoneSubtitle:
                    return "扫描完成后再归档到地块"
                case .plotAssignedSubtitle:
                    return "分配到该地块"
                case .plotAdd:
                    return "添加地块"
                case .seasonTitle:
                    return "估算阶段"
                case .seasonToolSubtitle:
                    return "当前开放成熟期融合估算；冠层回归完成实测标定后开放。"
                case .seasonSubtitle:
                    return "当前仅开放已具备可靠输入的成熟期估算。"
                case .seasonNote:
                    return "非成熟期冠层路线需先用真实称重数据完成模型标定，避免输出缺乏依据的产量。"
                case .seasonMatureTitle:
                    return "成熟期"
                case .seasonMatureSubtitle:
                    return "RGB + LiDAR 果实融合估算"
                case .seasonOffTitle:
                    return "非成熟期（待标定）"
                case .seasonOffSubtitle:
                    return "冠层回归尚缺实测系数，暂不可选择"
                case .seasonCalibrationPending:
                    return "待标定"
                case .tagsToolTitle:
                    return "标签分组"
                case .tagsToolSubtitle:
                    return "用标签标记品种、试验组或管理状态，方便后续复盘。"
                case .tagsTitle:
                    return "标签"
                case .tagsSubtitle:
                    return "可选。用于标记品种、试验组或管理状态。"
                case .tagsEmptyTitle:
                    return "还没有标签"
                case .tagsEmptyMessage:
                    return "标签可以跳过，不会影响扫描。"
                case .tagsCreate:
                    return "创建标签"
                case .tagsAdd:
                    return "添加"
                case .tagsSelectedCount:
                    return "已选 %d 个标签"
                case .confirmationToolTitle:
                    return "启动扫描"
                case .confirmationToolSubtitle:
                    return "确认信息后进入 LiDAR 采集，请围绕树体缓慢移动。"
                case .confirmationTitle:
                    return "启动前检查"
                case .confirmationSubtitle:
                    return "确认编号、分组和定位状态。"
                case .confirmationUnassigned:
                    return "未分配"
                case .confirmationMatureSeason:
                    return "成熟期（RGB + LiDAR 融合）"
                case .confirmationOffSeason:
                    return "非成熟期（待标定）"
                case .confirmationNone:
                    return "无"
                case .confirmationTagSeparator:
                    return "、"
                case .confirmationGPSAvailable:
                    return "已获取"
                case .confirmationGPSPending:
                    return "获取中..."
                case .confirmationNote:
                    return "开始后请围绕树体缓慢移动，尽量让树冠与果实进入稳定视野。"
                }
            }
        }

        static func text(_ key: Key, in bundle: Bundle = .main) -> String {
            bundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
        }

        static func selectedTagCount(_ count: Int, in bundle: Bundle = .main) -> String {
            String.localizedStringWithFormat(text(.tagsSelectedCount, in: bundle), count)
        }

        static func tagSummary(
            names: [String],
            remainingCount: Int = 0,
            in bundle: Bundle = .main
        ) -> String {
            let visibleNames = names.joined(separator: text(.confirmationTagSeparator, in: bundle))
            guard remainingCount > 0 else { return visibleNames }
            return "\(visibleNames) +\(remainingCount)"
        }

        static func validationError(
            for issue: TreeIdentifierPolicy.ValidationIssue,
            in bundle: Bundle = .main
        ) -> String {
            switch issue {
            case .empty:
                return text(.identifierErrorEmpty, in: bundle)
            case .tooLong(let maximumCharacterCount):
                return String(
                    format: text(.identifierErrorTooLong, in: bundle),
                    maximumCharacterCount
                )
            case .pathMarker:
                return text(.identifierErrorPathMarker, in: bundle)
            case .forbiddenCharacters:
                return text(.identifierErrorForbidden, in: bundle)
            }
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = NSLocalizedString("settings.title", value: "设置", comment: "Settings title")
        static let deviceSection = NSLocalizedString("settings.section.device", value: "设备", comment: "Device settings section")
        static let cameraSettings = NSLocalizedString("settings.camera_settings", value: "相机设置", comment: "Camera settings destination")
        static let cameraSettingsSubtitle = NSLocalizedString("settings.camera_settings_subtitle", value: "分辨率与采集帧率", comment: "Camera settings destination description")
        static let actualResolution = NSLocalizedString("settings.actual_resolution", value: "实际分辨率", comment: "Active camera resolution")
        static let dataSection = NSLocalizedString("settings.section.data", value: "数据", comment: "Data settings section")
        static let fruitType = NSLocalizedString("settings.fruit_type", value: "水果类型", comment: "Fruit type setting")
        static let autoExportCSV = NSLocalizedString("settings.auto_export_csv", value: "扫描后自动导出", comment: "Auto export CSV toggle")
        static let autoExportCSVHint = NSLocalizedString("settings.auto_export_csv_hint", value: "扫描完成后自动导出 CSV 文件。", comment: "Auto export CSV accessibility hint")
        static let scanSection = NSLocalizedString("settings.section.scan", value: "扫描", comment: "Scan settings section")
        static let currentFruitType = NSLocalizedString("settings.current_fruit_type", value: "当前水果类型", comment: "Current fruit type setting")
        static let fruitTypeHint = NSLocalizedString("settings.fruit_type_hint", value: "用于图像检测、点云聚类与产量换算。", comment: "Fruit type setting explanation")
        static let varietyDatabase = NSLocalizedString("settings.variety_database", value: "品种参数库", comment: "Fruit variety parameters destination")
        static let varietyDatabaseSubtitle = NSLocalizedString("settings.variety_database_subtitle", value: "编辑当前水果的尺寸、重量与聚类参数", comment: "Fruit variety parameters destination description")
        static let scanQuality = NSLocalizedString("settings.scan_quality", value: "质量预设", comment: "Scan quality preset")
        static let qualityHigh = NSLocalizedString("settings.quality.high", value: "高", comment: "High quality preset display name")
        static let qualityMedium = NSLocalizedString("settings.quality.medium", value: "中", comment: "Medium quality preset display name")
        static let qualityLow = NSLocalizedString("settings.quality.low", value: "低", comment: "Low quality preset display name")
        static let qualityHint = NSLocalizedString("settings.quality_hint", value: "高质量会提高深度置信度门槛，点云更干净，但弱光或快速移动时可能需要补扫。", comment: "Scan quality preset explanation")
        static let maxPoints = NSLocalizedString("settings.max_points", value: "最大点数", comment: "Maximum point count setting")
        static let maxPointsHint = NSLocalizedString("settings.max_points_hint", value: "更多点能保留更多细节，但会增加内存占用、导出文件大小和结果计算时间。", comment: "Maximum point count explanation")
        static let precision = NSLocalizedString("settings.precision", value: "精度", comment: "Scan precision setting")
        static let precisionHint = NSLocalizedString("settings.precision_hint", value: "更小的值会减少体素采样间隔，适合细枝和小果，但分析时间更长。", comment: "Scan precision explanation")
        static let targetResolution = NSLocalizedString("settings.target_resolution", value: "目标分辨率", comment: "Target camera resolution")
        static let captureFrameRate = NSLocalizedString("settings.capture_frame_rate", value: "采集帧率", comment: "Camera capture frame rate")
        static let cameraFormatHint = NSLocalizedString("settings.camera_format_hint", value: "ARKit 会为目标分辨率和帧率选择最接近的可用相机格式；实际结果取决于设备能力和系统负载。", comment: "Camera format selection explanation")
        static let sectionExpanded = NSLocalizedString("settings.section_expanded", value: "已展开", comment: "Expanded settings section accessibility value")
        static let sectionCollapsed = NSLocalizedString("settings.section_collapsed", value: "已折叠", comment: "Collapsed settings section accessibility value")
        static let sectionToggleHint = NSLocalizedString("settings.section_toggle_hint", value: "轻点两下即可展开或折叠此分区。", comment: "Expandable settings section accessibility hint")

        private static let maxPointsValueFormat = NSLocalizedString("settings.max_points_value", value: "%@ 点", comment: "Localized maximum point count value")
        private static let centimetersValueFormat = NSLocalizedString("settings.centimeters_value", value: "%@ cm", comment: "Localized centimeter value")

        static func qualityPresetName(for rawValue: String) -> String {
            switch rawValue {
            case "高": return qualityHigh
            case "中": return qualityMedium
            case "低": return qualityLow
            default: return rawValue
            }
        }

        static func maxPointCountValue(_ value: Int) -> String {
            let number = value.formatted(.number.grouping(.automatic))
            return String(format: maxPointsValueFormat, number)
        }

        static func precisionValue(_ centimeters: Double) -> String {
            let number = centimeters.formatted(.number.precision(.fractionLength(1)))
            return String(format: centimetersValueFormat, number)
        }
    }

    // MARK: - Variety Parameters
    enum VarietyDatabase {
        static let title = NSLocalizedString("variety.title", value: "品种参数库", comment: "Variety parameter database title")
        static let moreActions = NSLocalizedString("variety.more_actions", value: "更多品种操作", comment: "Variety parameter toolbar menu accessibility label")
        static let resetAll = NSLocalizedString("variety.reset_all", value: "重置所有参数", comment: "Reset all variety parameters action")
        static let resetAllMessage = NSLocalizedString("variety.reset_all_message", value: "确定要将所有品种参数重置为默认值吗？此操作无法撤销。", comment: "Reset all variety parameters confirmation message")
        static let reset = NSLocalizedString("variety.reset", value: "重置", comment: "Reset variety parameters action")
        static let searchPrompt = NSLocalizedString("variety.search_prompt", value: "搜索品种", comment: "Variety search field prompt")
        static let activeScanFormat = NSLocalizedString("variety.active_scan", value: "当前扫描：%@", comment: "Current scan variety summary")
        static let customizedCountFormat = NSLocalizedString("variety.customized_count", value: "已自定义品种：%d", comment: "Customized variety count summary")
        static let searchResultsFormat = NSLocalizedString("variety.search_results", value: "搜索结果：%d", comment: "Variety search result count")
        static let searchEmptyTitle = NSLocalizedString("variety.search_empty_title", value: "没有匹配的品种", comment: "Empty variety search title")
        static let searchEmptyMessageFormat = NSLocalizedString("variety.search_empty_message", value: "未找到与“%@”匹配的参数。", comment: "Empty variety search message")
        static let current = NSLocalizedString("variety.current", value: "当前", comment: "Current variety badge")
        static let currentAccessibilityFormat = NSLocalizedString("variety.current_accessibility", value: "%@，当前扫描品种", comment: "Current scan variety accessibility label")
        static let useAccessibilityFormat = NSLocalizedString("variety.use_accessibility", value: "将%@设为扫描品种", comment: "Use variety accessibility label")
        static let useHint = NSLocalizedString("variety.use_hint", value: "设为后续扫描使用的品种。", comment: "Use variety accessibility hint")
        static let customizedAccessibilityFormat = NSLocalizedString("variety.customized_accessibility", value: "%@，参数已自定义", comment: "Customized variety accessibility label")
        static let editAccessibilityFormat = NSLocalizedString("variety.edit_accessibility", value: "编辑%@参数", comment: "Edit variety accessibility label")
        static let diameterChip = NSLocalizedString("variety.chip.diameter", value: "直径", comment: "Diameter parameter chip label")
        static let averageWeightChip = NSLocalizedString("variety.chip.average_weight", value: "均重", comment: "Average weight parameter chip label")
        static let epsChip = NSLocalizedString("variety.chip.eps", value: "Eps", comment: "DBSCAN epsilon parameter chip label")
        static let editTitleFormat = NSLocalizedString("variety.edit_title", value: "编辑%@", comment: "Edit variety parameters title")
        static let editImpactFormat = NSLocalizedString("variety.edit_impact", value: "调整参数会影响%@的检测和产量估算结果。", comment: "Variety parameter impact explanation")
        static let sizeSection = NSLocalizedString("variety.section.size", value: "果实尺寸", comment: "Fruit size section title")
        static let minimumDiameter = NSLocalizedString("variety.minimum_diameter", value: "最小直径", comment: "Minimum fruit diameter control")
        static let maximumDiameter = NSLocalizedString("variety.maximum_diameter", value: "最大直径", comment: "Maximum fruit diameter control")
        static let weightDensitySection = NSLocalizedString("variety.section.weight_density", value: "重量与密度", comment: "Weight and density section title")
        static let averageWeight = NSLocalizedString("variety.average_weight", value: "平均单果重量", comment: "Average fruit weight control")
        static let density = NSLocalizedString("variety.density", value: "密度", comment: "Fruit density control")
        static let thresholdsSection = NSLocalizedString("variety.section.thresholds", value: "检测阈值", comment: "Detection thresholds section title")
        static let sphericityThreshold = NSLocalizedString("variety.sphericity_threshold", value: "球形度阈值", comment: "Sphericity threshold control")
        static let clusteringSection = NSLocalizedString("variety.section.clustering", value: "聚类参数", comment: "Clustering parameters section title")
        static let clusterRadius = NSLocalizedString("variety.cluster_radius", value: "聚类半径 (Eps)", comment: "Clustering radius control")
        static let resetDefault = NSLocalizedString("variety.reset_default", value: "重置为默认值", comment: "Reset one variety to defaults action")
        static let resetParameterTitle = NSLocalizedString("variety.reset_parameter_title", value: "重置参数", comment: "Reset one variety parameters alert title")
        static let resetParameterMessage = NSLocalizedString("variety.reset_parameter_message", value: "确定要将此品种重置为默认参数吗？", comment: "Reset one variety parameters confirmation")
        static let sliderHint = NSLocalizedString("variety.slider_hint", value: "上下轻扫以调整数值。", comment: "Variety parameter slider accessibility hint")
        static let unitValueFormat = NSLocalizedString("variety.unit_value", value: "%@ %@", comment: "Parameter value followed by an abbreviated unit")
        static let diameterRangeFormat = NSLocalizedString("variety.diameter_range", value: "%@–%@ %@", comment: "Minimum and maximum diameter followed by abbreviated unit")

        static func activeScan(_ varietyName: String) -> String {
            String(format: activeScanFormat, varietyName)
        }

        static func customizedCount(_ count: Int) -> String {
            String(format: customizedCountFormat, count)
        }

        static func searchResults(_ count: Int) -> String {
            String(format: searchResultsFormat, count)
        }

        static func searchEmptyMessage(_ query: String) -> String {
            String(format: searchEmptyMessageFormat, query)
        }

        static func currentAccessibility(_ varietyName: String) -> String {
            String(format: currentAccessibilityFormat, varietyName)
        }

        static func useAccessibility(_ varietyName: String) -> String {
            String(format: useAccessibilityFormat, varietyName)
        }

        static func customizedAccessibility(_ varietyName: String) -> String {
            String(format: customizedAccessibilityFormat, varietyName)
        }

        static func editAccessibility(_ varietyName: String) -> String {
            String(format: editAccessibilityFormat, varietyName)
        }

        static func editTitle(_ varietyName: String) -> String {
            String(format: editTitleFormat, varietyName)
        }

        static func editImpact(_ varietyName: String) -> String {
            String(format: editImpactFormat, varietyName)
        }

        static func unitValue(_ value: String, unit: String) -> String {
            String(format: unitValueFormat, value, unit)
        }

        static func diameterRange(minimum: String, maximum: String, unit: String) -> String {
            String(format: diameterRangeFormat, minimum, maximum, unit)
        }
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

    // MARK: - Scan HUD
    enum ScanHUD {
        static let wholeTree = NSLocalizedString("scan.hud.whole_tree", value: "果树全株", comment: "Whole-tree scan badge")
        private static let treeIDFormat = NSLocalizedString("scan.hud.tree_id_format", value: "树号 %@", comment: "Tree identifier displayed in scan HUD")
        static let treeID = NSLocalizedString("scan.hud.metric.tree_id", value: "树号", comment: "Tree identifier metric label")
        static let coverage = NSLocalizedString("scan.hud.metric.coverage", value: "覆盖", comment: "Scan coverage metric label")
        static let fruitCount = NSLocalizedString("scan.hud.metric.fruit_count", value: "果数", comment: "Detected fruit count metric label")
        static let quality = NSLocalizedString("scan.hud.metric.quality", value: "质量", comment: "Scan quality metric label")
        static let depth = NSLocalizedString("scan.hud.metric.depth", value: "深度", comment: "Depth status metric label")
        static let points = NSLocalizedString("scan.hud.metric.points", value: "点数", comment: "Point count metric label")
        static let vision = NSLocalizedString("scan.hud.metric.vision", value: "图像", comment: "Vision status metric label")
        static let model = NSLocalizedString("scan.hud.metric.model", value: "模型", comment: "Vision model metric label")
        static let pointCloud = NSLocalizedString("scan.hud.metric.point_cloud", value: "点云", comment: "Point-cloud status metric label")
        static let frames = NSLocalizedString("scan.hud.metric.frames", value: "帧数", comment: "Processed frame count metric label")
        static let fusion = NSLocalizedString("scan.hud.metric.fusion", value: "融合", comment: "Fusion status metric label")
        static let density = NSLocalizedString("scan.hud.metric.density", value: "密度", comment: "Point density metric label")
        static let lighting = NSLocalizedString("scan.hud.metric.lighting", value: "光照", comment: "Lighting metric label")

        static let ready = NSLocalizedString("scan.hud.state.ready", value: "就绪", comment: "Ready scan state")
        static let recording = NSLocalizedString("scan.hud.state.recording", value: "采集中", comment: "Recording scan state")
        static let processing = NSLocalizedString("scan.hud.state.processing", value: "处理中", comment: "Processing scan state")
        static let error = NSLocalizedString("scan.hud.state.error", value: "错误", comment: "Error scan state")

        static let routeTrunk = NSLocalizedString("scan.hud.route.trunk", value: "从主干开始，慢速绕树一圈", comment: "Initial scan route guidance")
        static let routeDiscovering = NSLocalizedString("scan.hud.route.discovering", value: "正在发现新区域，继续保持树冠在画面中", comment: "Active discovery scan guidance")
        static let routeFinishing = NSLocalizedString("scan.hud.route.finishing", value: "接近完成，补树冠背面和下层枝条", comment: "Nearly complete scan guidance")
        static let routeStable = NSLocalizedString("scan.hud.route.stable", value: "覆盖稳定，可以停止录制并进入粗预览", comment: "Stable coverage scan guidance")

        static let onDevice = NSLocalizedString("scan.hud.vision.on_device", value: "本机", comment: "On-device vision status")
        static let fallback = NSLocalizedString("scan.hud.vision.fallback", value: "备用", comment: "Fallback vision status")
        static let modelNotLoaded = NSLocalizedString("scan.hud.vision.model_not_loaded", value: "未载入", comment: "Vision model not loaded")
        static let modelLoaded = NSLocalizedString("scan.hud.vision.model_loaded", value: "已载入", comment: "Vision model loaded")

        static let available = NSLocalizedString("scan.hud.runtime.available", value: "可用", comment: "Runtime resource available")
        static let waiting = NSLocalizedString("scan.hud.runtime.waiting", value: "等待", comment: "Runtime resource waiting")
        static let noDepth = NSLocalizedString("scan.hud.runtime.no_depth", value: "无深度", comment: "Depth unavailable on device")
        static let unavailable = NSLocalizedString("scan.hud.runtime.unavailable", value: "不可用", comment: "Runtime resource unavailable")
        static let exportable = NSLocalizedString("scan.hud.runtime.exportable", value: "可导出", comment: "Point cloud ready for export")
        static let fused = NSLocalizedString("scan.hud.runtime.fused", value: "已融合", comment: "Fusion completed")
        static let lowConfidence = NSLocalizedString("scan.hud.runtime.low_confidence", value: "低置信", comment: "Low-confidence fusion status")
        static let scanning = NSLocalizedString("scan.hud.runtime.scanning", value: "扫描中", comment: "Scanning in progress")
        static let rescanning = NSLocalizedString("scan.hud.runtime.rescanning", value: "补扫中", comment: "Supplemental scanning in progress")
        static let interrupted = NSLocalizedString("scan.hud.runtime.interrupted", value: "已中断", comment: "Scan interrupted")
        static let failed = NSLocalizedString("scan.hud.runtime.failed", value: "失败", comment: "Scan failed")

        static let qualityPoor = NSLocalizedString("scan.hud.quality.poor", value: "差", comment: "Poor scan quality")
        static let qualityFair = NSLocalizedString("scan.hud.quality.fair", value: "一般", comment: "Fair scan quality")
        static let qualityGood = NSLocalizedString("scan.hud.quality.good", value: "良好", comment: "Good scan quality")
        static let qualityExcellent = NSLocalizedString("scan.hud.quality.excellent", value: "优秀", comment: "Excellent scan quality")
        static let qualityOutstanding = NSLocalizedString("scan.hud.quality.outstanding", value: "极佳", comment: "Outstanding scan quality")

        static func treeIdentifier(_ identifier: String) -> String {
            String(format: treeIDFormat, identifier)
        }
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

    // MARK: - Import
    enum Import {
        static let navigationTitle = NSLocalizedString("import.navigation_title", value: "导入文件", comment: "PLY import navigation title")
        static let headerTitle = NSLocalizedString("import.header_title", value: "点云导入", comment: "PLY import header title")
        static let headerSubtitle = NSLocalizedString("import.header_subtitle", value: "把已有 PLY 点云加入扫描记录，用于查看、对比和后续导出。", comment: "PLY import header subtitle")
        static let idleTitle = NSLocalizedString("import.status.idle_title", value: "等待选择 PLY 文件", comment: "PLY import idle-state title")
        static let idleMessage = NSLocalizedString("import.status.idle_message", value: "支持 ASCII 和 Binary PLY，导入后会写入本机扫描记录。", comment: "PLY import idle-state message")
        static let selectingTitle = NSLocalizedString("import.status.selecting_title", value: "请选择文件", comment: "PLY import file-selection title")
        static let selectingMessage = NSLocalizedString("import.status.selecting_message", value: "从文件应用中选择一个 .ply 点云文件。", comment: "PLY import file-selection message")
        static let processingTitle = NSLocalizedString("import.status.processing_title", value: "正在处理", comment: "PLY import processing title")
        static let successTitle = NSLocalizedString("import.status.success_title", value: "导入成功", comment: "PLY import success title")
        static let errorTitle = NSLocalizedString("import.status.error_title", value: "导入失败", comment: "PLY import failure title")
        static let selectButton = NSLocalizedString("import.button.select", value: "选择 PLY 文件", comment: "Select a PLY file action")
        static let continueButton = NSLocalizedString("import.button.continue", value: "继续导入 PLY 文件", comment: "Import another PLY file action")
        static let historyRule = NSLocalizedString("import.rule.history", value: "导入后会出现在扫描记录", comment: "Imported file history rule")
        static let metadataRule = NSLocalizedString("import.rule.metadata", value: "保留可读取的扫描元数据", comment: "Imported metadata rule")
        static let duplicateRule = NSLocalizedString("import.rule.duplicate", value: "同名文件会自动生成新副本", comment: "Duplicate import rule")
        static let noFileError = NSLocalizedString("import.error.no_file", value: "未选择文件", comment: "No file selected import error")
        static let unsupportedFormatError = NSLocalizedString("import.error.unsupported_format", value: "当前导入记录只支持 PLY 点云文件", comment: "Unsupported import format error")
        static let invalidPLYError = NSLocalizedString("import.error.invalid_ply", value: "文件不是有效的 PLY 点云", comment: "Invalid PLY file error")
        static let invalidPointCloudError = NSLocalizedString("import.error.invalid_point_cloud", value: "PLY 点云数据不完整或当前无法读取", comment: "Unreadable PLY point-cloud error")

        private static let successMessageFormat = NSLocalizedString("import.status.success_message", value: "%@ 已添加到扫描记录，可继续导入或关闭此页。", comment: "PLY import success message containing the imported filename")

        static func successMessage(fileName: String) -> String {
            String(format: successMessageFormat, fileName)
        }
    }

    // MARK: - Point Cloud Preview
    enum PointCloud {
        static let navigationTitle = NSLocalizedString("point_cloud.navigation_title", value: "点云预览", comment: "Point-cloud preview navigation title")
        static let closePreviewAccessibility = NSLocalizedString("point_cloud.accessibility.close_preview", value: "关闭点云预览", comment: "Close point-cloud preview accessibility label")
        static let emptyTitle = NSLocalizedString("point_cloud.empty.title", value: "暂无扫描数据", comment: "Point-cloud preview empty-state title")
        static let emptyMessage = NSLocalizedString("point_cloud.empty.message", value: "完成扫描或导入 PLY 后，点云文件会自动出现在这里。", comment: "Point-cloud preview empty-state message")
        static let newScan = NSLocalizedString("point_cloud.action.new_scan", value: "新建扫描", comment: "Start a new scan from point-cloud preview")
        static let importPLY = NSLocalizedString("point_cloud.action.import_ply", value: "导入 PLY", comment: "Import a PLY file from point-cloud preview")

        static let loadingTitle = NSLocalizedString("point_cloud.status.loading_title", value: "正在读取点云", comment: "Point-cloud loading title")
        static let loadingMessage = NSLocalizedString("point_cloud.status.loading_message", value: "正在解析 PLY 点和颜色数据…", comment: "Point-cloud loading message")
        static let openErrorTitle = NSLocalizedString("point_cloud.status.error_title", value: "无法打开点云", comment: "Point-cloud load failure title")
        static let noFileTitle = NSLocalizedString("point_cloud.status.no_file_title", value: "暂无点云文件", comment: "Missing point-cloud file title")
        static let noFileMessage = NSLocalizedString("point_cloud.status.no_file_message", value: "完成扫描或导入 PLY 后，可在这里旋转、测量和分享点云。", comment: "Missing point-cloud file message")
        static let noPointsTitle = NSLocalizedString("point_cloud.status.no_points_title", value: "没有可显示的点", comment: "Empty point-cloud data title")
        static let noPointsMessage = NSLocalizedString("point_cloud.status.no_points_message", value: "该文件未解析到有效点云，请检查 PLY 内容。", comment: "Empty point-cloud data message")
        static let loadFailed = NSLocalizedString("point_cloud.error.load_failed", value: "无法读取点云文件。", comment: "Point-cloud parser failure")

        static let searchPlaceholder = NSLocalizedString("point_cloud.selector.search_placeholder", value: "搜索编号", comment: "Point-cloud record search placeholder")
        static let clearSearchAccessibility = NSLocalizedString("point_cloud.accessibility.clear_search", value: "清除搜索", comment: "Clear point-cloud search accessibility label")
        static let viewerTitle = NSLocalizedString("point_cloud.viewer.title", value: "点云查看", comment: "Point-cloud viewer title")
        static let shareAccessibility = NSLocalizedString("point_cloud.accessibility.share", value: "分享点云", comment: "Share point-cloud accessibility label")

        static let pointsMetric = NSLocalizedString("point_cloud.metric.points", value: "点", comment: "Compact point-count metric label")
        static let heightMetric = NSLocalizedString("point_cloud.metric.height", value: "高", comment: "Compact point-cloud height metric label")
        static let footprintMetric = NSLocalizedString("point_cloud.metric.footprint", value: "冠幅", comment: "Compact crown-footprint metric label")

        static let reset = NSLocalizedString("point_cloud.tool.reset", value: "重置", comment: "Reset point-cloud camera")
        static let color = NSLocalizedString("point_cloud.tool.color", value: "色彩", comment: "Point-cloud color tool")
        static let zoomIn = NSLocalizedString("point_cloud.tool.zoom_in", value: "放大", comment: "Zoom in point-cloud view")
        static let zoomOut = NSLocalizedString("point_cloud.tool.zoom_out", value: "缩小", comment: "Zoom out point-cloud view")
        static let measure = NSLocalizedString("point_cloud.tool.measure", value: "测量", comment: "Point-cloud measurement tool")

        static let legendLow = NSLocalizedString("point_cloud.legend.low", value: "低", comment: "Low end of point-cloud height legend")
        static let legendHigh = NSLocalizedString("point_cloud.legend.high", value: "高", comment: "High end of point-cloud height legend")
        static let legendSparse = NSLocalizedString("point_cloud.legend.sparse", value: "稀", comment: "Sparse end of point-cloud density legend")
        static let legendDense = NSLocalizedString("point_cloud.legend.dense", value: "密", comment: "Dense end of point-cloud density legend")
        static let legendFruitCandidates = NSLocalizedString("point_cloud.legend.fruit_candidates", value: "果实候选", comment: "Fruit candidates in point-cloud legend")
        static let legendUniformBright = NSLocalizedString("point_cloud.legend.uniform_bright", value: "统一亮色", comment: "Uniform bright point-cloud legend")

        static let viewOrbit = NSLocalizedString("point_cloud.view.orbit", value: "自由", comment: "Orbit point-cloud view mode")
        static let viewFront = NSLocalizedString("point_cloud.view.front", value: "正面", comment: "Front point-cloud view mode")
        static let viewTop = NSLocalizedString("point_cloud.view.top", value: "俯视", comment: "Top point-cloud view mode")
        static let viewSide = NSLocalizedString("point_cloud.view.side", value: "侧面", comment: "Side point-cloud view mode")
        static let viewDetailOrbit = NSLocalizedString("point_cloud.view_detail.orbit", value: "透视旋转", comment: "Orbit view-mode detail")
        static let viewDetailFront = NSLocalizedString("point_cloud.view_detail.front", value: "高度轮廓", comment: "Front view-mode detail")
        static let viewDetailTop = NSLocalizedString("point_cloud.view_detail.top", value: "冠层投影", comment: "Top view-mode detail")
        static let viewDetailSide = NSLocalizedString("point_cloud.view_detail.side", value: "侧向轮廓", comment: "Side view-mode detail")

        static let colorHeight = NSLocalizedString("point_cloud.color.height", value: "高度", comment: "Height point-cloud color mode")
        static let colorDensity = NSLocalizedString("point_cloud.color.density", value: "密度", comment: "Density point-cloud color mode")
        static let colorFruit = NSLocalizedString("point_cloud.color.fruit", value: "果实", comment: "Fruit point-cloud color mode")
        static let colorUniform = NSLocalizedString("point_cloud.color.uniform", value: "统一", comment: "Uniform point-cloud color mode")

        static let measurementStart = NSLocalizedString("point_cloud.measurement.start", value: "起点", comment: "Point-cloud measurement start")
        static let measurementEnd = NSLocalizedString("point_cloud.measurement.end", value: "终点", comment: "Point-cloud measurement end")
        static let measurementInstruction = NSLocalizedString("point_cloud.measurement.instruction", value: "点击点云表面测量", comment: "Point-cloud measurement instruction")
        static let measurementDistance = NSLocalizedString("point_cloud.measurement.distance", value: "测量距离", comment: "Point-cloud measured distance label")
        static let closeMeasurementAccessibility = NSLocalizedString("point_cloud.accessibility.close_measurement", value: "停止测量", comment: "Stop point-cloud measurement accessibility label")

        enum ScanMeasurementPrompt: String, CaseIterable {
            case selectFirst = "scan.measurement.prompt.select_first"
            case recordPointCloud = "scan.measurement.prompt.record_point_cloud"
            case surfaceNotFound = "scan.measurement.prompt.surface_not_found"
            case selectSecond = "scan.measurement.prompt.select_second"
            case complete = "scan.measurement.prompt.complete"

            fileprivate var fallback: String {
                switch self {
                case .selectFirst: return "点击第1个点"
                case .recordPointCloud: return "请先录制点云"
                case .surfaceNotFound: return "未选中点云，请点果树表面"
                case .selectSecond: return "点击第2个点"
                case .complete: return "测量完成，点击重置"
                }
            }
        }

        static func scanMeasurementPrompt(
            _ prompt: ScanMeasurementPrompt,
            in bundle: Bundle = .main
        ) -> String {
            bundle.localizedString(forKey: prompt.rawValue, value: prompt.fallback, table: nil)
        }

        static func scanMeasurementCalculating(in bundle: Bundle = .main) -> String {
            bundle.localizedString(
                forKey: "scan.measurement.calculating",
                value: "计算中…",
                table: nil
            )
        }

        static func scanMeasurementDistance(_ distance: Float, in bundle: Bundle = .main) -> String {
            let format = bundle.localizedString(
                forKey: "scan.measurement.distance_format",
                value: "%.2f m",
                table: nil
            )
            return String(format: format, Double(distance))
        }

        private static let noSearchResultsFormat = NSLocalizedString("point_cloud.selector.no_results", value: "未找到编号“%@”的记录", comment: "No point-cloud record matching the entered tree ID")
        private static let colorLegendFormat = NSLocalizedString("point_cloud.legend.color_format", value: "色彩：%@", comment: "Point-cloud color legend with selected mode")
        private static let actualHeightFormat = NSLocalizedString("point_cloud.legend.actual_height_format", value: "真实高度 %@", comment: "Actual point-cloud height")
        private static let pointCountAccessibilityFormat = NSLocalizedString("point_cloud.accessibility.point_count", value: "点数：%@", comment: "Point-count accessibility value")
        private static let heightAccessibilityFormat = NSLocalizedString("point_cloud.accessibility.height", value: "高度：%@", comment: "Point-cloud height accessibility value")
        private static let footprintAccessibilityFormat = NSLocalizedString("point_cloud.accessibility.footprint", value: "冠幅：%@", comment: "Crown-footprint accessibility value")

        static func noSearchResults(for treeID: String) -> String {
            String(format: noSearchResultsFormat, treeID)
        }

        static func colorLegend(modeName: String) -> String {
            String(format: colorLegendFormat, modeName)
        }

        static func actualHeight(_ height: String) -> String {
            String(format: actualHeightFormat, height)
        }

        static func pointCountAccessibility(_ count: String) -> String {
            String(format: pointCountAccessibilityFormat, count)
        }

        static func heightAccessibility(_ height: String) -> String {
            String(format: heightAccessibilityFormat, height)
        }

        static func footprintAccessibility(_ footprint: String) -> String {
            String(format: footprintAccessibilityFormat, footprint)
        }
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
