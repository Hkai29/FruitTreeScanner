// QuickScanView.swift
// 首页快速扫描入口

import SwiftUI
import UIKit

@MainActor
final class QuickScanTreeIdentifierDraft: ObservableObject {
    @Published var value: String

    init(value: String) {
        self.value = value
    }

    var normalizedValue: String {
        TreeIdentifierPolicy.normalized(value)
    }

    var validationIssue: TreeIdentifierPolicy.ValidationIssue? {
        TreeIdentifierPolicy.validationIssue(for: normalizedValue)
    }

    var isValid: Bool {
        validationIssue == nil
    }

    var validatedValue: String? {
        guard isValid else { return nil }
        return normalizedValue
    }
}

struct QuickScanView: View {
    var onLaunchScan: (ScanLaunchRequest) -> Void

    @Environment(\.dismiss) var dismiss
    @StateObject private var gps = GPSRecorder()
    @StateObject private var launchGate = ScanLaunchSubmissionGate()
    @StateObject private var treeIdentifierDraft = QuickScanTreeIdentifierDraft(
        value: QuickScanView.makeDefaultTreeID()
    )
    @State private var selectedFruitCategory = FruitCategory.scanCategory(for: SettingsStore.shared.fruitType)

    private var canLaunch: Bool {
        !launchGate.isSubmitting && treeIdentifierDraft.validatedValue != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 14) {
                            DashboardToolHeader(
                                imageName: "FeatureQuickScan",
                                title: L10n.QuickScan.headerTitle,
                                subtitle: L10n.QuickScan.headerSubtitle,
                                icon: "bolt.fill",
                                accent: Design.Colors.harvest
                            )
                            QuickScanTreeIDInput(draft: treeIdentifierDraft)
                            fruitCategoryPicker
                            gpsStatusRow
                        }
                        .padding(.horizontal, Design.Space.md)
                        .padding(.top, Design.Space.md)
                    }

                    launchButton
                }
            }
            .navigationTitle(L10n.QuickScan.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.QuickScan.close) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }

    private var fruitCategoryPicker: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundColor(Design.Colors.harvest)
            Text(L10n.FruitCategoryVerification.selectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
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
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var gpsStatusRow: some View {
        HStack(spacing: Design.Space.sm) {
            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(gps.isAvailable ? Design.Colors.forest : Design.Colors.Dark.textSecondary)
                .frame(width: 24)

            Text(gps.isAvailable ? L10n.QuickScan.gpsAvailable : L10n.QuickScan.gpsUnavailable)
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var launchButton: some View {
        Button(action: launchQuickScan) {
            HStack(spacing: 12) {
                if launchGate.isSubmitting {
                    ProgressView()
                        .tint(Design.Colors.Dark.textPrimary)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(launchGate.isSubmitting ? L10n.QuickScan.launching : L10n.QuickScan.launch)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(canLaunch ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(canLaunch ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.bottom, Design.Space.lg)
        .disabled(!canLaunch)
    }

    private func launchQuickScan() {
        guard canLaunch else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        launchGate.submit(
            makeRequest: { () -> ScanLaunchRequest? in
                guard let treeID = treeIdentifierDraft.validatedValue else { return nil }
                return ScanLaunchRequest(
                    treeID: treeID,
                    selectedFruitCategory: selectedFruitCategory,
                    season: .mature,
                    gps: gps,
                    plotId: nil,
                    tagIds: []
                )
            },
            deliver: { request in
                SettingsStore.shared.fruitType = selectedFruitCategory.rawValue
                onLaunchScan(request)
            }
        )
    }

    private static func makeDefaultTreeID() -> String {
        "Q\(Int.random(in: 1000...9999))"
    }
}

private struct QuickScanTreeIDInput: View {
    @ObservedObject var draft: QuickScanTreeIdentifierDraft

    private var isValid: Bool {
        draft.isValid
    }

    private var validationErrorMessage: String? {
        guard !draft.normalizedValue.isEmpty,
              let issue = draft.validationIssue else {
            return nil
        }
        return L10n.QuickScan.validationError(for: issue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.QuickScan.treeID)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Spacer()
                Text(
                    isValid
                        ? L10n.QuickScan.treeIDValid
                        : (validationErrorMessage != nil ? L10n.QuickScan.treeIDInvalid : L10n.QuickScan.treeIDRequired)
                )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isValid ? Design.Colors.forest : Design.Colors.harvest)
            }

            TextField(L10n.QuickScan.treeIDPlaceholder, text: $draft.value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textContentType(.none)
                .submitLabel(.done)

            if let error = validationErrorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.harvest)
            }
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}
