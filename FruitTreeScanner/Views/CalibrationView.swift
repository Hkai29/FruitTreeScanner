// CalibrationView.swift
// 算法校准界面 - 用于验证和调整产量估算算法
//
// 用户流程：
// 1. 扫描果树，获取算法估算的果实数量和产量
// 2. 人工计数（手工数出可见果实数量）
// 3. 采摘后录入实际重量
// 4. 系统计算误差，帮用户判断算法是否需要调整
//
// 参数采用“草稿—提交”模型：滑杆拖动只改草稿，结束编辑或离开页面才写入
// SettingsStore / FruitParametersStore；每个字段只跟自己的上一次接受值比较。

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
            parameterID: params.id,
            settingsMinimum: settings.clusterMinDiameter, parameterMinimum: params.diamMin))
        _minClusterPoints = State(initialValue: CalibrationParameterDraft(settingsValue: Double(settings.clusterMinPoints)))
        _sphericity = State(initialValue: CalibrationParameterDraft(
            settingsValue: settings.sphericityThreshold, parameterValue: Double(params.sphericityThreshold),
            parameterID: params.id))
        _activeFruitCategory = State(initialValue: category)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Workspace.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        leadNote

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
                            conflictNotice
                        }

                        // 误差统计始终可见：没有足够记录时，区块内部给出诚实的说明，
                        // 而不是整段消失（用户会以为功能不存在）。
                        statisticsCard

                        // 校准记录列表
                        recordsSection

                        calibrationGuide
                    }
                    .frame(maxWidth: 1080, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .preferredColorScheme(.light)
            .navigationTitle(L10n.Calibration.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
                            .foregroundColor(Design.Colors.Workspace.accent)
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
                               parameterID: params.id,
                               settingsMinimum: settings.clusterMinDiameter, parameterMinimum: params.diamMin)
            minClusterPoints.rebase(settingsValue: Double(settings.clusterMinPoints))
            sphericity.rebase(settingsValue: settings.sphericityThreshold,
                             parameterValue: Double(params.sphericityThreshold), parameterID: params.id)
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

    // MARK: - 页首

    /// 页尾指引：说明校准数据从哪来、用来做什么。
    /// 它是页面的必要说明，不是填充。
    private var calibrationGuide: some View {
        Text(NSLocalizedString(
            "calibration.guide.footer",
            value: "校准数据来自实测：扫描后录入实际果实数量，采摘后称重录入实际产量，系统据此估算误差并帮助调整参数。",
            comment: "Calibration page footer guide"
        ))
        .font(.footnote)
        .foregroundColor(Design.Colors.Workspace.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var leadNote: some View {
        Text(L10n.Calibration.headerSubtitle)
            .font(.subheadline)
            .foregroundColor(Design.Colors.Workspace.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Calibration.headerTitle)
            .accessibilityValue(L10n.Calibration.headerSubtitle)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 冲突提示

    private var conflictNotice: some View {
        Text(L10n.Calibration.parameterConflict)
            .font(.footnote)
            .foregroundColor(Design.Colors.Workspace.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Design.Colors.Workspace.attentionSoft,
                in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.attention.opacity(0.3), lineWidth: 1)
            )
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
                                    parameterID: current.id,
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
        let latest = parametersStore.param(for: category)
        maxDiameter.rebase(settingsValue: settings.clusterMaxDiameter,
                           parameterValue: Double(latest.diamMax), parameterID: latest.id,
                           settingsMinimum: settings.clusterMinDiameter,
                           parameterMinimum: latest.diamMin)
    }

    private func commitSphericityDraft() {
        let category = activeFruitCategory
        let current = parametersStore.param(for: category)
        switch sphericity.decision(settingsValue: settings.sphericityThreshold,
                                  parameterValue: Double(current.sphericityThreshold), parameterID: current.id,
                                  step: 0.02) {
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
        let latest = parametersStore.param(for: category)
        sphericity.rebase(settingsValue: settings.sphericityThreshold,
                          parameterValue: Double(latest.sphericityThreshold), parameterID: latest.id)
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
    private let parameterIDBaseline: UUID?
    private let settingsMinimumBaseline: Double?
    private let parameterMinimumBaseline: Float?

    init(settingsValue: Double, parameterValue: Double? = nil, parameterID: UUID? = nil,
         settingsMinimum: Double? = nil, parameterMinimum: Float? = nil) {
        value = parameterValue ?? settingsValue
        baselineValue = value
        settingsBaseline = settingsValue
        parameterBaseline = parameterValue
        parameterIDBaseline = parameterID
        settingsMinimumBaseline = settingsMinimum
        parameterMinimumBaseline = parameterMinimum
    }

    func decision(settingsValue: Double, parameterValue: Double? = nil, parameterID: UUID? = nil,
                  settingsMinimum: Double? = nil, parameterMinimum: Float? = nil, step: Double) -> Decision {
        guard abs(value - baselineValue) > 0.000_1 else { return .unchanged }
        // A same-value reset replaces the source; each pending field must reject its own old identity.
        guard settingsValue == settingsBaseline, parameterValue == parameterBaseline,
              parameterID == parameterIDBaseline else { return .conflict }
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

    mutating func rebase(settingsValue: Double, parameterValue: Double? = nil, parameterID: UUID? = nil,
                         settingsMinimum: Double? = nil, parameterMinimum: Float? = nil) {
        self = Self(settingsValue: settingsValue, parameterValue: parameterValue, parameterID: parameterID,
                    settingsMinimum: settingsMinimum, parameterMinimum: parameterMinimum)
    }
}
