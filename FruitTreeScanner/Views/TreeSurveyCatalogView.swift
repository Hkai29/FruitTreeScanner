import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct TreeSurveyCatalogView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var catalog: TreeSurveyCatalog
    var onScanTree: ((String) -> Void)?
    @State private var selectedID: String?
    @State private var isImporting = false
    @State private var isReading = false
    @State private var isExporting = false
    @State private var exportDocument: TreeSurveyDocument?
    @State private var pending: TreeSurveyImport?
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var recoverySnapshot: TreeSurveyCatalog.RecoverySnapshot?
    @State private var recoveryBackupURL: URL?

    private var selected: TreeSurveyPoint? { catalog.point(treeID: selectedID ?? "") }
    private var filtered: [TreeSurveyPoint] {
        search.isEmpty ? catalog.points : catalog.points.filter { $0.treeID.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("单树定位").font(Design.Typography.title2)
                Text("以树干基部为测量点，同一树号沿用同一位置。")
                    .font(.subheadline).foregroundStyle(Design.Colors.Workspace.secondary)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { importExportActions }
                } else {
                    HStack(spacing: 12) { importExportActions }
                }
                if let message = catalog.loadError {
                    Text(message).font(.subheadline).foregroundStyle(Design.Colors.Workspace.failure)
                        .accessibilityIdentifier("treeSurvey.error")
                    Button("从文件恢复树位档案") { beginRecovery() }
                        .buttonStyle(WorkspacePrimaryButtonStyle()).disabled(isReading)
                        .accessibilityIdentifier("treeSurvey.recover")
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Design.Colors.Workspace.failure)
                        .accessibilityIdentifier("treeSurvey.operationError")
                }
                if let recoveryBackupURL {
                    Text("恢复已保存，损坏原档的副本已保留。可将副本保存到文件，供后续检查。")
                        .font(.subheadline)
                    ShareLink("保存原档副本", item: recoveryBackupURL)
                        .accessibilityIdentifier("treeSurvey.shareRecoveryBackup")
                }
                if catalog.points.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("尚无树干测量点").font(.headline)
                        Text("导入 RTK 或全站仪测量结果后，可按树号查看位置与误差范围。普通手机定位只作参考，不会自动识别相邻果树。")
                            .font(.subheadline).foregroundStyle(Design.Colors.Workspace.secondary)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Design.Colors.Workspace.surface)
                } else {
                    Text("\(catalog.points.count) 棵树 · \(catalog.points.filter(\.meetsReportedTarget).count) 棵报告误差 ≤1 m")
                        .font(.subheadline).monospacedDigit()
                    TreeSurveyMap(points: catalog.points, selectedID: $selectedID)
                        .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium))
                        .accessibilityIdentifier("treeSurvey.map")
                    if let selected { detail(selected) }
                    TextField("查找树号", text: $search).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("treeSurvey.search")
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { point in
                            Button {
                                selectedID = point.treeID
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(point.treeID).font(.body.weight(.medium))
                                        Text(point.method.title).font(.caption).foregroundStyle(Design.Colors.Workspace.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.3f m", point.horizontalAccuracyMeters)).monospacedDigit()
                                        .font(.subheadline)
                                }.padding(.vertical, 14).frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("treeSurvey.point.\(point.treeID)")
                            Divider()
                        }
                        if filtered.isEmpty { Text("未找到此树号").font(.subheadline).padding(.vertical, 16) }
                    }
                }
                DisclosureGroup("导入格式与精度说明") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WGS84 GeoJSON FeatureCollection，每棵树一个 Point，坐标顺序为经度、纬度。文件 ≤2 MB，总数 ≤5000 棵。")
                        Text("properties 必填：tree_id、position_source、horizontal_accuracy_m（米）、measured_at（ISO 8601）、reference: trunk_base、source_note。")
                        Text("position_source 支持 rtk_fixed、total_station、rtk_float、device_gps。误差数字来自测量文件；RTK 固定解或全站仪报告半径 ≤1 m 只表示达到输入门槛，实际精度仍需现场核验。")
                        Text("地图底图用于浏览；树位精度取决于测量结果与坐标系。复扫前仍需核对现场树号。")
                    }.font(.caption).foregroundStyle(Design.Colors.Workspace.secondary).padding(.top, 10)
                }.font(.subheadline)
            }.padding(20)
        }
        .background(Design.Colors.Workspace.background)
        .tint(Design.Colors.Workspace.accent)
        .navigationTitle("树位档案").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, UTType(filenameExtension: "geojson") ?? .json]) { result in
            switch result {
            case .failure(let error): errorMessage = error.localizedDescription
            case .success(let url): read(url)
            }
        }
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: .json, defaultFilename: "tree-positions.geojson") { result in
            exportDocument = nil
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .sheet(item: $pending) { batch in
            TreeSurveyImportPreview(batch: batch, catalog: catalog) { points, replace in
                do {
                    if let snapshot = batch.recovery {
                        recoveryBackupURL = try catalog.recover(points, from: snapshot, confirmed: replace)
                    } else {
                        try catalog.commit(points, replacingExisting: replace)
                    }
                    selectedID = points.first?.treeID
                    errorMessage = nil
                    pending = nil
                } catch { errorMessage = error.localizedDescription; pending = nil }
            }
        }
    }

    @ViewBuilder
    private var importExportActions: some View {
        Button("导入树位") { recoverySnapshot = nil; isImporting = true }
            .buttonStyle(WorkspacePrimaryButtonStyle()).disabled(isReading || catalog.loadError != nil)
            .accessibilityIdentifier("treeSurvey.import")
        Button("导出树位") { prepareExport() }
            .buttonStyle(WorkspaceSecondaryButtonStyle()).disabled(catalog.points.isEmpty)
        if isReading { ProgressView().accessibilityLabel("正在读取树位") }
    }

    private func beginRecovery() {
        do {
            recoverySnapshot = try catalog.prepareRecovery()
            errorMessage = nil
            isImporting = true
        } catch { errorMessage = error.localizedDescription }
    }

    /// 导出前先把内容编码好。
    /// 编码失败时不给导出器任何文档：以前这里传的是空 Data，
    /// 导出器会「成功」写出一个 0 字节的 geojson，用户以为导出完成了。
    private func prepareExport() {
        switch TreeSurveyExportPreparation.payload(for: catalog.points) {
        case .success(let data):
            exportDocument = TreeSurveyDocument(data: data)
            errorMessage = nil
            isExporting = true
        case .failure(let error):
            exportDocument = nil
            errorMessage = "树位导出没有生成文件：\(error.localizedDescription)"
        }
    }

    private func detail(_ point: TreeSurveyPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(point.treeID).font(.title3.weight(.medium))
            Text(point.method.title + " · " + point.accuracyDescription).font(.subheadline).monospacedDigit()
            Text(point.meetsReportedTarget ? "报告精度达到 1 m 目标 · 现场待核验" : "未达到高精度输入门槛 · 需复测")
                .font(.caption).foregroundStyle(Design.Colors.Workspace.secondary)
            Text(String(format: "经度 %.8f° · 纬度 %.8f°", point.longitude, point.latitude))
                .font(.caption).monospacedDigit()
            Text("测量时间 \(point.measuredAt)\n来源 \(point.sourceNote)")
                .font(.caption).foregroundStyle(Design.Colors.Workspace.secondary)
            if let onScanTree {
                Button("扫描这棵树") { onScanTree(point.treeID) }
                    .buttonStyle(WorkspacePrimaryButtonStyle()).frame(minHeight: 44)
                    .accessibilityIdentifier("treeSurvey.scan")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Design.Colors.Workspace.surface)
    }

    private func read(_ url: URL) {
        let snapshot = recoverySnapshot
        isReading = true
        errorMessage = nil
        Task {
            do {
                let points = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try TreeSurveyCodec.decode(TreeSurveyCodec.readFile(url))
                }.value
                pending = TreeSurveyImport(points: points, recovery: snapshot)
            } catch { errorMessage = error.localizedDescription }
            isReading = false
        }
    }
}

