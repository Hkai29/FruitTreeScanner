// OrchardMapView.swift
// 果园地图：果园的空间索引。
//
// 数据边界（见 docs/implementation/UI_DESIGN_SYSTEM.md 第 1 节）：
// 地图上只画**有真实坐标**的完整扫描。没有坐标的记录不出现在地图上，
// 但它们仍然留在档案里，因此地图必须把这条回退路径显式说出来。

import SwiftUI
import MapKit

@available(iOS 17, *)
struct OrchardMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var historyStore: ScanHistoryStore
    @ObservedObject private var surveyCatalog = TreeSurveyCatalog.shared
    private let onStartScan: (() -> Void)?
    /// 「按树复扫」的能力。
    ///
    /// 地图里的档案要能带着**这一棵树**进入扫描：树号、地块、标签都要跟着走。
    /// 没有它的时候，行尾菜单的「复扫这棵」会退化成没有身份的新建扫描 ——
    /// 菜单写着复扫这棵树，用户拿到的却是另一个扫描。
    private let onRescanTree: ((String) -> Void)?
    private let bundle: Bundle
    @State private var selectedTreeID: String?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var filterYieldLevel: YieldLevel?
    @State private var isArchivePresented = false
    /// 档案弹层关掉之后才交出去的树号。
    @State private var pendingRescanTreeID: String?
    /// 档案每次「呈现 → 关闭」换一个新号。
    ///
    /// 迟到的旧动作带着旧号：档案重新打开之后，它不能再影响新的呈现。
    @State private var archiveGeneration = 0

    @MainActor
    init(
        onStartScan: (() -> Void)? = nil,
        onRescanTree: ((String) -> Void)? = nil,
        bundle: Bundle = .main,
        historyStore: ScanHistoryStore? = nil
    ) {
        self.onStartScan = onStartScan
        self.onRescanTree = onRescanTree
        self.bundle = bundle
        self.historyStore = historyStore ?? .shared
    }

    private var presentation: OrchardMapPresentation {
        OrchardMapPresentation(bundle: bundle)
    }

    var body: some View {
        GeometryReader { proxy in
            // 一次求值只聚合一次：树体与无定位记录数必须来自同一份快照。
            let data = OrchardMapData(records: historyStore.scanFiles, surveyPoints: surveyCatalog.points)

            ZStack {
                Design.Colors.Workspace.background
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    topBar

                    if data.trees.isEmpty {
                        OrchardMapEmptyState(
                            onStartScan: onStartScan,
                            onOpenArchive: { isArchivePresented = true },
                            bundle: bundle
                        )
                    } else {
                        content(
                            data: data,
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.light)
        .navigationBarHidden(true)
        .environment(\.orchardMapPresentation, presentation)
        .sheet(isPresented: $isArchivePresented, onDismiss: finishArchiveDismissal) {
            HistorySheetView(
                onStartScan: { startScanFromArchive() },
                // 没有「按树复扫」这个能力时就得是**没有**：不能拿一个恒真的包装去冒充。
                // 否则详情页会多出一个点不动的「重新扫描」，
                // 行尾菜单的「复扫这棵」也会丢掉「新建扫描」这个既有兜底。
                onRescanTree: onRescanTree.map { _ in
                    let presentationGeneration = archiveGeneration
                    return { treeID in
                        rescanFromArchive(treeID, generation: presentationGeneration)
                    }
                },
                historyStore: historyStore
            )
        }
        .onAppear(perform: loadAndFrameMap)
        .onChange(of: historyStore.scanFiles) { _ in
            clearUnavailableSelection()
            updateMapRegion()
        }
        .onChange(of: filterYieldLevel) { _ in
            clearUnavailableSelection()
        }
        .onChange(of: surveyCatalog.points) { _ in
            clearUnavailableSelection()
            updateMapRegion()
        }
    }

    // MARK: - 版面

    private func content(data: OrchardMapData, width: CGFloat, height: CGFloat) -> some View {
        let trees = data.trees
        let filtered = filteredTrees(in: trees)
        let selected = selectedTree(in: filtered)
        // Short height alone does not make room for a 320pt side panel.
        let sideBySide = width >= 700

        return Group {
            if sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    mapFrame(trees: filtered)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            readoutBlock(data: data)
                            bottomPanel(
                                selected: selected,
                                filtered: filtered,
                                located: trees
                            )
                        }
                    }
                    .frame(width: 320)
                }
            } else if dynamicTypeSize.isAccessibilitySize || height < 560 {
                // Keep readouts, fallback actions and details in one scroll area.
                // Otherwise large readouts can consume the entire detail viewport.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        readoutBlock(data: data)
                        mapFrame(trees: filtered)
                            .frame(height: max(180, min(280, height * 0.35)))
                        bottomPanel(selected: selected, filtered: filtered, located: trees)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    readoutBlock(data: data)
                    mapFrame(trees: filtered)
                        .frame(maxHeight: .infinity)
                    bottomPanel(selected: selected, filtered: filtered, located: trees)
                }
            }
        }
    }

    private var topBar: some View {
        OrchardMapTopBar(title: L10n.Dashboard.mapTitle) {
            dismiss()
        }
    }

    /// 读数与回退路径：始终可见，不随筛选变化。
    private func readoutBlock(data: OrchardMapData) -> some View {
        VStack(spacing: 12) {
            OrchardMapCountReadout(
                locatedTreeCount: data.trees.count,
                unlocatedRecordCount: data.unlocatedRecordCount
            )

            if data.unlocatedRecordCount > 0 {
                OrchardMapFallbackNotice(
                    unlocatedRecordCount: data.unlocatedRecordCount,
                    onOpenArchive: { isArchivePresented = true }
                )
            }
        }
    }

    private func bottomPanel(
        selected: TreeAnnotation?,
        filtered: [TreeAnnotation],
        located: [TreeAnnotation]
    ) -> some View {
        OrchardMapBottomPanel(
            selectedTree: selected,
            filteredTrees: filtered,
            locatedTrees: located,
            filterYieldLevel: $filterYieldLevel,
            onClearSelection: { selectedTreeID = nil }
        )
    }

    // MARK: - 地图

    private func mapFrame(trees: [TreeAnnotation]) -> some View {
        mapSurface(trees: trees)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
            .accessibilityIdentifier("orchard.map")
    }

    private func mapSurface(trees: [TreeAnnotation]) -> some View {
        Map(position: $mapCameraPosition, selection: selectionBinding(in: trees)) {
            if let selected = selectedTree(in: trees), let point = selected.surveyPoint {
                MapCircle(center: point.coordinate, radius: point.horizontalAccuracyMeters)
                    .foregroundStyle(Design.Colors.Workspace.accent.opacity(0.12))
                    .stroke(Design.Colors.Workspace.accent, lineWidth: 1)
            }
            ForEach(trees) { tree in
                Annotation(tree.treeID, coordinate: tree.coordinate, anchor: .center) {
                    TreeMapPin(tree: tree, isSelected: selectedTreeID == tree.id)
                }
                .tag(tree)
            }
        }
        // 与果园空间同一张地图：压平高程、去掉兴趣点，只留位置关系。
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    // MARK: - 辅助

    private func filteredTrees(in trees: [TreeAnnotation]) -> [TreeAnnotation] {
        guard let filterYieldLevel else { return trees }
        return trees.filter { $0.yieldLevel == filterYieldLevel }
    }

    private func selectedTree(in trees: [TreeAnnotation]) -> TreeAnnotation? {
        guard let selectedTreeID else { return nil }
        return trees.first { $0.id == selectedTreeID }
    }

    /// MapKit 的选择控件（`selectAnnotation`）通过这个绑定回到界面状态。
    private func selectionBinding(in trees: [TreeAnnotation]) -> Binding<TreeAnnotation?> {
        Binding(
            get: { selectedTree(in: trees) },
            set: { selection in
                selectedTreeID = selection.flatMap { selected in
                    trees.first { $0.id == selected.id }?.id
                }
            }
        )
    }

    /// 从档案里发起扫描：先收起档案，再让地图退出，
    /// 由 Dashboard 接手"开始扫描"的交接。
    private func startScanFromArchive() {
        isArchivePresented = false
        DispatchQueue.main.async {
            onStartScan?()
        }
    }

    /// 档案里的「复扫这棵」：先把档案弹层关掉，关完再把**这棵树**交给上层。
    ///
    /// 顺序很重要：扫描是全屏界面，档案弹层还开着就启动会撞上两次转场。
    /// 这里不用固定延时 —— 弹层**真的**关掉了（`onDismiss`）才把树交出去。
    ///
    /// 迟到的或重复的动作直接丢掉：
    /// - 弹层不在 = 它已经在关闭途中，那一次交接由 `onDismiss` 负责；
    /// - 号对不上 = 它属于上一次已经关掉的呈现，档案重新打开后也不该再影响它。
    /// 两次都放行就会出现两次扫描。
    private func rescanFromArchive(_ treeID: String, generation: Int) {
        guard isArchivePresented, generation == archiveGeneration else { return }
        pendingRescanTreeID = treeID
        isArchivePresented = false
    }

    /// 档案弹层**已经关掉**：这时才可以启动扫描。
    private func finishArchiveDismissal() {
        archiveGeneration &+= 1
        guard let treeID = pendingRescanTreeID else { return }
        pendingRescanTreeID = nil
        onRescanTree?(treeID)
    }

    private func loadAndFrameMap() {
        historyStore.loadRecords()
        updateMapRegion()
    }

    private func clearUnavailableSelection() {
        let trees = OrchardMapData(records: historyStore.scanFiles, surveyPoints: surveyCatalog.points).trees
        if selectedTreeID != nil && selectedTree(in: filteredTrees(in: trees)) == nil {
            selectedTreeID = nil
        }
    }

    private func updateMapRegion() {
        let trees = OrchardMapData(records: historyStore.scanFiles, surveyPoints: surveyCatalog.points).trees
        guard let region = OrchardMapRegionCalculator.region(for: trees) else { return }
        mapCameraPosition = .region(region)
    }
}
