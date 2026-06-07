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

                        // 参数调整卡片
                        paramsCard

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

    // MARK: - 参数调整卡片

    private var paramsCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text("算法参数")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            // 最小聚类点数 → clusterMinPoints
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最小聚类点数")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Spacer()
                    Text("\(Int(minClusterPoints))")
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.Dark.glow)
                }
                Slider(
                    value: $minClusterPoints,
                    in: 3...150,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            commitMinClusterPointsDraft()
                        }
                    }
                )
                .tint(Design.Colors.Dark.glow)
            }

            // 最大聚类直径 → clusterMaxDiameter
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最大聚类直径 (m)")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Spacer()
                    Text(String(format: "%.3f m", maxDiameter))
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.Dark.glow)
                }
                Slider(
                    value: $maxDiameter,
                    in: 0.04...0.20,
                    step: 0.005,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            commitMaxDiameterDraft()
                        }
                    }
                )
                .tint(Design.Colors.Dark.glow)
            }

            // 最小球形度 → sphericityThreshold
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最小球形度")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Spacer()
                    Text(String(format: "%.2f", sphericity))
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.Dark.glow)
                }
                Slider(
                    value: $sphericity,
                    in: 0.2...0.8,
                    step: 0.02,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            commitSphericityDraft()
                        }
                    }
                )
                .tint(Design.Colors.Dark.glow)
            }

            // HSV 色调范围（只读显示）
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("HSV 色调范围")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                HStack {
                    Text("H: \(Int(SettingsStore.shared.hsvHMin))° - \(Int(SettingsStore.shared.hsvHMax))°")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Spacer()
                    Text("S≥\(String(format: "%.0f%%", SettingsStore.shared.hsvSMin * 100)) V≥\(String(format: "%.0f%%", SettingsStore.shared.hsvVMin * 100))")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
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
        let url = Self.recordsURL()
        recordsTask = Task.detached(priority: .utility) {
            do {
                let data = try Data(contentsOf: url)
                let records = try JSONDecoder().decode([CalibrationRecord].self, from: data)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.calibrationRecords = records
                }
            } catch CocoaError.fileReadNoSuchFile {
                await MainActor.run {
                    self.calibrationRecords = []
                }
            } catch {
            }
        }
    }

    private func saveRecords() {
        let records = calibrationRecords
        let url = Self.recordsURL()
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(records)
                try data.write(to: url, options: .atomic)
            } catch {
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

    private static func recordsURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("calibration_records.json")
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