struct TreeSurveyImport: Identifiable {
    let id = UUID()
    let points: [TreeSurveyPoint]
    var recovery: TreeSurveyCatalog.RecoverySnapshot? = nil
}

struct TreeSurveyImportPreview: View {
    @Environment(\.dismiss) private var dismiss
    let batch: TreeSurveyImport
    @ObservedObject var catalog: TreeSurveyCatalog
    let commit: ([TreeSurveyPoint], Bool) -> Void
    @State private var replaceExisting = false
    private var conflicts: Int { catalog.conflictCount(for: batch.points) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if batch.recovery != nil {
                        Text("恢复将用本批测量点替换无法读取的树位档案。保存前会核对并保留损坏原档的副本；取消不会修改文件。")
                        Toggle("确认保留原档副本并恢复", isOn: $replaceExisting)
                            .accessibilityIdentifier("treeSurvey.confirmRecovery")
                    }
                    Text("\(batch.points.count) 个树干测量点，\(conflicts) 个已有树号。")
                    Text("精度为文件报告值，尚未现场核验。导入不会更改扫描原始数据与估产结果。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if batch.recovery == nil && conflicts > 0 {
                        Toggle("确认更新 \(conflicts) 棵树的测量点", isOn: $replaceExisting)
                    }
                }
                Section("导入预览") {
                    ForEach(batch.points) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.treeID).font(.headline)
                            Text(p.method.title + " · " + p.accuracyDescription).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("确认树位").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit(batch.points, replaceExisting) }
                        .disabled((batch.recovery != nil || conflicts > 0) && !replaceExisting)
                        .accessibilityIdentifier("treeSurvey.saveImport")
                }
            }
        }
    }
}

