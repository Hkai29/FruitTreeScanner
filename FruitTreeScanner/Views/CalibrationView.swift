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
    @ObservedObject private var settings: SettingsStore
    private let parametersStore: FruitParametersStore
    let scanSource: CalibrationScanSource
    @State private var showAddRecord = false
    @State private var recordPendingDeletion: CalibrationRecord?
    @State private var maxDiameter: CalibrationParameterDraft
    @State private var minClusterPoints: CalibrationParameterDraft
    @State private var sphericity: CalibrationParameterDraft
    @State private var showsParameterConflict = false
    // A draft keeps its category even if another root consumer changes the next scan selection.
    @State private var activeFruitCategory: FruitCategory

    @MainActor
    init(
        recordsController: CalibrationRecordsController? = nil,
        scanSource: CalibrationScanSource? = nil,
        settings: SettingsStore = .shared,
        parametersStore: FruitParametersStore? = nil
    ) {
        _recordsController = StateObject(wrappedValue: recordsController ?? CalibrationRecordsController())
        self.scanSource = scanSource ?? .production(repository: .shared, historyStore: .shared)
        self.settings = settings
        let resolvedStore = parametersStore ?? .shared
        self.parametersStore = resolvedStore
        let category = FruitCategory(rawValue: settings.fruitType) ?? .apple
        let params = resolvedStore.param(for: category)
        _maxDiameter = State(initialValue: CalibrationParameterDraft(
            settingsValue: settings.clusterMaxDiameter, parameterValue: Double(params.diamMax),
            settingsMinimum: settings.clusterMinDiameter, parameterMinimum: params.diamMin))
        _minClusterPoints = State(initialValue: CalibrationParameterDraft(settingsValue: Double(settings.clusterMinPoints)))
        _sphericity = State(initialValue: CalibrationParameterDraft(
            settingsValue: settings.sphericityThreshold, parameterValue: Double(params.sphericityThreshold)))
        _activeFruitCategory = State(initialValue: category)
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
                            maxDiameter: $maxDiameter.value,
                            minClusterPoints: $minClusterPoints.value,
                            sphericity: $sphericity.value,
                            onCommitMinClusterPoints: commitMinClusterPointsDraft,
                            onCommitMaxDiameter: commitMaxDiameterDraft,
                            onCommitSphericity: commitSphericityDraft,
                            settings: settings
                        )

                        if showsParameterConflict {
                            Text(L10n.Calibration.parameterConflict)
                                .font(Design.Typography.subheadline)
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                        }

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
            AddCalibrationRecordView(scanSource: scanSource) { record in
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
            let params = parametersStore.param(for: activeFruitCategory)
            maxDiameter.rebase(settingsValue: settings.clusterMaxDiameter, parameterValue: Double(params.diamMax),
                               settingsMinimum: settings.clusterMinDiameter, parameterMinimum: params.diamMin)
            minClusterPoints.rebase(settingsValue: Double(settings.clusterMinPoints))
            sphericity.rebase(settingsValue: settings.sphericityThreshold,
                             parameterValue: Double(params.sphericityThreshold))
            showsParameterConflict = false
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
        switch minClusterPoints.decision(settingsValue: Double(settings.clusterMinPoints), step: 1) {
        case .unchanged:
            break
        case .conflict:
            showsParameterConflict = true
        case .commit(let rounded):
            if settings.clusterMinPoints != Int(rounded) {
                settings.clusterMinPoints = Int(rounded)
            }
        }
        minClusterPoints.rebase(settingsValue: Double(settings.clusterMinPoints))
    }

    private func commitMaxDiameterDraft() {
        let category = activeFruitCategory
        let current = parametersStore.param(for: category)
        switch maxDiameter.decision(settingsValue: settings.clusterMaxDiameter,
                                    parameterValue: Double(current.diamMax),
                                    settingsMinimum: settings.clusterMinDiameter,
                                    parameterMinimum: current.diamMin, step: 0.005) {
        case .unchanged:
            break
        case .conflict:
            showsParameterConflict = true
        case .commit(let rounded):
            if abs(Double(current.diamMax) - rounded) > 0.000_1 {
                parametersStore.updateParam(for: category) { params in
                    params.diamMax = Float(rounded)
                    if params.diamMin > params.diamMax {
                        params.diamMin = params.diamMax
                    }
                }
            }
            if abs(settings.clusterMaxDiameter - rounded) > 0.000_1 {
                settings.clusterMaxDiameter = rounded
            }
        }
        maxDiameter.rebase(settingsValue: settings.clusterMaxDiameter,
                           parameterValue: Double(parametersStore.param(for: category).diamMax),
                           settingsMinimum: settings.clusterMinDiameter,
                           parameterMinimum: parametersStore.param(for: category).diamMin)
    }

    private func commitSphericityDraft() {
        let category = activeFruitCategory
        let current = parametersStore.param(for: category)
        switch sphericity.decision(settingsValue: settings.sphericityThreshold,
                                  parameterValue: Double(current.sphericityThreshold), step: 0.02) {
        case .unchanged:
            break
        case .conflict:
            showsParameterConflict = true
        case .commit(let rounded):
            if abs(Double(current.sphericityThreshold) - rounded) > 0.000_1 {
                parametersStore.updateParam(for: category) { params in
                    params.sphericityThreshold = Float(rounded)
                }
            }
            if abs(settings.sphericityThreshold - rounded) > 0.000_1 {
                settings.sphericityThreshold = rounded
            }
        }
        sphericity.rebase(settingsValue: settings.sphericityThreshold,
                          parameterValue: Double(parametersStore.param(for: category).sphericityThreshold))
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

/// A field compares with its own last accepted sources, never with another field's commit.
private struct CalibrationParameterDraft {
    enum Decision {
        case unchanged
        case conflict
        case commit(Double)
    }

    var value: Double
    private let baselineValue: Double
    private let settingsBaseline: Double
    private let parameterBaseline: Double?
    private let settingsMinimumBaseline: Double?
    private let parameterMinimumBaseline: Float?

    init(settingsValue: Double, parameterValue: Double? = nil,
         settingsMinimum: Double? = nil, parameterMinimum: Float? = nil) {
        value = parameterValue ?? settingsValue
        baselineValue = value
        settingsBaseline = settingsValue
        parameterBaseline = parameterValue
        settingsMinimumBaseline = settingsMinimum
        parameterMinimumBaseline = parameterMinimum
    }

    func decision(settingsValue: Double, parameterValue: Double? = nil,
                  settingsMinimum: Double? = nil, parameterMinimum: Float? = nil, step: Double) -> Decision {
        guard abs(value - baselineValue) > 0.000_1 else { return .unchanged }
        guard settingsValue == settingsBaseline, parameterValue == parameterBaseline else { return .conflict }
        let rounded = (value / step).rounded() * step
        // Maximum diameter also changes the effective minima through the existing clamp policy.
        if let minimum = settingsMinimum, minimum != settingsMinimumBaseline, rounded < minimum {
            return .conflict
        }
        if let minimum = parameterMinimum, minimum != parameterMinimumBaseline, Float(rounded) < minimum {
            return .conflict
        }
        return .commit(rounded)
    }

    mutating func rebase(settingsValue: Double, parameterValue: Double? = nil,
                         settingsMinimum: Double? = nil, parameterMinimum: Float? = nil) {
        self = Self(settingsValue: settingsValue, parameterValue: parameterValue,
                    settingsMinimum: settingsMinimum, parameterMinimum: parameterMinimum)
    }
}
