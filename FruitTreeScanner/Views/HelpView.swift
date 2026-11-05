// HelpView.swift
// 使用帮助：长文说明页。
//
// 版式：页面标题 + 小标签分区 + 列表组。行高按动态字号放大，
// 文本不设固定行数，任何 Dynamic Type 下都不会被裁切。

import SwiftUI

/// 帮助页的文案。放在视图文件内，避免与 Core/L10n.swift 的改动冲突。
enum HelpCopy {
    static let title = NSLocalizedString("help.title", value: "使用帮助", comment: "Help screen title")
    static let subtitle = NSLocalizedString(
        "help.subtitle",
        value: "扫描、估产与校准的操作要点：怎么走、看到什么、怎么复核。",
        comment: "Help screen subtitle"
    )
    static let sectionTitle = NSLocalizedString("help.section.title", value: "帮助", comment: "Help section title in settings")

    struct Section: Identifiable {
        let id: String
        let systemImage: String
        let title: String
        let items: [String]
    }

    static let sections: [Section] = [
        Section(
            id: "help.section.scan_tips",
            systemImage: "viewfinder",
            title: NSLocalizedString("help.section.scan_tips.title", value: "扫描技巧", comment: "Scanning tips section title"),
            items: [
                NSLocalizedString("help.item.distance", value: "保持设备与果树距离 1-3 米", comment: "Scanning tip"),
                NSLocalizedString("help.item.slow_move", value: "缓慢移动设备，从不同角度扫描", comment: "Scanning tip"),
                NSLocalizedString("help.item.no_shake", value: "避免快速移动或剧烈抖动", comment: "Scanning tip"),
                NSLocalizedString("help.item.tracking_quality", value: "确保追踪状态显示「优秀」或「良好」", comment: "Scanning tip"),
                NSLocalizedString("help.item.cover_all_sides", value: "尽量覆盖果树的各个面", comment: "Scanning tip")
            ]
        ),
        Section(
            id: "help.section.speed",
            systemImage: "hare.fill",
            title: NSLocalizedString("help.section.speed.title", value: "速度检测", comment: "Speed detection section title"),
            items: [
                NSLocalizedString("help.item.speed_too_fast", value: "「太快」：降低移动速度", comment: "Speed hint"),
                NSLocalizedString("help.item.speed_sparse", value: "「太快」：可能导致点云稀疏", comment: "Speed hint"),
                NSLocalizedString("help.item.speed_ideal", value: "「适中」：最佳扫描速度", comment: "Speed hint"),
                NSLocalizedString("help.item.speed_too_slow", value: "「太慢」：适当加快移动", comment: "Speed hint"),
                NSLocalizedString("help.item.speed_still", value: "「静止」：请移动设备进行扫描", comment: "Speed hint")
            ]
        ),
        Section(
            id: "help.section.tracking",
            systemImage: "location.fill",
            title: NSLocalizedString("help.section.tracking.title", value: "追踪状态", comment: "Tracking status section title"),
            items: [
                NSLocalizedString("help.item.tracking_excellent", value: "「优秀」：追踪正常，点云质量高", comment: "Tracking status"),
                NSLocalizedString("help.item.tracking_good", value: "「良好」：追踪正常，点云质量良好", comment: "Tracking status"),
                NSLocalizedString("help.item.tracking_fair", value: "「一般」：追踪受限，可能影响精度", comment: "Tracking status"),
                NSLocalizedString("help.item.tracking_lost", value: "「丢失」：追踪失败，请重新对准", comment: "Tracking status")
            ]
        ),
        Section(
            id: "help.section.detection",
            systemImage: "leaf.fill",
            title: NSLocalizedString("help.section.detection.title", value: "果实检测原理", comment: "Fruit detection section title"),
            items: [
                NSLocalizedString("help.item.detection_sources", value: "联合图像检测、LiDAR 深度与点云证据", comment: "Detection principle"),
                NSLocalizedString("help.item.detection_fusion", value: "通过空间定位和融合验证识别同一果实", comment: "Detection principle"),
                NSLocalizedString("help.item.detection_reliable", value: "只有融合验证通过的果实参与可靠估产", comment: "Detection principle"),
                NSLocalizedString("help.item.detection_review", value: "低质量与零产量结果需要结合诊断复核", comment: "Detection principle")
            ]
        ),
        Section(
            id: "help.section.calibration",
            systemImage: "slider.horizontal.3",
            title: NSLocalizedString("help.section.calibration.title", value: "算法校准", comment: "Calibration section title"),
            items: [
                NSLocalizedString("help.item.calibration_count", value: "扫描后记录实际果实数量", comment: "Calibration step"),
                NSLocalizedString("help.item.calibration_weight", value: "采摘后称重实际产量", comment: "Calibration step"),
                NSLocalizedString("help.item.calibration_entry", value: "在「算法校准」中录入数据", comment: "Calibration step"),
                NSLocalizedString("help.item.calibration_error", value: "系统计算误差帮您调整参数", comment: "Calibration step")
            ]
        )
    ]
}

struct HelpView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 长文正文的最大宽度：超过这个宽度中文行长就不好读了。
    private let readingWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                InstrumentPageHeader(
                    title: HelpCopy.title,
                    subtitle: HelpCopy.subtitle
                )

                ForEach(HelpCopy.sections) { section in
                    helpSection(section)
                }
            }
            .frame(maxWidth: readingWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .workspacePage()
        .navigationTitle(HelpCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Design.Colors.Workspace.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - 分区

    private func helpSection(_ section: HelpCopy.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .accessibilityHidden(true)
                Text(section.title)
                    .instrumentLabel()
            }

            InstrumentRowGroup {
                ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                    helpItem(item)
                    if index < section.items.count - 1 {
                        DividerLine()
                    }
                }
            }
        }
    }

    private func helpItem(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("—")
                .font(.body)
                .foregroundColor(Design.Colors.Workspace.faint)
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineSpacing(bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
    }

    // MARK: - 行高

    /// 行距随动态字号放大：字号越大，一行文字占的高度越大，需要更多行距。
    private var bodyLineSpacing: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium: return 4
        case .large: return 5
        case .xLarge: return 6
        case .xxLarge: return 7
        case .xxxLarge: return 8
        default: return 10
        }
    }
}
