// StartConfirmationView.swift
// 第 5 步：启动前检查。
//
// 只复述已经选定的真实值：编号、地块、估算阶段、标签与定位状态。

import SwiftUI

struct Step5_Confirmation: View {
    let treeID: String
    let plot: Plot?
    let season: Season
    @Binding var selectedFruitCategory: FruitCategory
    let tags: [GroupTag]
    @ObservedObject var gps: GPSRecorder
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identifierPanel

            reviewGroup

            StartNoteRow(
                icon: "camera.metering.center.weighted",
                text: L10n.StartSetup.text(.confirmationNote),
                tone: .accent
            )
        }
    }

    // MARK: - 编号

    private var identifierPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.StartSetup.text(.identifierFieldLabel))
                .instrumentLabel()
            Text(treeID)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundColor(Design.Colors.Workspace.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .startSurface(cornerRadius: Design.Radius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.StartSetup.text(.identifierFieldLabel))
        .accessibilityValue(treeID)
    }

    // MARK: - 复核

    private var reviewGroup: some View {
        InstrumentRowGroup {
            fruitCategoryRow

            DividerLine(inset: 0)

            ConfirmationRow(
                icon: "map.fill",
                label: L10n.StartSetup.text(.plotTitle),
                value: plot?.name ?? L10n.StartSetup.text(.confirmationUnassigned),
                valueColor: plot != nil ? Design.Colors.Workspace.ink : Design.Colors.Workspace.secondary
            )

            DividerLine(inset: 0)

            ConfirmationRow(
                icon: season == .mature ? "sun.max" : "leaf.fill",
                label: L10n.StartSetup.text(.seasonTitle),
                value: season == .mature
                    ? L10n.StartSetup.text(.confirmationMatureSeason)
                    : L10n.StartSetup.text(.confirmationOffSeason),
                valueColor: Design.Colors.Workspace.ink
            )

            DividerLine(inset: 0)

            tagSummaryRow

            DividerLine(inset: 0)

            gpsRow
        }
    }

    // MARK: - 水果类别

    private var fruitCategoryRow: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: 10) {
                    fruitCategoryLabel
                    Spacer(minLength: 8)
                    fruitCategoryMenu
                }
            case .vertical:
                VStack(alignment: .leading, spacing: 8) {
                    fruitCategoryLabel
                    fruitCategoryMenu
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: Design.Touch.minimumHeight)
    }

    private var fruitCategoryLabel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.FruitCategoryVerification.selectionTitle)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                Text(L10n.FruitCategoryVerification.fixedForScan)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fruitCategoryMenu: some View {
        Picker(L10n.FruitCategoryVerification.selectionTitle, selection: $selectedFruitCategory) {
            ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                Text(L10n.Fruit.name(for: category)).tag(category)
            }
        }
        .pickerStyle(.menu)
        .tint(Design.Colors.Workspace.accent)
        .frame(minWidth: Design.Touch.minimumWidth, minHeight: Design.Touch.minimumHeight)
        .accessibilityLabel(L10n.FruitCategoryVerification.selectedAccessibilityLabel)
        .accessibilityValue(L10n.FruitCategoryVerification.selectionAccessibilityValue(selectedFruitCategory))
        .accessibilityHint(L10n.FruitCategoryVerification.selectedAccessibilityHint)
    }

    // MARK: - 标签

    private var tagSummaryRow: some View {
        ConfirmationRow(
            icon: "tag.fill",
            label: L10n.StartSetup.text(.tagsTitle),
            value: tagSummaryText,
            valueColor: tags.isEmpty ? Design.Colors.Workspace.secondary : Design.Colors.Workspace.ink
        )
    }

    private var tagSummaryText: String {
        guard !tags.isEmpty else { return L10n.StartSetup.text(.confirmationNone) }
        return L10n.StartSetup.tagSummary(
            names: tags.prefix(3).map(\.name),
            remainingCount: max(tags.count - 3, 0)
        )
    }

    // MARK: - 定位

    private var gpsRow: some View {
        ConfirmationRow(
            icon: gps.isAvailable ? "location.fill" : "location.slash",
            label: "GPS",
            value: gps.isAvailable
                ? L10n.StartSetup.text(.confirmationGPSAvailable)
                : L10n.StartSetup.text(.confirmationGPSPending),
            valueColor: gps.isAvailable ? Design.Colors.Workspace.accent : Design.Colors.Workspace.secondary
        )
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}

/// 复核行：标签 + 值。
struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Design.Colors.Workspace.ink
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch layoutPolicy.arrangement {
            case .horizontal:
                HStack(spacing: 10) {
                    rowLabel
                    Spacer(minLength: 8)
                    rowValue
                        .multilineTextAlignment(.trailing)
                }
            case .vertical:
                VStack(alignment: .leading, spacing: 4) {
                    rowLabel
                    rowValue
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: Design.Touch.minimumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var rowLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
    }

    private var rowValue: some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(valueColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}
