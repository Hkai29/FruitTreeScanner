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
    @State private var calibrationRecords: [CalibrationRecord] = []
    @State private var showAddRecord = false
    @State private var recordPendingDeletion: CalibrationRecord?
    @State private var recordsTask: Task<Void, Never>?
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
                        statisticsCard

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
                    .accessibilityLabel("添加校准记录")
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddCalibrationRecordView { record in
                calibrationRecords.insert(record, at: 0)
                saveRecords()
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
            loadRecords()
            let params = FruitParametersStore.shared.param(for: activeFruitCategory)
            maxDiameter = Double(params.diamMax)
            minClusterPoints = Double(SettingsStore.shared.clusterMinPoints)
            sphericity = Double(params.sphericityThreshold)
        }
        .onDisappear {
            commitParameterDrafts()
            recordsTask?.cancel()
            recordsTask = nil
        }
    }

    // MARK: - 误差统计卡片

    private var statisticsCard: some View {
        CalibrationStatisticsCard(records: calibrationRecords)
    }

    // MARK: - 校准记录列表

    private var recordsSection: some View {
        CalibrationRecordsSection(
            records: calibrationRecords,
            onAdd: { showAddRecord = true },
            onDelete: { record in
                recordPendingDeletion = record
            }
        )
    }

    // MARK: - Helpers

    private func loadRecords() {
        recordsTask?.cancel()
        recordsTask = Task.detached(priority: .utility) {
            do {
                let records = try CalibrationRecordPersistence.load()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.calibrationRecords = records
                }
            } catch {
            }
        }
    }

    private func saveRecords() {
        let records = calibrationRecords
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
        calibrationRecords.removeAll { $0.id == record.id }
        recordPendingDeletion = nil
        saveRecords()
    }
}
