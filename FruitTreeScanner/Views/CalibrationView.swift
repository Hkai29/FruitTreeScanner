// CalibrationView.swift
// 算法校准界面 - 用于验证和调整产量估算算法
//
// 用户流程：
// 1. 扫描果树，获取算法估算的果实数量和产量
// 2. 人工计数（手工数出可见果实数量）
// 3. 采摘后录入实际重量
// 4. 系统计算误差，帮用户判断算法是否需要调整

import SwiftUI

// MARK: - 校准记录

struct CalibrationRecord: Codable, Identifiable {
    let id: UUID
    let treeID: String
    let scanDate: Date
    let estimatedFruitCount: Int
    let manualFruitCount: Int?
    let estimatedYieldKg: Double
    let actualYieldKg: Double?
    let fruitType: String

    var countError: Double? {
        guard let manual = manualFruitCount, manual > 0 else { return nil }
        return Double(estimatedFruitCount - manual) / Double(manual) * 100
    }

    var yieldError: Double? {
        guard let actual = actualYieldKg, actual > 0 else { return nil }
        return (estimatedYieldKg - actual) / actual * 100
    }
}

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
                Slider(value: $minClusterPoints, in: 3...150, step: 1)
                    .tint(Design.Colors.Dark.glow)
                    .onChange(of: minClusterPoints) { newValue in
                        SettingsStore.shared.clusterMinPoints = Int(newValue)
                    }
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
                Slider(value: $maxDiameter, in: 0.04...0.20, step: 0.005)
                    .tint(Design.Colors.Dark.glow)
                    .onChange(of: maxDiameter) { newValue in
                        let category = activeFruitCategory
                        FruitParametersStore.shared.updateParam(for: category) { params in
                            params.diamMax = Float(newValue)
                            if params.diamMin > params.diamMax {
                                params.diamMin = params.diamMax
                            }
                        }
                        SettingsStore.shared.clusterMaxDiameter = newValue
                    }
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
                Slider(value: $sphericity, in: 0.2...0.8, step: 0.02)
                    .tint(Design.Colors.Dark.glow)
                    .onChange(of: sphericity) { newValue in
                        let category = activeFruitCategory
                        FruitParametersStore.shared.updateParam(for: category) { params in
                            params.sphericityThreshold = Float(newValue)
                        }
                        SettingsStore.shared.sphericityThreshold = newValue
                    }
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
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text("误差统计")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()

            let validRecords = calibrationRecords.filter { $0.countError != nil || $0.yieldError != nil }
            if validRecords.isEmpty {
                Text("暂无校准数据")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Design.Space.md)
            } else {
                HStack(spacing: Design.Space.xl) {
                    // 计数误差
                    let countErrors = validRecords.compactMap { $0.countError }
                    let avgCountError = countErrors.isEmpty ? 0 : countErrors.reduce(0, +) / Double(countErrors.count)

                    StatBox(
                        title: "计数误差",
                        value: String(format: "%.1f%%", avgCountError),
                        color: errorColor(avgCountError)
                    )

                    // 产量误差
                    let yieldErrors = validRecords.compactMap { $0.yieldError }
                    let avgYieldError = yieldErrors.isEmpty ? 0 : yieldErrors.reduce(0, +) / Double(yieldErrors.count)

                    StatBox(
                        title: "产量误差",
                        value: String(format: "%.1f%%", avgYieldError),
                        color: errorColor(avgYieldError)
                    )

                    // 校准次数
                    StatBox(
                        title: "校准次数",
                        value: "\(validRecords.count)",
                        color: Design.Colors.Dark.glow
                    )
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

    // MARK: - 校准记录列表

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.glow)

                Text("校准记录")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()
            }

            Divider()

            if calibrationRecords.isEmpty {
                VStack(spacing: Design.Space.md) {
                    Image(systemName: "leaf")
                        .font(.system(size: 40))
                        .foregroundColor(Design.Colors.Dark.textSecondary.opacity(0.5))

                    Text("暂无校准记录")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    Text("点击右上角 + 添加校准记录")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Space.xl)
            } else {
                ForEach(calibrationRecords) { record in
                    CalibrationRecordRow(
                        record: record,
                        onDelete: { recordPendingDeletion = record }
                    )
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

    // MARK: - Helpers

    private func errorColor(_ error: Double) -> Color {
        let absError = abs(error)
        if absError <= 10 { return Design.Colors.Dark.success }
        if absError <= 20 { return Design.Colors.Dark.warning }
        return Design.Colors.Dark.error
    }

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
                #if DEBUG
                print("[Calibration] Failed to load records: \(error)")
                #endif
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
                #if DEBUG
                print("[Calibration] Failed to save records: \(error)")
                #endif
            }
        }
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

