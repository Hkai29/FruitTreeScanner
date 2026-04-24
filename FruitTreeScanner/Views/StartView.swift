// StartView.swift
// 扫描前配置页面 - 自然有机风格

import SwiftUI

struct StartView: View {
    @State private var treeID: String = ""
    @State private var nVisualStr: String = ""
    @State private var season: Season = .mature
    @State private var showScan = false
    @StateObject private var gps = GPSRecorder()
    @Environment(\.dismiss) var dismiss

    private var nVisual: Int? { Int(nVisualStr) }
    private var canStart: Bool { !treeID.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.white
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
                        .foregroundColor(Design.Colors.forest)
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
                                    .fill(Design.Colors.forest.opacity(0.15))
                                    .frame(width: 100, height: 100)

                                Circle()
                                    .strokeBorder(Design.Colors.forest.opacity(0.5), lineWidth: 2)
                                    .frame(width: 90, height: 90)

                                Image(systemName: "viewfinder")
                                    .font(.system(size: 40))
                                    .foregroundColor(Design.Colors.forest)
                            }

                            Text("新建扫描")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "1C1C1E"))

                            Text("配置扫描参数并开始采集")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "8E8E93"))
                        }
                        .padding(.top, 20)

                        // 树木编号
                        StartInputCard(title: "树木编号") {
                            TextField("例：T001", text: $treeID)
                                .font(.system(size: 17))
                                .foregroundColor(Color(hex: "1C1C1E"))
                                .padding(16)
                                .background(Color(hex: "F2F2F7"))
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
                                        .foregroundColor(Color(hex: "8E8E93"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        // AI 视觉计数（可选）
                            StartInputCard(title: "AI 视觉计数（可选）") {
                                VStack(spacing: 12) {
                                    TextField("留空则不校正遮挡", text: $nVisualStr)
                                        .font(.system(size: 17))
                                        .foregroundColor(Color(hex: "1C1C1E"))
                                        .keyboardType(.numberPad)
                                        .padding(16)
                                        .background(Color(hex: "F2F2F7"))
                                        .cornerRadius(12)

                                    Text("输入 YOLO 等视觉模型检测到的果实数量\n用于校正 LiDAR 遮挡损失")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "8E8E93"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                        // GPS 状态
                        HStack(spacing: 12) {
                            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.slate)

                            Text(gps.isAvailable
                                 ? String(format: "GPS: %.4f, %.4f", gps.latitude, gps.longitude)
                                 : "GPS 获取中...")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(gps.isAvailable ? Design.Colors.slate : Design.Colors.slate.opacity(0.6))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(hex: "F2F2F7"))
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
                            .foregroundColor(Color(hex: "1C1C1E"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                canStart
                                    ? LinearGradient(
                                        colors: [Design.Colors.forest, Design.Colors.forestLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Design.Colors.slate.opacity(0.5), Design.Colors.slate.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .cornerRadius(16)
                            .shadow(color: canStart ? Design.Colors.forest.opacity(0.3) : .clear, radius: 8, y: 4)
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
                .foregroundColor(Color(hex: "8E8E93"))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Design.Colors.bgSurface.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Design.Colors.forest.opacity(0.3), lineWidth: 1)
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
                    .foregroundColor(isSelected ? Design.Colors.forest : Design.Colors.slate)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1C1E"))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8E8E93"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Design.Colors.forest.opacity(0.15) : Design.Colors.bgSurface.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Design.Colors.forest : Color.clear, lineWidth: 1.5)
            )
        }
    }
}