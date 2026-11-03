// ScanArchiveDetailView.swift
// 归档详情：**只读**这一次归档。
//
// 它不是「本次扫描」的结果页：打开历史不改树体复核状态、不重算产量、不触发完成流程。
// 可以做的只有看，以及从这一条档案出发去看点云、分享、复扫。

import SwiftUI

struct ScanArchiveDetailView: View {
    let recordID: String
    /// 必须**观察**这份档案表，不能当成普通引用拿着。
    ///
    /// 详情是推进在档案列表上面的一页：档案被删掉或被替换之后，
    /// 生产刷新完成（`ScanHistoryStore` 发布新的 `scanFiles`）时，
    /// 这一页要自己醒过来重读一次 —— 读不到就说读不到，
    /// 不能继续挂着上一次读到的数。
    /// 只用 `let` 拿着的话，这一页根本不会被 store 的发布唤醒：
    /// 推进中的详情不会因为父页面重画而重新求值，
    /// `onChange` 也就永远等不到那次变化。
    @ObservedObject var historyStore: ScanHistoryStore
    var onRescan: ((String) -> Void)? = nil

    @StateObject private var controller: ScanArchiveDetailController
    @State private var presentedSheet: ScanArchiveDetailSheet?
    /// 分享点云失败时要告诉用户：面板一关就什么也没发生，用户会以为已经分享成功。
    @State private var showShareError = false

    init(
        recordID: String,
        historyStore: ScanHistoryStore,
        onRescan: ((String) -> Void)? = nil
    ) {
        self.recordID = recordID
        _historyStore = ObservedObject(wrappedValue: historyStore)
        self.onRescan = onRescan
        _controller = StateObject(wrappedValue: ScanArchiveDetailController(
            loader: ScanArchiveDetailLoader(repository: historyStore.archiveRepository)
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch controller.state {
                case .idle, .loading:
                    ScanArchiveDetailPlaceholder()
                case .failed(_, let reason):
                    ScanArchiveDetailUnavailable(message: reason, onRetry: loadDetail)
                case .loaded(let detail):
                    identity(detail)
                    reading(detail)
                    provenance(detail)
                    actions(detail)
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Design.Colors.Workspace.background)
        .tint(Design.Colors.Workspace.accent)
        .navigationTitle(L10n.History.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: recordID) { loadDetail() }
        .onChange(of: historyStore.scanFiles) { _ in
            // 档案被替换或删掉之后，详情要重新读一次：读不到就说读不到，
            // 不能继续挂着上一次读到的数。
            loadDetail()
        }
        .onDisappear { controller.cancel() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share(let url):
                // 分享点云必须接上完成回调：失败要说出来，不能让用户以为已经分享成功。
                ShareSheet(items: [url]) { result in handleShareCompletion(result) }
            case .pointCloud(let url):
                PointCloudSheet(initialFileURL: url, historyStore: historyStore)
            }
        }
        .alert(L10n.History.shareFailureTitle, isPresented: $showShareError) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.History.shareFailureMessage)
        }
    }

    /// 分享点云失败要说出来。
    ///
    /// 之前这里用 `ShareSheet(items:)` 不带完成回调，UIKit 报的失败被直接丢掉：
    /// 分享面板关掉后什么也没发生，用户以为点云已经分享/保存成功。
    /// 用户自己取消不算失败，不打扰。
    private func handleShareCompletion(_ result: ShareActivityResult) {
        guard ScanShareFailurePolicy.isFailure(result) else { return }
        Log.export.error("Archive point cloud sharing failed: \(result.errorDescription ?? "Unknown activity error")")
        showShareError = true
    }

    // MARK: - 读取

    /// 读取这一条。
    ///
    /// 档案页已经有同一批记录：直接用那一条，不必再扫一遍目录
    /// （扫目录等于把每份点云重新解析一遍）。记录不在列表里时，才按存档身份去找。
    private func loadDetail() {
        if let record = historyStore.scanFiles.first(where: { $0.id == recordID }) {
            controller.load(record: record)
        } else {
            controller.load(recordID: recordID)
        }
    }

    // MARK: - 身份

    private func identity(_ detail: ScanArchiveDetail) -> some View {
        InstrumentPanel(
            label: L10n.History.detailIdentityTitle,
            systemImage: "tree",
            tone: .neutral
        ) {
            VStack(alignment: .leading, spacing: 10) {
                detailLine(L10n.History.detailTreeLabel, detail.treeID)
                detailLine(
                    L10n.History.detailRecordLabel,
                    detail.recordID,
                    monospaced: true
                )
                detailLine(
                    L10n.History.detailDateLabel,
                    detail.scanDate.formatted(date: .abbreviated, time: .shortened)
                )
                if !detail.fruitType.isEmpty {
                    detailLine(L10n.History.detailFruitTypeLabel, detail.fruitType)
                }
            }
        }
    }

    // MARK: - 读数

    private func reading(_ detail: ScanArchiveDetail) -> some View {
        InstrumentPanel(
            label: L10n.History.detailReadingTitle,
            systemImage: "scalemass",
            tone: .neutral
        ) {
            VStack(alignment: .leading, spacing: 12) {
                switch detail.reading {
                case .available(let fruitCount, let yieldKg):
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.History.detailYieldLabel)
                                .font(.caption)
                                .foregroundColor(Design.Colors.Workspace.secondary)
                            Text(String(format: "%.1f", yieldKg))
                                .font(.system(size: 24, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(Design.Colors.Workspace.ink)
                            Text("kg")
                                .font(.caption)
                                .foregroundColor(Design.Colors.Workspace.secondary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.History.detailCountLabel)
                                .font(.caption)
                                .foregroundColor(Design.Colors.Workspace.secondary)
                            Text(L10n.Dashboard.fruitCountLabel(fruitCount))
                                .font(.system(.body, design: .default))
                                .monospacedDigit()
                                .foregroundColor(Design.Colors.Workspace.ink)
                        }
                    }
                case .unavailable(let reason):
                    // 读不到就说读不到：不用 0 冒充一次成功读取。
                    Text(reasonText(reason))
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("archiveDetail.readingUnavailable")
                }
                detailLine(
                    L10n.History.detailReliabilityLabel,
                    detail.reliability ?? L10n.History.detailReliabilityUnknown
                )
            }
        }
    }

    // MARK: - 来源与完整性

    private func provenance(_ detail: ScanArchiveDetail) -> some View {
        InstrumentPanel(
            label: L10n.History.detailSourceTitle,
            systemImage: "doc.badge.ellipsis",
            tone: detail.fileIntegrity == .complete ? .neutral : .attention
        ) {
            VStack(alignment: .leading, spacing: 8) {
                detailLine(
                    L10n.History.detailIntegrityLabel,
                    integrityText(detail.fileIntegrity)
                )
                detailLine(
                    L10n.History.detailFileSizeLabel,
                    ByteCountFormatter.string(fromByteCount: Int64(detail.fileSizeBytes), countStyle: .file)
                )
                detailLine(L10n.History.detailFileLabel, detail.fileURL.lastPathComponent, monospaced: true)
            }
        }
    }

    // MARK: - 动作

    private func actions(_ detail: ScanArchiveDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                presentedSheet = .pointCloud(detail.fileURL)
            } label: {
                Label(L10n.History.previewPointCloud, systemImage: "cube.transparent")
                    .frame(minHeight: Design.Touch.minimumHeight)
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle())
            .accessibilityIdentifier("archiveDetail.previewPointCloud")

            Button {
                presentedSheet = .share(detail.fileURL)
            } label: {
                Label(L10n.History.sharePointCloud, systemImage: "square.and.arrow.up")
                    .frame(minHeight: Design.Touch.minimumHeight)
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle())
            .accessibilityIdentifier("archiveDetail.sharePointCloud")

            if let onRescan {
                Button {
                    onRescan(detail.treeID)
                } label: {
                    Label(L10n.History.rescanTree, systemImage: "viewfinder")
                        .frame(minHeight: Design.Touch.minimumHeight)
                }
                .buttonStyle(WorkspaceSecondaryButtonStyle())
                .accessibilityIdentifier("archiveDetail.rescanTree")
                .accessibilityHint(
                    NSLocalizedString(
                        "history.row.rescan_accessibility_hint",
                        value: "Starts a new scan for this tree. This record's count and yield remain unavailable.",
                        comment: ""
                    )
                )
            }
        }
    }

    // MARK: - 辅助

    private func detailLine(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 读取失败的原因码 → 用户能看懂的说明（沿用档案行已有的文案口径）。
    private func reasonText(_ code: String) -> String {
        switch code {
        case "scanResultJSONFailed":
            return NSLocalizedString(
                "history.integrity.invalid.json",
                value: "结果文件无法读取。",
                comment: "Archive result JSON cannot be read"
            )
        case "scanResultCSVFailed":
            return NSLocalizedString(
                "history.integrity.invalid.csv",
                value: "结果表无法读取。",
                comment: "Archive result CSV cannot be read"
            )
        case "scanResultManifestMissing":
            return NSLocalizedString(
                "history.integrity.incomplete.missing_result",
                value: "这次扫描没有留下完成清单。",
                comment: "Archive completion manifest is missing"
            )
        default:
            return L10n.History.detailResultUnavailable
        }
    }

    private func integrityText(_ state: ScanPersistenceState) -> String {
        switch state {
        case .complete:
            return L10n.History.integrityComplete
        case .incomplete:
            return L10n.History.integrityIncomplete
        case .invalid:
            return L10n.History.integrityInvalid
        }
    }
}

