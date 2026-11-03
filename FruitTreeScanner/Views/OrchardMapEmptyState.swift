import SwiftUI

/// 地图空状态的文案。
///
/// 键与既有本地化表保持一致（`orchard_map.empty.*`），不新增键。
struct OrchardMapEmptyStatePresentation: Equatable {
    let title: String
    let message: String
    let startScanTitle: String

    init(bundle: Bundle = .main) {
        title = bundle.localizedString(
            forKey: "orchard_map.empty.title",
            value: "暂无定位扫描",
            table: nil
        )
        message = bundle.localizedString(
            forKey: "orchard_map.empty.message",
            value: "带 GPS 的完整扫描记录会显示在果园地图中，用于查看可靠产量分布。",
            table: nil
        )
        startScanTitle = bundle.localizedString(
            forKey: "orchard_map.empty.start_scan",
            value: "开始扫描",
            table: nil
        )
    }
}

/// 果园地图空板。
///
/// 没有定位记录时不说"地图是空的"，而是说明现在有什么、下一步做什么，
/// 并把无定位档案的去处（档案）留在可见位置。
struct OrchardMapEmptyState: View {
    private let onStartScan: (() -> Void)?
    private let onOpenArchive: (() -> Void)?
    private let presentation: OrchardMapEmptyStatePresentation

    init(
        onStartScan: (() -> Void)? = nil,
        onOpenArchive: (() -> Void)? = nil,
        bundle: Bundle = .main
    ) {
        self.onStartScan = onStartScan
        self.onOpenArchive = onOpenArchive
        presentation = OrchardMapEmptyStatePresentation(bundle: bundle)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                plate
                actions
                Spacer(minLength: Design.Space.xxl)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.lg)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Design.Colors.Workspace.background)
    }

    private var plate: some View {
        InstrumentSurveyPlate {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityHidden(true)
                    Text(presentation.title)
                        .font(.system(.headline, design: .default).weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DividerLine()

                Text(WorkspaceText.locationExplanation)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if let onStartScan {
                Button(action: onStartScan) {
                    Label(presentation.startScanTitle, systemImage: "viewfinder")
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .accessibilityIdentifier("orchard.map.startScan")
            }

            if let onOpenArchive {
                Button(action: onOpenArchive) {
                    Label(WorkspaceText.openArchives, systemImage: "square.stack.3d.up")
                }
                .buttonStyle(WorkspaceSecondaryButtonStyle())
                .accessibilityIdentifier("orchard.map.openArchive")
            }
        }
    }
}