/// 树位导出的准备步骤：编码成功才给内容，编码失败把原因交回界面。
/// 单独抽出来是为了能直接测「失败时不会产出空文件」。
enum TreeSurveyExportPreparation {
    static func payload(for points: [TreeSurveyPoint]) -> Result<Data, Error> {
        do {
            return .success(try TreeSurveyCodec.encode(points))
        } catch {
            return .failure(error)
        }
    }
}

private struct TreeSurveyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct TreeSurveyMap: UIViewRepresentable {
    let points: [TreeSurveyPoint]
    @Binding var selectedID: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let changed = coordinator.points != points
        if changed {
            coordinator.points = points
            map.removeAnnotations(map.annotations)
            map.addAnnotations(points.map { p in
                let a = MKPointAnnotation(); a.title = p.treeID; a.coordinate = p.coordinate; return a
            })
        }
        if changed || coordinator.selectedID != selectedID {
            coordinator.selectedID = selectedID
            map.removeOverlays(map.overlays)
            if let p = points.first(where: { $0.treeID == selectedID }) {
                map.addOverlay(MKCircle(center: p.coordinate, radius: p.horizontalAccuracyMeters))
                map.setRegion(MKCoordinateRegion(center: p.coordinate,
                    latitudinalMeters: max(25, p.horizontalAccuracyMeters * 5),
                    longitudinalMeters: max(25, p.horizontalAccuracyMeters * 5)), animated: false)
            } else { map.showAnnotations(map.annotations, animated: false) }
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TreeSurveyMap
        var points: [TreeSurveyPoint] = []
        var selectedID: String?
        init(_ parent: TreeSurveyMap) { self.parent = parent }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let id = view.annotation?.title ?? nil else { return }
            parent.selectedID = id
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "tree-survey") as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "tree-survey")
            view.annotation = annotation
            view.markerTintColor = UIColor(Design.Colors.Workspace.accent)
            view.glyphImage = UIImage(systemName: "tree")
            return view
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKCircleRenderer(overlay: overlay)
            renderer.strokeColor = UIColor.systemBlue
            renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12)
            renderer.lineWidth = 1
            return renderer
        }
    }
}
