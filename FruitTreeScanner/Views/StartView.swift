// StartView.swift
// 扫描前配置页面 - 统一深色科技风格

import SwiftUI

struct StartView: View {
    @State private var treeID: String = ""
    @State private var selectedFruitType: FruitType = .appleRed
    @State private var nVisualStr: String = ""
    @State private var season: Season = .mature
    @State private var showScan = false
    @StateObject private var gps = GPSRecorder()
    @Environment(\.dismiss) var dismiss

    private var nVisual: Int? { Int(nVisualStr) }
    private var canStart: Bool { !treeID.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color(hex: "0a1628")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部导航
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("返回")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "4ADE80"))
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 32) {
                        // 标题
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "4ADE80").opacity(0.15))
                                    .frame(width: 100, height: 100)

                                Circle()
                                    .strokeBorder(Color(hex: "4ADE80").opacity(0.5), lineWidth: 2)
                                    .frame(width: 90, height: 90)

                                Image(systemName: "viewfinder")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(hex: "4ADE80"))
                            }

                            Text("新建扫描")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("配置扫描参数并开始采集")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 20)

                        // 树木编号
                        StartInputCard(title: "树木编号") {
                            TextField("例：T001", text: $treeID)
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                        }

                        // 季节选择
                        StartInputCard(title: "扫描季节") {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    SeasonButton(
                                        title: "成熟期",
                                        subtitle: "双路线估算",
                                        icon: "apple.logo",
                                        isSelected: season == .mature
                                    ) {
                                        season = .mature
                                    }

                                    SeasonButton(
                                        title: "非成熟期",
                                        subtitle: "仅冠层体积",
                                        icon: "leaf",
                                        isSelected: season == .off
                                    ) {
                                        season = .off
                                    }
                                }

                                if season == .off {
                                    Text("非成熟期只跑冠层体积法（路线A）")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        // 果种选择（成熟期）
                        if season == .mature {
                            StartInputCard(title: "果实种类") {
                                VStack(spacing: 16) {
                                    Menu {
                                        ForEach(FruitType.allCases, id: \.self) { ft in
                                            Button(ft.rawValue) {
                                                selectedFruitType = ft
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedFruitType.rawValue)
                                                .font(.system(size: 17))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .foregroundColor(Color(hex: "4ADE80"))
                                        }
                                        .padding(16)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(Color(hex: "4ADE80"))
                                        Text("果实密度：\(String(format: "%.2f", selectedFruitType.density)) g/cm³")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            // AI 视觉计数
                            StartInputCard(title: "AI 视觉计数（可选）") {
                                VStack(spacing: 12) {
                                    TextField("留空则不校正遮挡", text: $nVisualStr)
                                        .font(.system(size: 17))
                                        .foregroundColor(.white)
                                        .keyboardType(.numberPad)
                                        .padding(16)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)

                                    Text("输入 YOLO 等视觉模型检测到的果实数量\n用于校正 LiDAR 遮挡损失")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        // GPS 状态
                        HStack(spacing: 12) {
                            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                                .foregroundColor(gps.isAvailable ? Color(hex: "4ADE80") : .white.opacity(0.4))

                            Text(gps.isAvailable
                                 ? String(format: "GPS: %.4f, %.4f", gps.latitude, gps.longitude)
                                 : "GPS 获取中...")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(gps.isAvailable ? .white.opacity(0.7) : .white.opacity(0.4))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)

                        // 开始按钮
                        Button {
                            showScan = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18))
                                Text("开始扫描")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "0a1628"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                canStart
                                    ? LinearGradient(
                                        colors: [Color(hex: "4ADE80"), Color(hex: "22C55E")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .cornerRadius(16)
                        }
                        .disabled(!canStart)
                        .padding(.top, 8)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
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

// MARK: - 通用输入卡片
struct StartInputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - 季节选择按钮
struct SeasonButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? Color(hex: "4ADE80") : .white.opacity(0.5))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "4ADE80").opacity(0.15) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color(hex: "4ADE80") : Color.clear, lineWidth: 1.5)
            )
        }
    }
}