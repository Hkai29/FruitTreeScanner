// StartFlowViews.swift
// 新建扫描流程的步骤组件

import SwiftUI

struct Step1_IDEntry: View {
    @Binding var treeID: String
    @Binding var isValid: Bool
    @State private var draftTreeID = ""
    @State private var localIsValid = false
    @State private var validationErrorMessage: String?
    @State private var syncTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 1,
                totalSteps: 5,
                title: "果树编号",
                subtitle: "用于记录、导出和后续对比，建议与果园现场编号一致。"
            )

            VStack(alignment: .leading, spacing: Design.Space.sm) {
                HStack {
                    Text("编号")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Spacer()
                    Text(localIsValid ? "可用" : (validationErrorMessage != nil ? "无效" : "必填"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(localIsValid ? Design.Colors.forest : Design.Colors.harvest)
                }

                TextField("例：T001", text: $draftTreeID)
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, 14)
                    .background(Design.Colors.Dark.bgElevated)
                    .cornerRadius(8)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .textContentType(.none)
                    .submitLabel(.next)
                    .onSubmit(syncImmediately)

                if let error = validationErrorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Design.Colors.harvest)
                }
            }
            .padding(Design.Space.lg)
            .startSurface(cornerRadius: 10)

            StartNoteRow(
                icon: "link",
                text: "编号会写入扫描记录和导出文件，不会影响点云采集本身。",
                tint: Design.Colors.harvest
            )
        }
        .onAppear {
            if draftTreeID.isEmpty {
                draftTreeID = treeID
            }
            updateLocalValidity(for: draftTreeID)
            syncImmediately()
        }
        .onDisappear {
            syncImmediately()
            syncTask?.cancel()
        }
        .onChange(of: draftTreeID) { newValue in
            updateLocalValidity(for: newValue)
            syncTask?.cancel()
            syncTask = Task {
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    publish(newValue)
                }
            }
        }
    }

    private func syncImmediately() {
        publish(draftTreeID)
    }

    private func updateLocalValidity(for value: String) {
        let normalized = TreeIdentifierPolicy.normalized(value)
        if normalized.isEmpty {
            localIsValid = false
            validationErrorMessage = nil
        } else if let error = TreeIdentifierPolicy.validationError(for: normalized) {
            localIsValid = false
            validationErrorMessage = error
        } else {
            localIsValid = true
            validationErrorMessage = nil
        }
    }

    private func publish(_ value: String) {
        let normalized = TreeIdentifierPolicy.normalized(value)
        treeID = normalized
        isValid = TreeIdentifierPolicy.isValid(normalized)
    }
}

struct Step2_PlotSelection: View {
    let plots: [Plot]
    @Binding var selectedPlotId: UUID?
    let onAddPlot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 2,
                totalSteps: 5,
                title: "地块",
                subtitle: "可选。用于后续按地块筛选和汇总。"
            )

            if plots.isEmpty {
                StartEmptyAction(
                    icon: "map",
                    title: "还没有地块",
                    message: "这次扫描可以跳过，之后也能在标签管理中维护。",
                    buttonTitle: "创建地块",
                    action: onAddPlot
                )
            } else {
                VStack(spacing: 0) {
                    PlotSelectionRow(
                        title: "暂不分配",
                        subtitle: "扫描完成后再归档到地块",
                        color: Design.Colors.Dark.textMuted,
                        isSelected: selectedPlotId == nil
                    ) {
                        selectedPlotId = nil
                    }

                    Divider().background(Design.Colors.Dark.glassBorder)

                    ForEach(plots) { plot in
                        PlotSelectionRow(
                            title: plot.name,
                            subtitle: "分配到该地块",
                            color: Color(hex: plot.colorHex),
                            isSelected: selectedPlotId == plot.id
                        ) {
                            selectedPlotId = plot.id
                        }

                        if plot.id != plots.last?.id {
                            Divider().background(Design.Colors.Dark.glassBorder)
                        }
                    }

                    Divider().background(Design.Colors.Dark.glassBorder)

                    Button(action: onAddPlot) {
                        HStack(spacing: Design.Space.sm) {
                            Image(systemName: "plus")
                            Text("添加地块")
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .startSurface(cornerRadius: 10)
            }
        }
    }
}

struct Step3_SeasonSelection: View {
    @Binding var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 3,
                totalSteps: 5,
                title: "估算阶段",
                subtitle: "当前仅开放已具备可靠输入的成熟期估算。"
            )

            VStack(spacing: 0) {
                SeasonOptionRow(
                    icon: "apple.logo",
                    title: "成熟期",
                    subtitle: "RGB + LiDAR 果实融合估算",
                    isSelected: season == .mature,
                    color: Design.Colors.forest
                ) {
                    season = .mature
                }

                Divider().background(Design.Colors.Dark.glassBorder)

                SeasonOptionRow(
                    icon: "leaf.fill",
                    title: "非成熟期（待标定）",
                    subtitle: "冠层回归尚缺实测系数，暂不可选择",
                    isSelected: season == .off,
                    color: Design.Colors.harvest,
                    isEnabled: false
                ) {
                    // 冠层回归完成实测标定后再开放。
                }
            }
            .startSurface(cornerRadius: 10)

            StartNoteRow(
                icon: "info.circle",
                text: "非成熟期冠层路线需先用真实称重数据完成模型标定，避免输出缺乏依据的产量。"
            )
        }
    }
}

struct SeasonOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        StartSelectionRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: color,
            isSelected: isSelected,
            action: action
        ) {
            if !isEnabled {
                Text("待标定")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
}

struct PlotSelectionRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        StartSelectionRow(
            title: title,
            subtitle: subtitle,
            icon: "map",
            tint: color,
            isSelected: isSelected,
            action: action
        ) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
    }
}
