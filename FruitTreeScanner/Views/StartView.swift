// StartView.swift
// 主界面：输入树木编号 + 选择果种 + 季节，进入扫描

import SwiftUI

struct StartView: View {
    @State private var treeID: String = ""
    @State private var selectedFruitType: FruitType = .appleRed
    @State private var nVisualStr: String = ""    // AI 视觉计数（可留空）
    @State private var season: Season = .mature
    @State private var showScan = false
    @StateObject private var gps = GPSRecorder()

    private var nVisual: Int? { Int(nVisualStr) }
    private var canStart: Bool { !treeID.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // ── 标题 ────────────────────────────
                    VStack(spacing: 8) {
                        Image(systemName: "camera.metering.spot")
                            .font(.system(size: 52))
                            .foregroundColor(.green)
                        Text("果树 LiDAR 采集")
                            .font(.largeTitle.bold())
                        Text("iPad Pro · 扫描 + 产量估算")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 30)

                    // ── 树木编号 ─────────────────────────
                    FormSection(title: "树木编号") {
                        TextField("例：T001", text: $treeID)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                    }

                    // ── 季节 ─────────────────────────────
                    FormSection(title: "扫描季节") {
                        Picker("季节", selection: $season) {
                            Text("🍎 成熟期（双路线）").tag(Season.mature)
                            Text("🌿 非成熟期（仅路线A）").tag(Season.off)
                        }
                        .pickerStyle(.segmented)

                        if season == .off {
                            Text("非成熟期只跑冠层体积法（路线A），\n路线A需先采集称重数据训练模型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // ── 果种（成熟期才显示）─────────────
                    if season == .mature {
                        FormSection(title: "果实种类") {
                            Picker("果种", selection: $selectedFruitType) {
                                ForEach(FruitType.allCases, id: \.self) { ft in
                                    Text(ft.rawValue).tag(ft)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("密度：\(String(format: "%.2f", selectedFruitType.density)) g/cm³")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // ── AI 视觉计数（可选）──────────
                        FormSection(title: "AI 视觉计数（可选）") {
                            TextField("留空则不校正遮挡", text: $nVisualStr)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)

                            Text("输入 YOLO 等视觉模型检测到的果实数量，\n用于校正 LiDAR 遮挡损失（路线B核心）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // ── GPS 状态 ─────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                            .foregroundColor(gps.isAvailable ? .green : .gray)
                        Text(gps.isAvailable
                             ? String(format: "GPS: %.4f, %.4f", gps.latitude, gps.longitude)
                             : "GPS 获取中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // ── 开始按钮 ─────────────────────────
                    Button {
                        showScan = true
                    } label: {
                        Label("开始扫描", systemImage: "play.circle.fill")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canStart ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(!canStart)
                    .padding(.horizontal)

                    // ── 历史记录 ─────────────────────────
                    NavigationLink(destination: ScanHistoryView()) {
                        Label("查看历史记录", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView(
                treeID: treeID.trimmingCharacters(in: .whitespaces),
                fruitType: selectedFruitType,
                nVisual: nVisual,
                season: season,
                gps: gps
            )
        }
    }
}

// MARK: - 表单段落组件

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}
