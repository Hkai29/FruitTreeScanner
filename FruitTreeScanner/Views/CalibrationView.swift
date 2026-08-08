// CalibrationView.swift
// 算法校准界面 - 用于验证和调整产量估算算法
//
// 用户流程：
// 1. 扫描果树，获取算法估算的果实数量和产量
// 2. 人工计数（手工数出可见果实数量）
// 3. 采摘后录入实际重量
// 4. 系统计算误差，帮用户判断算法是否需要调整

import SwiftUI

// MARK: - 校准视图

struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordStore = CalibrationRecordStore()
    @State private var showAddRecord = false
    @State private var recordPendingDeletion: CalibrationRecord?
    @State private var maxDiameter: Double = SettingsStore.shared.clusterMaxDiameter
    @State private var minClusterPoints: Double = Double(SettingsStore.shared.clusterMinPoints)
    @State private var sphericity: Double = SettingsStore.shared.sphericityThreshold

    private var activeFruitCategory: FruitCategory {
        FruitCategory(rawValue: SettingsStore.shared.fruitType) ?? .apple
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        DashboardToolHeader(
                            imageName: "FeatureCalibration",
                            title: "算法校准",
                            subtitle: "用实测果径、聚类阈值和误差记录调准产量估算。",
                            icon: "slider.horizontal.3",
                            accent: Design.Colors.Dark.info
                        )

                        CalibrationParametersCard(
                            maxDiameter: $maxDiameter,
                            minClusterPoints: $minClusterPoints,
                            sphericity: $sphericity,
                            onCommitMinClusterPoints: commitMinClusterPointsDraft,
                            onCommitMaxDiameter: commitMaxDiameterDraft,
                            onCommitSphericity: commitSphericityDraft
                        )

                        // 误差统计
                        if loadPresentation.showsStatistics {
                            statisticsCard
                        }

                        // 校准记录列表
                        recordsSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("算法校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddRecord = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Design.Colors.Dark.glow)
                    }
                    .disabled(!loadPresentation.allowsMutation)
                    .accessibilityLabel("添加校准记录")
                    .accessibilityHint(
                        loadPresentation.allowsMutation
                            ? ""
                            : CalibrationRecordLoadText.mutationDisabledHint
                    )
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddCalibrationRecordView { record in
                guard let records = recordStore.prepend(record) else { return }
                saveRecords(records)
            }
        }
        .alert("删除校准记录", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) {
                recordPendingDeletion = nil
            }
            Button("删除", role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            Text("这条校准记录会从本机移除，扫描原始记录不会被删除。")
        }
        .onAppear {
            recordStore.loadRecords()
            let params = FruitParametersStore.shared.param(for: activeFruitCategory)
            maxDiameter = Double(params.diamMax)
            minClusterPoints = Double(SettingsStore.shared.clusterMinPoints)
            sphericity = Double(params.sphericityThreshold)
        }
        .onDisappear {
            commitParameterDrafts()
            recordStore.invalidateLoad()
        }
    }

    // MARK: - 误差统计卡片

    private var statisticsCard: some View {
        CalibrationStatisticsCard(records: recordStore.records)
    }

    // MARK: - 校准记录列表

    @ViewBuilder
    private var recordsSection: some View {
        switch loadPresentation.primaryContent {
        case .loading:
            CalibrationRecordsLoadingView()
        case .loadFailure:
            CalibrationRecordsLoadFailureView(
                message: CalibrationRecordLoadText.failureMessage(
                    retainedRecordCount: loadPresentation.retainedRecordCount
                ),
                isRetrying: recordStore.isLoading,
                onRetry: retryLoadingRecords
            )
        case .records:
            CalibrationRecordsSection(
                records: recordStore.records,
                onAdd: { showAddRecord = true },
                onDelete: { record in
                    recordPendingDeletion = record
                }
            )
        }
    }

    // MARK: - Helpers

    private var loadPresentation: CalibrationRecordLoadPresentation {
        CalibrationRecordLoadPresentation(
            records: recordStore.records,
            isLoading: recordStore.isLoading,
            hasLoaded: recordStore.hasLoaded,
            loadFailure: recordStore.loadFailure
        )
    }

    private func retryLoadingRecords() {
        guard !recordStore.isLoading else { return }
        recordStore.loadRecords()
    }

    private func saveRecords(_ records: [CalibrationRecord]) {
        let generation = CalibrationSaveRevisionSource.shared.nextRevision()
        Task(priority: .utility) {
            let saved = await CalibrationRecordPersistenceController.shared.save(
                records,
                generation: generation
            )
            if !saved,
               let error = await CalibrationRecordPersistenceController.shared.lastErrorDescription {
                Log.general.error("Calibration save failed: \(error)")
            }
        }
    }

    private func commitParameterDrafts() {
        commitMinClusterPointsDraft()
        commitMaxDiameterDraft()
        commitSphericityDraft()
    }

    private func commitMinClusterPointsDraft() {
        let rounded = Int(minClusterPoints.rounded())
        guard SettingsStore.shared.clusterMinPoints != rounded else { return }
        SettingsStore.shared.clusterMinPoints = rounded
        minClusterPoints = Double(SettingsStore.shared.clusterMinPoints)
    }

    private func commitMaxDiameterDraft() {
        let rounded = (maxDiameter / 0.005).rounded() * 0.005
        let category = activeFruitCategory
        let current = FruitParametersStore.shared.param(for: category)
        let needsStoreUpdate = abs(Double(current.diamMax) - rounded) > 0.000_1
        let needsSettingsUpdate = abs(SettingsStore.shared.clusterMaxDiameter - rounded) > 0.000_1
        guard needsStoreUpdate || needsSettingsUpdate else {
            maxDiameter = Double(current.diamMax)
            return
        }

        if needsStoreUpdate {
            FruitParametersStore.shared.updateParam(for: category) { params in
                params.diamMax = Float(rounded)
                if params.diamMin > params.diamMax {
                    params.diamMin = params.diamMax
                }
            }
        }
        if needsSettingsUpdate {
            SettingsStore.shared.clusterMaxDiameter = rounded
        }
        maxDiameter = rounded
    }

    private func commitSphericityDraft() {
        let rounded = (sphericity / 0.02).rounded() * 0.02
        let category = activeFruitCategory
        let current = FruitParametersStore.shared.param(for: category)
        let needsStoreUpdate = abs(Double(current.sphericityThreshold) - rounded) > 0.000_1
        let needsSettingsUpdate = abs(SettingsStore.shared.sphericityThreshold - rounded) > 0.000_1
        guard needsStoreUpdate || needsSettingsUpdate else {
            sphericity = Double(current.sphericityThreshold)
            return
        }

        if needsStoreUpdate {
            FruitParametersStore.shared.updateParam(for: category) { params in
                params.sphericityThreshold = Float(rounded)
            }
        }
        if needsSettingsUpdate {
            SettingsStore.shared.sphericityThreshold = rounded
        }
        sphericity = rounded
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { recordPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    recordPendingDeletion = nil
                }
            }
        )
    }

    private func deletePendingRecord() {
        guard let record = recordPendingDeletion else { return }
        recordPendingDeletion = nil
        guard let records = recordStore.remove(id: record.id) else { return }
        saveRecords(records)
    }
}