// MARK: - 统计框

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Design.Space.xs) {
            Text(value)
                .font(Design.Typography.title2)
                .foregroundColor(color)

            Text(title)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 校准记录行

struct CalibrationRecordRow: View {
    let record: CalibrationRecord
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack {
                Text("树 #\(record.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Spacer()

                Text(formatDate(record.scanDate))
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            HStack(spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("估算")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text("\(record.estimatedFruitCount) 个 / \(String(format: "%.1f", record.estimatedYieldKg)) kg")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                if record.manualFruitCount != nil || record.actualYieldKg != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实际")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
                            Text("\(manual) 个 / \(String(format: "%.1f", actual)) kg")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.Dark.textPrimary)
                        } else if let manual = record.manualFruitCount {
                            Text("\(manual) 个")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.Dark.textPrimary)
                        } else if let actual = record.actualYieldKg {
                            Text("\(String(format: "%.1f", actual)) kg")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.Dark.textPrimary)
                        }
                    }
                }

                Spacer()

                // 误差显示
                if let countError = record.countError {
                    ErrorBadge(label: "计数", error: countError)
                }
                if let yieldError = record.yieldError {
                    ErrorBadge(label: "产量", error: yieldError)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.error)
                        .frame(width: 32, height: 32)
                        .background(Design.Colors.Dark.error.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除校准记录")
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(Design.Colors.Dark.bgSurface.opacity(0.3))
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 误差徽章

struct ErrorBadge: View {
    let label: String
    let error: Double

    var body: some View {
        let color: Color = {
            let absError = abs(error)
            if absError <= 10 { return Design.Colors.Dark.success }
            if absError <= 20 { return Design.Colors.Dark.warning }
            return Design.Colors.Dark.error
        }()

        VStack(spacing: 2) {
            Text(String(format: "%+.1f%%", error))
                .font(Design.Typography.monoSmall)
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xs)
        .background(color.opacity(0.1))
        .cornerRadius(Design.Radius.small)
    }
}

// MARK: - 添加校准记录视图

struct AddCalibrationRecordView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared

    let onSave: (CalibrationRecord) -> Void

    @State private var treeID = ""
    @State private var estimatedFruitCount = ""
    @State private var estimatedYieldKg = ""
    @State private var manualFruitCount = ""
    @State private var actualYieldKg = ""
    @State private var selectedFruitCategory: FruitCategory = .apple
    @State private var scanDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        if !historyStore.scanFiles.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: Design.Space.md) {
                                    Text("从扫描记录带入")
                                        .font(Design.Typography.subheadlineMedium)
                                        .foregroundColor(Design.Colors.Dark.textSecondary)

                                    Menu {
                                        ForEach(historyStore.scanFiles.prefix(12)) { record in
                                            Button {
                                                applyScanRecord(record)
                                            } label: {
                                                Text("\(record.treeID) · \(record.fruitCount) 个 · \(String(format: "%.1f kg", record.yieldKg))")
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock.arrow.circlepath")
                                            Text("选择最近扫描")
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(Design.Colors.Dark.textPrimary)
                                        .padding(.horizontal, Design.Space.md)
                                        .padding(.vertical, Design.Space.sm)
                                        .background(Design.Colors.Dark.bgElevated)
                                        .cornerRadius(Design.Radius.small)
                                    }

                                    Text("会自动填入树编号、估算果数、估算产量和扫描日期。")
                                        .font(Design.Typography.caption)
                                        .foregroundColor(Design.Colors.Dark.textSecondary)
                                }
                            }
                        }

                        // 基本信息
                        GroupBox {
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("基本信息")
                                    .font(Design.Typography.subheadlineMedium)
                                    .foregroundColor(Design.Colors.Dark.textSecondary)

                                TextField("树木编号 (如 T001)", text: $treeID)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)

                                Picker("水果类型", selection: $selectedFruitCategory) {
                                    ForEach(FruitCategory.allCases, id: \.self) { cat in
                                        Text(cat.displayName).tag(cat)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        // 算法估算结果
                        GroupBox {
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("算法估算结果")
                                    .font(Design.Typography.subheadlineMedium)
                                    .foregroundColor(Design.Colors.Dark.textSecondary)

                                HStack {
                                    TextField("果实数量", text: $estimatedFruitCount)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)

                                    Text("个")
                                        .foregroundColor(Design.Colors.Dark.textSecondary)
                                }

                                HStack {
                                    TextField("估算产量", text: $estimatedYieldKg)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.decimalPad)

                                    Text("kg")
                                        .foregroundColor(Design.Colors.Dark.textSecondary)
                                }
                            }
                        }

                        // 实际数据（可选）
                        GroupBox {
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("实际数据（可选）")
                                    .font(Design.Typography.subheadlineMedium)
                                    .foregroundColor(Design.Colors.Dark.textSecondary)

                                Text("录入实际数据后，系统会自动计算误差")
                                    .font(Design.Typography.caption)
                                    .foregroundColor(Design.Colors.Dark.textSecondary)

                                HStack {
                                    TextField("人工计数", text: $manualFruitCount)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)

                                    Text("个")
                                        .foregroundColor(Design.Colors.Dark.textSecondary)
                                }

                                HStack {
                                    TextField("实际产量", text: $actualYieldKg)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.decimalPad)

                                    Text("kg")
                                        .foregroundColor(Design.Colors.Dark.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("添加校准记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRecord()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            historyStore.loadRecords()
        }
    }

    private var canSave: Bool {
        !treeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(estimatedFruitCount) != nil
    }

    private func applyScanRecord(_ record: ScanFileRecord) {
        treeID = record.treeID
        estimatedFruitCount = "\(record.fruitCount)"
        estimatedYieldKg = String(format: "%.2f", record.yieldKg)
        scanDate = record.scanDate
        if let category = FruitCategory(rawValue: record.fruitType) {
            selectedFruitCategory = category
        } else if let category = FruitCategory.allCases.first(where: { $0.displayName == record.fruitType }) {
            selectedFruitCategory = category
        }
    }

    private func saveRecord() {
        let normalizedTreeID = treeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CalibrationRecord(
            id: UUID(),
            treeID: normalizedTreeID,
            scanDate: scanDate,
            estimatedFruitCount: Int(estimatedFruitCount) ?? 0,
            manualFruitCount: Int(manualFruitCount),
            estimatedYieldKg: Double(estimatedYieldKg) ?? 0,
            actualYieldKg: Double(actualYieldKg),
            fruitType: selectedFruitCategory.displayName
        )
        onSave(record)
        dismiss()
    }
}

#Preview {
    NavigationView {
        CalibrationView()
    }
}
