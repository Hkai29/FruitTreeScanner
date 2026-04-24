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

// MARK: - 校准参数

struct CalibrationParams {
    var minClusterPoints: Int = 70      // 最小聚类点数
    var maxClusterVolume: Float = 0.001  // 最大聚类体积 (m³)
    var minSphericity: Float = 0.46      // 最小球形度

    // HSV 阈值调整
    var hsvHMin: Float = 330            // 色调最小值
    var hsvHMax: Float = 25             // 色调最大值
    var hsvSMin: Float = 0.3            // 饱和度最小值
    var hsvVMin: Float = 0.3            // 明度最小值
}

// MARK: - 校准视图

struct CalibrationView: View {
    @State private var calibrationRecords: [CalibrationRecord] = []
    @State private var showAddRecord = false
    @State private var maxDiameter: Double = SettingsStore.shared.clusterMaxDiameter
    @State private var minClusterPoints: Double = Double(SettingsStore.shared.clusterMinPoints)
    @State private var sphericity: Double = SettingsStore.shared.sphericityThreshold

    var body: some View {
        ZStack {
            Design.Colors.bgBase
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
        .navigationTitle("算法校准")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddRecord = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddCalibrationRecordView { record in
                calibrationRecords.insert(record, at: 0)
                saveRecords()
            }
        }
        .onAppear {
            loadRecords()
            maxDiameter = SettingsStore.shared.clusterMaxDiameter
            minClusterPoints = Double(SettingsStore.shared.clusterMinPoints)
            sphericity = SettingsStore.shared.sphericityThreshold
        }
    }

    // MARK: - 参数调整卡片