private enum ScanArchiveDetailSheet: Identifiable {
    case share(URL)
    case pointCloud(URL)

    var id: String {
        switch self {
        case .share(let url): return "share-\(url.lastPathComponent)"
        case .pointCloud(let url): return "pointCloud-\(url.lastPathComponent)"
        }
    }
}

/// 读取中：只给一个安静的占位，不假装有读数。
private struct ScanArchiveDetailPlaceholder: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(L10n.History.detailLoading)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .accessibilityIdentifier("archiveDetail.loading")
    }
}

/// 读不到：说清读不到，并给重试。
///
/// 重试不是装饰：档案目录读不到是**临时**故障（文案也让用户「稍后再试」），
/// 失败态若只说明不给出路，用户唯一能做的就是退出详情再进一次 ——
/// 那条记录一旦从档案列表掉下去，就再也回不来。
///
/// 标识只挂在叶子节点上：带标识的容器会把子元素的标识一起覆盖掉，
/// 按钮自己的标识会消失（AX 树里读不到）。
private struct ScanArchiveDetailUnavailable: View {
    let message: String
    /// 重新读一次这条归档。
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.History.detailUnavailableTitle, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundColor(Design.Colors.Workspace.attention)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("archiveDetail.unavailable")
            Button(action: onRetry) {
                Label(L10n.History.detailRetry, systemImage: "arrow.clockwise")
                    .frame(minHeight: Design.Touch.minimumHeight)
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle())
            .accessibilityIdentifier("archiveDetail.retry")
            .accessibilityHint(L10n.History.detailRetryHint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
    }
}
