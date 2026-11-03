// DashboardOrchardWorkspace.swift
// 果园空间：这棵树的点云证据是主视觉，地图是空间索引，工具在最后。
//
// 层级依据（见 docs/implementation/UI_DESIGN_SYSTEM.md 第 0 节）：
// 数字 → 这棵树的证据 → 空间位置 → 工具。

import MapKit
import SwiftUI

/// Saved evidence locations; never an invented orchard or a parallel record store.
struct DashboardOrchardWorkspace: View {
    let records: [ScanFileRecord]
    let wideLayout: Bool
    let mapHeight: CGFloat
    let onOpenMap: () -> Void
    let onScanTap: (ScanFileRecord) -> Void
    @State private var selectedTreeID: String?
    @ObservedObject private var surveyCatalog = TreeSurveyCatalog.shared

    private var trees: [TreeAnnotation] { OrchardMapData(records: records, surveyPoints: surveyCatalog.points).trees }
    private var selectedRecord: ScanFileRecord? {
        OrchardWorkspaceSelection.record(in: records, trees: trees, selectedTreeID: selectedTreeID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if records.isEmpty {
                emptyPlate
            } else if wideLayout {
                HStack(alignment: .top, spacing: 16) {
                    recordPanel.frame(maxWidth: .infinity)
                    mapPanel.frame(width: 300)
                }
            } else {
                recordPanel
                mapPanel
            }
        }
        .onChange(of: records) { _ in
            if let selectedTreeID, !trees.contains(where: { $0.treeID == selectedTreeID }) { self.selectedTreeID = nil }
        }
    }

    // MARK: - 主视觉：这棵树的证据

    @ViewBuilder
    private var recordPanel: some View {
        if let record = selectedRecord {
            DashboardTreeEvidenceCard(
                record: record,
                pointCloudAspect: wideLayout ? 16.0 / 9.0 : 16.0 / 10.0,
                onOpen: { onScanTap(record) }
            )
        } else {
            emptyPlate
        }
    }

    // MARK: - 空间索引

    private var mapPanel: some View {
        ZStack(alignment: .topTrailing) {
            if trees.isEmpty {
                emptyMap
            } else {
                // This API supports the app's iOS 16 deployment target.
                DashboardSavedTreeMap(
                    trees: trees, selectedID: selectedRecord?.id,
                    onSelect: { id in
                        selectedTreeID = trees.first { $0.id == id }?.treeID
                    })
                mapControl("arrow.up.left.and.arrow.down.right", label: WorkspaceText.openMap, action: onOpenMap)
                    .padding(10)
            }
        }
        .frame(height: wideLayout ? 230 : max(150, min(190, mapHeight)))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }

    // MARK: - 空状态

    private var emptyPlate: some View {
        InstrumentSurveyPlate {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityHidden(true)
                    Text(L10n.Dashboard.noScans)
                        .font(.system(.headline, design: .default).weight(.semibold))
                        .foregroundColor(Design.Colors.Workspace.ink)
                }
                Text(L10n.Dashboard.emptyDescription)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private var emptyMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Dashboard.noScans)
                .font(.system(.headline, design: .default).weight(.semibold))
            Text(L10n.Dashboard.emptyDescription)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mapControl(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .stroke(Design.Colors.Workspace.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

enum OrchardWorkspaceSelection {
    static func record(in records: [ScanFileRecord], trees: [TreeAnnotation], selectedTreeID: String?)
        -> ScanFileRecord?
    {
        let selectedTree = trees.first { $0.treeID == selectedTreeID } ?? trees.first
        if let selectedTree, let record = records.first(where: { $0.id == selectedTree.id }) { return record }
        return records.first
    }
}

// MARK: - 树体证据卡（主视觉）

/// 主视觉卡片：这棵树的真实点云 + 真实读数 + 证据等级。
private struct DashboardTreeEvidenceCard: View {
    let record: ScanFileRecord
    var pointCloudAspect: CGFloat = 16.0 / 10.0
    let onOpen: () -> Void

    private var presentation: ScanHistoryRecordPresentation { ScanHistoryRecordPresentation(record: record) }
    private var tier: InstrumentRecordTier { InstrumentRecord.tier(for: record) }

    var body: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: 14) {
                identity
                // 点云是主视觉：占满承载面宽度，按固定比例呈现。
                WorkspacePointCloudPreview(record: record)
                    .aspectRatio(pointCloudAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                readings
                openEvidenceLink
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.treeID)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(record.scanDate, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.muted)
        }
    }

    private var readings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { readingItems }
            VStack(alignment: .leading, spacing: 8) { readingItems }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var readingItems: some View {
        if let yieldKg = presentation.yieldKg {
            InstrumentDatum(
                label: WorkspaceText.estimatedYield,
                value: String(format: "%.1f", yieldKg),
                unit: "kg"
            )
        }
        if let fruitCount = presentation.fruitCount {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.Result.fruitCount)
                    .instrumentLabel()
                // 计数文本本身已含数字与单位，标签不再重复表达。
                Text(L10n.Dashboard.fruitCountLabel(fruitCount))
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Dashboard.fruitCountLabel(fruitCount))
        }
        InstrumentTierBadge(
            title: tierTitle,
            style: tier.markStyle,
            tint: tier.tint
        )
    }

    private var tierTitle: String {
        // 记录层面只说明“完整 / 待复核 / 需恢复”，不声称融合可靠性。
        InstrumentRecord.title(for: record)
    }

    private var openEvidenceLink: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 12, weight: .medium))
                Text(WorkspaceText.evidence)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(Design.Colors.Workspace.accent)
            .frame(minHeight: Design.Touch.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.orchard.evidence")
    }
}