    private var paramsCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.forest)

                Text("算法参数")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.charcoal)

                Spacer()
            }

            Divider()

            // 最小聚类点数 → clusterMinPoints
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最小聚类点数")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Text("\(Int(minClusterPoints))")
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.forest)
                }
                Slider(value: $minClusterPoints, in: 3...150, step: 1)
                    .tint(Design.Colors.forest)
                    .onChange(of: minClusterPoints) { newValue in
                        SettingsStore.shared.clusterMinPoints = Int(newValue)
                    }
            }

            // 最大聚类直径 → clusterMaxDiameter
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最大聚类直径 (m)")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Text(String(format: "%.3f m", maxDiameter))
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.forest)
                }
                Slider(value: $maxDiameter, in: 0.04...0.20, step: 0.005)
                    .tint(Design.Colors.forest)
                    .onChange(of: maxDiameter) { newValue in
                        SettingsStore.shared.clusterMaxDiameter = newValue
                    }
            }

            // 最小球形度 → sphericityThreshold
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text("最小球形度")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.charcoal)
                    Spacer()
                    Text(String(format: "%.2f", sphericity))
                        .font(Design.Typography.mono)
                        .foregroundColor(Design.Colors.forest)
                }
                Slider(value: $sphericity, in: 0.2...0.8, step: 0.02)
                    .tint(Design.Colors.forest)
                    .onChange(of: sphericity) { newValue in
                        SettingsStore.shared.sphericityThreshold = newValue
                    }
            }

            // HSV 色调范围（只读显示）
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("HSV 色调范围")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.charcoal)

                HStack {
                    Text("H: \(Int(SettingsStore.shared.hsvHMin))° - \(Int(SettingsStore.shared.hsvHMax))°")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.slate)
                    Spacer()
                    Text("S≥\(String(format: "%.0f%%", SettingsStore.shared.hsvSMin * 100)) V≥\(String(format: "%.0f%%", SettingsStore.shared.hsvVMin * 100))")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - 误差统计卡片

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.forest)

                Text("误差统计")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.charcoal)

                Spacer()
            }

            Divider()

            let validRecords = calibrationRecords.filter { $0.countError != nil || $0.yieldError != nil }
            if validRecords.isEmpty {
                Text("暂无校准数据")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.slate)
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
                        color: Design.Colors.forest
                    )
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - 校准记录列表

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Design.Colors.forest)

                Text("校准记录")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.charcoal)

                Spacer()
            }

            Divider()

            if calibrationRecords.isEmpty {
                VStack(spacing: Design.Space.md) {
                    Image(systemName: "leaf")
                        .font(.system(size: 40))
                        .foregroundColor(Design.Colors.slate.opacity(0.5))

                    Text("暂无校准记录")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.slate)

                    Text("点击右上角 + 添加校准记录")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.slate.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Space.xl)
            } else {
                ForEach(calibrationRecords) { record in
                    CalibrationRecordRow(record: record)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - Helpers

    private func errorColor(_ error: Double) -> Color {
        let absError = abs(error)
        if absError <= 10 { return Design.Colors.success }
        if absError <= 20 { return Design.Colors.warning }
        return Design.Colors.error
    }

    private func loadRecords() {
        let url = getDocumentsDirectory().appendingPathComponent("calibration_records.json")
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([CalibrationRecord].self, from: data) else {
            return
        }
        calibrationRecords = records
    }

    private func saveRecords() {
        let url = getDocumentsDirectory().appendingPathComponent("calibration_records.json")
        guard let data = try? JSONEncoder().encode(calibrationRecords) else { return }
        try? data.write(to: url)
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
                .foregroundColor(Design.Colors.slate)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 校准记录行

struct CalibrationRecordRow: View {
    let record: CalibrationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack {
                Text("树 #\(record.treeID)")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.charcoal)

                Spacer()

                Text(formatDate(record.scanDate))
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)
            }

            HStack(spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("估算")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.slate)
                    Text("\(record.estimatedFruitCount) 个 / \(String(format: "%.1f", record.estimatedYieldKg)) kg")
                        .font(Design.Typography.monoSmall)
                        .foregroundColor(Design.Colors.charcoal)
                }

                if record.manualFruitCount != nil || record.actualYieldKg != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.slate)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实际")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.slate)
                        if let manual = record.manualFruitCount, let actual = record.actualYieldKg {
                            Text("\(manual) 个 / \(String(format: "%.1f", actual)) kg")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.charcoal)
                        } else if let manual = record.manualFruitCount {
                            Text("\(manual) 个")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.charcoal)
                        } else if let actual = record.actualYieldKg {
                            Text("\(String(format: "%.1f", actual)) kg")
                                .font(Design.Typography.monoSmall)
                                .foregroundColor(Design.Colors.charcoal)
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
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium)
                .fill(Design.Colors.stone.opacity(0.3))
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
            if absError <= 10 { return Design.Colors.success }
            if absError <= 20 { return Design.Colors.warning }
            return Design.Colors.error
        }()

        VStack(spacing: 2) {
            Text(String(format: "%+.1f%%", error))
                .font(Design.Typography.monoSmall)
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Design.Colors.slate)
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

    let onSave: (CalibrationRecord) -> Void

    @State private var treeID = ""
    @State private var estimatedFruitCount = ""
    @State private var estimatedYieldKg = ""
    @State private var manualFruitCount = ""
    @State private var actualYieldKg = ""
    @State private var selectedFruitType = FruitType.appleRed

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.bgBase
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        // 基本信息
                        GroupBox {
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("基本信息")
                                    .font(Design.Typography.subheadlineMedium)
                                    .foregroundColor(Design.Colors.slate)

                                TextField("树木编号 (如 T001)", text: $treeID)
                                    .textFieldStyle(.roundedBorder)

                                Picker("水果类型", selection: $selectedFruitType) {
                                    ForEach(FruitType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
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
                                    .foregroundColor(Design.Colors.slate)

                                HStack {
                                    TextField("果实数量", text: $estimatedFruitCount)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)

                                    Text("个")
                                        .foregroundColor(Design.Colors.slate)
                                }

                                HStack {
                                    TextField("估算产量", text: $estimatedYieldKg)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.decimalPad)

                                    Text("kg")
                                        .foregroundColor(Design.Colors.slate)
                                }
                            }
                        }

                        // 实际数据（可选）
                        GroupBox {
                            VStack(alignment: .leading, spacing: Design.Space.md) {
                                Text("实际数据（可选）")
                                    .font(Design.Typography.subheadlineMedium)
                                    .foregroundColor(Design.Colors.slate)

                                Text("录入实际数据后，系统会自动计算误差")
                                    .font(Design.Typography.caption)
                                    .foregroundColor(Design.Colors.slate)

                                HStack {
                                    TextField("人工计数", text: $manualFruitCount)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)

                                    Text("个")
                                        .foregroundColor(Design.Colors.slate)
                                }

                                HStack {
                                    TextField("实际产量", text: $actualYieldKg)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.decimalPad)

                                    Text("kg")
                                        .foregroundColor(Design.Colors.slate)
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
                    .disabled(treeID.isEmpty || estimatedFruitCount.isEmpty)
                }
            }
        }
    }

    private func saveRecord() {
        let record = CalibrationRecord(
            id: UUID(),
            treeID: treeID,
            scanDate: Date(),
            estimatedFruitCount: Int(estimatedFruitCount) ?? 0,
            manualFruitCount: Int(manualFruitCount),
            estimatedYieldKg: Double(estimatedYieldKg) ?? 0,
            actualYieldKg: Double(actualYieldKg),
            fruitType: selectedFruitType.rawValue
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
