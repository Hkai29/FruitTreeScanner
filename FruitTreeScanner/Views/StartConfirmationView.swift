// StartConfirmationView.swift
// 新建扫描流程的最终确认步骤

import SwiftUI

struct Step5_Confirmation: View {
    let treeID: String
    let plot: Plot?
    let season: Season
    @Binding var selectedFruitCategory: FruitCategory
    let tags: [GroupTag]
    @ObservedObject var gps: GPSRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 5,
                totalSteps: 5,
                title: L10n.StartSetup.text(.confirmationTitle),
                subtitle: L10n.StartSetup.text(.confirmationSubtitle)
            )

            VStack(spacing: Design.Space.md) {
                ConfirmationRow(
                    icon: "number",
                    label: L10n.StartSetup.text(.identifierFieldLabel),
                    value: treeID
                )

                Divider().background(Design.Colors.Dark.glassBorder)

                fruitCategoryPicker

                Divider().background(Design.Colors.Dark.glassBorder)

                ConfirmationRow(
                    icon: "map.fill",
                    label: L10n.StartSetup.text(.plotTitle),
                    value: plot?.name ?? L10n.StartSetup.text(.confirmationUnassigned),
                    valueColor: plot != nil ? Design.Colors.forest : Color(hex: "8E8E93")
                )

                Divider().background(Design.Colors.Dark.glassBorder)

                ConfirmationRow(
                    icon: season == .mature ? "apple.logo" : "leaf.fill",
                    label: L10n.StartSetup.text(.seasonTitle),
                    value: season == .mature
                        ? L10n.StartSetup.text(.confirmationMatureSeason)
                        : L10n.StartSetup.text(.confirmationOffSeason),
                    valueColor: Design.Colors.harvest
                )

                Divider().background(Design.Colors.Dark.glassBorder)

                tagSummary

                Divider().background(Design.Colors.Dark.glassBorder)

                gpsSummary
            }
            .padding(Design.Space.lg)
            .startSurface(cornerRadius: 10)

            StartNoteRow(
                icon: "camera.metering.center.weighted",
                text: L10n.StartSetup.text(.confirmationNote),
                tint: Design.Colors.harvest
            )
        }
    }

    private var fruitCategoryPicker: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.FruitCategoryVerification.selectionTitle)
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Text(L10n.FruitCategoryVerification.fixedForScan)
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            Spacer()
            Picker(L10n.FruitCategoryVerification.selectionTitle, selection: $selectedFruitCategory) {
                ForEach(FruitCategory.scanSupportedCategories, id: \.self) { category in
                    Text(L10n.Fruit.name(for: category)).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Colors.harvest)
            .accessibilityLabel(L10n.FruitCategoryVerification.selectedAccessibilityLabel)
            .accessibilityValue(L10n.FruitCategoryVerification.selectionAccessibilityValue(selectedFruitCategory))
            .accessibilityHint(L10n.FruitCategoryVerification.selectedAccessibilityHint)
        }
    }

    private var tagSummary: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "tag.fill")
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)

            Text(L10n.StartSetup.text(.tagsTitle))
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            if tags.isEmpty {
                Text(L10n.StartSetup.text(.confirmationNone))
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            } else {
                HStack(spacing: Design.Space.xs) {
                    ForEach(tags.prefix(3)) { tag in
                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.system(size: 12))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.system(size: 12))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
        }
    }

    private var gpsSummary: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                .font(.system(size: 16))
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.slate)
                .frame(width: 24)

            Text("GPS")
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(
                gps.isAvailable
                    ? L10n.StartSetup.text(.confirmationGPSAvailable)
                    : L10n.StartSetup.text(.confirmationGPSPending)
            )
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.Dark.textSecondary)
        }
    }
}

struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Design.Colors.Dark.textPrimary

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}