// MARK: - 地图

private struct DashboardSavedTreeMap: View {
    let trees: [TreeAnnotation]
    let selectedID: String?
    let onSelect: (String) -> Void
    @State private var region: MKCoordinateRegion

    init(trees: [TreeAnnotation], selectedID: String?, onSelect: @escaping (String) -> Void) {
        self.trees = trees
        self.selectedID = selectedID
        self.onSelect = onSelect
        // This child is created only with located records, so Map never receives
        // the zero-span region used by the initial empty aggregation snapshot.
        _region = State(
            initialValue: OrchardMapRegionCalculator.region(for: trees)
                ?? MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
                ))
    }

    private var locationSignature: [String] {
        trees.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }
    }

    var body: some View {
        Group {
            if #available(iOS 17, *) {
                mapContent.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            } else {
                mapContent
            }
        }
        .accessibilityIdentifier("dashboard.orchard.map")
        .onChange(of: locationSignature) { _ in
            if let region = OrchardMapRegionCalculator.region(for: trees) { self.region = region }
        }
    }

    private var mapContent: some View {
        Map(coordinateRegion: $region, interactionModes: [.pan, .zoom], annotationItems: trees) { tree in
            MapAnnotation(coordinate: tree.coordinate) {
                Button {
                    onSelect(tree.id)
                } label: {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(pinColor(tree))
                        .frame(width: 9, height: 9)
                        .padding(4)
                        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(
                                    selectedID == tree.id ? Design.Colors.Workspace.accent : .clear,
                                    lineWidth: 1.5
                                )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .bottom) {
                            if selectedID == tree.id {
                                selectedLabel(tree.treeID)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tree.treeID)
                .accessibilityValue(OrchardMapPresentation().confidenceLabel(tree.confidence))
                .accessibilityAddTraits(selectedID == tree.id ? .isSelected : [])
            }
        }
    }

    private func selectedLabel(_ treeID: String) -> some View {
        Text(treeID)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(Design.Colors.Workspace.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
            .fixedSize()
    }

    private func pinColor(_ tree: TreeAnnotation) -> Color {
        ResultReviewPolicy.needsReview(tree.confidence)
            ? Design.Colors.Workspace.attention : Design.Colors.Workspace.accent
    }
}

// MARK: - 点云缩略图

/// A bounded visualization of the saved PLY, not a decorative stock tree.
private struct WorkspacePointCloudPreview: View {
    let record: ScanFileRecord
    @State private var points: [WorkspacePreviewPoint] = []
    @State private var totalCount: Int = 0
    @State private var isLoading = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(Design.Colors.Dark.bgDeep)

            if isLoading {
                ProgressView().tint(Design.Colors.Dark.glow)
            } else if points.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundColor(Design.Colors.Dark.textMuted)
                    Text(L10n.Dashboard.evidenceEmptyPointCloud)
                        .font(.caption2)
                        .foregroundColor(Design.Colors.Dark.textMuted)
                }
            } else {
                Canvas { context, size in
                    for point in points {
                        let rect = CGRect(
                            x: (Double(point.x) + 0.5) * size.width,
                            y: (0.5 - Double(point.y)) * size.height,
                            width: 1.7, height: 1.7)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(
                                Color(
                                    red: Double(point.r), green: Double(point.g), blue: Double(point.b), opacity: 0.92
                                )))
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !points.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(totalCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Design.Colors.Dark.bgDeep.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString(
            "dashboard.point_cloud_preview",
            value: "点云预览",
            comment: "Accessibility label for the dashboard point cloud preview"
        ))
        .accessibilityValue(
            isLoading
                ? L10n.PointCloud.loadingTitle
                : (totalCount > 0 ? totalCount.formatted() : L10n.Dashboard.evidenceEmptyPointCloud)
        )
        .task(id: record) {
            points = []
            totalCount = 0
            isLoading = true
            let url = record.fileURL
            let worker = Task.detached(priority: .utility) { WorkspacePreviewPoint.load(at: url) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            points = result.points
            totalCount = result.totalCount
            isLoading = false
        }
    }
}

private struct WorkspacePreviewPoint: Sendable {
    let x: Float
    let y: Float
    let r: Float
    let g: Float
    let b: Float

    struct LoadResult: Sendable {
        let points: [WorkspacePreviewPoint]
        let totalCount: Int
    }

    static func load(at url: URL) -> LoadResult {
        guard !Task.isCancelled,
            let data = PLYParserHelper.parsePointCloudData(at: url),
            let bounds = data.bounds
        else { return LoadResult(points: [], totalCount: 0) }
        let extent = max(bounds.size.x + bounds.size.z * 0.35, bounds.size.y * 1.1)
        guard extent.isFinite, extent > 0 else { return LoadResult(points: [], totalCount: 0) }
        let count = min(data.vertices.count, 2_048)
        guard count > 0 else { return LoadResult(points: [], totalCount: 0) }
        var result: [Self] = []
        result.reserveCapacity(count)
        for sample in 0..<count {
            guard !Task.isCancelled else { return LoadResult(points: [], totalCount: 0) }
            let index = sample * data.vertices.count / count
            let vertex = data.vertices[index]
            let color = data.colors[index]
            let depth = vertex.z - bounds.center.z
            result.append(
                Self(
                    x: (vertex.x - bounds.center.x + depth * 0.35) / extent,
                    y: (vertex.y - bounds.center.y + depth * 0.1) / extent,
                    r: color.r, g: color.g, b: color.b))
        }
        return LoadResult(points: result, totalCount: data.vertices.count)
    }
}