struct CalibrationRecordLoadPresentation: Equatable {
    enum PrimaryContent: Equatable {
        case loading
        case loadFailure
        case records
    }

    let primaryContent: PrimaryContent
    let allowsMutation: Bool
    let retainedRecordCount: Int
    let showsStatistics: Bool

    init(
        records: [CalibrationRecord],
        isLoading: Bool,
        hasLoaded: Bool,
        loadFailure: CalibrationRecordLoadFailure?
    ) {
        if loadFailure != nil {
            primaryContent = .loadFailure
        } else if !hasLoaded || isLoading {
            primaryContent = .loading
        } else {
            primaryContent = .records
        }
        allowsMutation = hasLoaded && !isLoading && loadFailure == nil
        retainedRecordCount = records.count
        showsStatistics = primaryContent == .records
    }
}

private struct CalibrationRecordsLoadingView: View {
    var body: some View {
        VStack(spacing: Design.Space.sm) {
            ProgressView()
                .tint(Design.Colors.Dark.info)
            Text(CalibrationRecordLoadText.loading)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private struct CalibrationRecordsLoadFailureView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            Label(CalibrationRecordLoadText.failureTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.error)

            Text(message)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                HStack(spacing: Design.Space.sm) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(
                        isRetrying
                            ? CalibrationRecordLoadText.retrying
                            : CalibrationRecordLoadText.retry
                    )
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Design.Colors.Dark.error)
            .disabled(isRetrying)
            .accessibilityHint(CalibrationRecordLoadText.retryHint)
        }
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private enum CalibrationRecordLoadText {
    static let loading = localized(
        "calibration.load.loading",
        fallback: "正在读取校准记录…"
    )
    static let failureTitle = localized(
        "calibration.load.failure.title",
        fallback: "校准记录未加载"
    )
    static let retry = localized("calibration.load.retry", fallback: "重试")
    static let retrying = localized("calibration.load.retrying", fallback: "正在重试…")
    static let retryHint = localized(
        "calibration.load.retry_hint",
        fallback: "重新读取本机校准记录。"
    )
    static let mutationDisabledHint = localized(
        "calibration.load.mutation_disabled_hint",
        fallback: "请等待校准记录成功加载后再添加。"
    )

    static func failureMessage(retainedRecordCount: Int) -> String {
        if retainedRecordCount > 0 {
            let format = localized(
                "calibration.load.failure.stale_message_format",
                fallback: "无法刷新校准文件，已保留上次成功加载的 %d 条记录。请重试后再编辑。"
            )
            return String.localizedStringWithFormat(format, retainedRecordCount)
        }
        return localized(
            "calibration.load.failure.empty_message",
            fallback: "无法读取本机校准文件。现有数据没有被修改，请重试后再添加或删除记录。"
        )
    }

    private static func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }
}
