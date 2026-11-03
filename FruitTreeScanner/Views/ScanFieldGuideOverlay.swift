// ScanFieldGuideOverlay.swift
// 现场采集指引。四条步骤按仪器说明书的方式编号排列，
// 覆盖层在深色画布上保持与 HUD 同一套语言。

import SwiftUI

struct ScanFieldGuideOverlay: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let onClose: () -> Void
    let onStartScan: () -> Void

    private var tips: [(icon: String, title: String, message: String)] {
        [
            ("figure.walk.motion", L10n.ScanGuidance.text(.slowCircleTitle),
             L10n.ScanGuidance.text(.slowCircleMessage)),
            ("scope", L10n.ScanGuidance.text(.outlineFirstTitle),
             L10n.ScanGuidance.text(.outlineFirstMessage)),
            ("square.3.layers.3d", L10n.ScanGuidance.text(.blindSpotsTitle),
             L10n.ScanGuidance.text(.blindSpotsMessage)),
            ("ruler", L10n.ScanGuidance.text(.measureTitle),
             L10n.ScanGuidance.text(.measureMessage))
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 0) {
                if verticalSizeClass != .compact {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.ScanGuidance.text(.guideTitle))
                                .font(.system(.title3, design: .default).weight(.semibold))
                                .foregroundColor(Design.Colors.Dark.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(L10n.ScanGuidance.text(.guideSubtitle))
                                .font(.caption)
                                .foregroundColor(Design.Colors.Dark.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        closeButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Design.Colors.Dark.glassBorder).frame(height: 0.5)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if verticalSizeClass == .compact {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.ScanGuidance.text(.guideTitle))
                                    .font(.system(.title3, design: .default).weight(.semibold))
                                    .foregroundColor(Design.Colors.Dark.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(L10n.ScanGuidance.text(.guideSubtitle))
                                    .font(.caption)
                                    .foregroundColor(Design.Colors.Dark.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 4)
                        }

                        ForEach(Array(tips.enumerated()), id: \.element.title) { index, tip in
                            ScanFieldGuideTipRow(
                                index: index + 1,
                                icon: tip.icon,
                                title: tip.title,
                                message: tip.message
                            )
                        }

                        DividerLine(color: Design.Colors.Dark.glassBorder)

                        Label(L10n.ScanGuidance.text(.wholeTree), systemImage: "viewfinder")
                            .font(.footnote)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }

                HStack(spacing: 16) {
                    if verticalSizeClass == .compact { closeButton }
                    Button(action: onStartScan) {
                        Text(L10n.ScanGuidance.text(.start))
                            .font(.headline)
                            .foregroundColor(Design.Colors.Dark.bgDeep)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .padding(.vertical, 8)
                            .background(Design.Colors.Dark.glow, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .overlay(alignment: .top) {
                    Rectangle().fill(Design.Colors.Dark.glassBorder).frame(height: 0.5)
                }
            }
            .frame(maxWidth: 520, maxHeight: 680)
            .background(Design.Colors.Dark.bgSurface.opacity(0.97), in: RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .padding(20)
        }
        .foregroundColor(Design.Colors.Dark.textPrimary)
        .transition(.opacity)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.ScanGuidance.text(.closeGuideAccessibility))
    }
}

/// 一条采集步骤：序号 + 图标 + 标题 + 说明。
private struct ScanFieldGuideTipRow: View {
    let index: Int
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.glow)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
