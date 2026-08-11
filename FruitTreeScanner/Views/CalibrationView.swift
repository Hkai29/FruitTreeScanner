// CalibrationView.swift
// 算法校准界面 - 用于验证和调整产量估算算法
//
// 用户流程：
// 1. 扫描果树，获取算法估算的果实数量和产量
// 2. 人工计数（手工数出可见果实数量）
// 3. 采摘后录入实际重量
// 4. 系统计算误差，帮用户判断算法是否需要调整

import SwiftUI
import UIKit

// MARK: - 校准视图

struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordsController: CalibrationRecordsController
    @State private var showAddRecord = false
    @State private var recordPendingDeletion: CalibrationRecord?
    @State private var maxDiameter: Double = SettingsStore.shared.clusterMaxDiameter
    @State private var minClusterPoints: Double = Double(SettingsStore.shared.clusterMinPoints)
    @State private var sphericity: Double = SettingsStore.shared.sphericityThreshold

    private var activeFruitCategory: FruitCategory {
        FruitCategory(rawValue: SettingsStore.shared.fruitType) ?? .apple
    }

    @MainActor
    init() {
        _recordsController = StateObject(wrappedValue: CalibrationRecordsController())
    }

    @MainActor
    init(recordsController: CalibrationRecordsController) {
        _recordsController = StateObject(wrappedValue: recordsController)
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
                            title: L10n.Calibration.headerTitle,
                            subtitle: L10n.Calibration.headerSubtitle,
                            icon: "slider.horizontal.3",
                            accent: Design.Colors.Dark.info
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.Calibration.headerTitle)
                        .accessibilityValue(L10n.Calibration.headerSubtitle)
                        .accessibilityAddTraits(.isHeader)

                        CalibrationParametersCard(
                            maxDiameter: $maxDiameter,
                            minClusterPoints: $minClusterPoints,
                            sphericity: $sphericity,
                            onCommitMinClusterPoints: commitMinClusterPointsDraft,
                            onCommitMaxDiameter: commitMaxDiameterDraft,
                            onCommitSphericity: commitSphericityDraft
                        )

                        if recordsController.state.showsDerivedStatistics {
                            statisticsCard
                        }

                        // 校准记录列表
                        recordsSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle(L10n.Calibration.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Calibration.close) {
                        dismiss()
                    }
                    .disabled(recordsController.state.isSaving)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddRecord = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Design.Colors.Dark.glow)
                    }
                    .disabled(!recordsController.state.canModify)
                    .accessibilityLabel(L10n.Calibration.addRecordAccessibility)
                }
            }
        }
        .interactiveDismissDisabled(recordsController.state.isSaving)
        .sheet(isPresented: $showAddRecord) {
            AddCalibrationRecordView { record in
                recordsController.add(record)
            }
        }
        .alert(L10n.Calibration.deleteConfirmationTitle, isPresented: deleteAlertBinding) {
            Button(L10n.Common.cancel, role: .cancel) {
                recordPendingDeletion = nil
            }
            Button(L10n.Common.delete, role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            Text(L10n.Calibration.deleteConfirmationMessage)
        }
        .onAppear {
            recordsController.load()
            let params = FruitParametersStore.shared.param(for: activeFruitCategory)
            maxDiameter = Double(params.diamMax)
            minClusterPoints = Double(SettingsStore.shared.clusterMinPoints)
            sphericity = Double(params.sphericityThreshold)
        }
        .onDisappear {
            commitParameterDrafts()
            recordsController.cancelLoading()
        }
        .onChange(of: recordsController.state) { state in
            guard let announcement = state.accessibilityAnnouncement else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    // MARK: - 误差统计卡片

    private var statisticsCard: some View {
        CalibrationStatisticsCard(records: recordsController.records)
    }

    // MARK: - 校准记录列表

    private var recordsSection: some View {
        CalibrationRecordsSection(
            records: recordsController.records,
            state: recordsController.state,
            onAdd: { showAddRecord = true },
            onRetry: recordsController.load,
            onDismissSaveFailure: recordsController.dismissSaveFailure,
            onDelete: { record in
                recordPendingDeletion = record
            }
        )
    }

    // MARK: - Helpers

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
        recordsController.delete(record)
        recordPendingDeletion = nil
    }
}
