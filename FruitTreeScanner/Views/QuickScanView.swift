// QuickScanView.swift
// 首页快速扫描入口

import SwiftUI
import UIKit

struct QuickScanView: View {
    var onLaunchScan: (ScanLaunchRequest) -> Void

    @Environment(\.dismiss) var dismiss
    @StateObject private var gps = GPSRecorder()
    @State private var treeID: String = QuickScanView.makeDefaultTreeID()
    @State private var isTreeIDValid = true
    @State private var isLaunchingScan = false
    @State private var selectedFruitCategory = FruitCategory.scanCategory(for: SettingsStore.shared.fruitType)

    private var canLaunch: Bool {
        !isLaunchingScan && isTreeIDValid
    }

    private var normalizedTreeID: String {
        TreeIdentifierPolicy.normalized(treeID)
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
                            QuickScanTreeIDInput(initialTreeID: treeID) { value, isValid in
                                treeID = value
                                isTreeIDValid = isValid
                            }
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
                if isLaunchingScan {
                    ProgressView()
                        .tint(Design.Colors.Dark.textPrimary)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isLaunchingScan ? L10n.QuickScan.launching : L10n.QuickScan.launch)
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
        isLaunchingScan = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard TreeIdentifierPolicy.isValid(normalizedTreeID) else {
                isLaunchingScan = false
                return
            }
            let request = ScanLaunchRequest(
                treeID: normalizedTreeID,
                selectedFruitCategory: selectedFruitCategory,
                season: .mature,
                gps: gps,
                plotId: nil,
                tagIds: []
            )
            SettingsStore.shared.fruitType = selectedFruitCategory.rawValue
            onLaunchScan(request)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isLaunchingScan = false
        }
    }

    private static func makeDefaultTreeID() -> String {
        "Q\(Int.random(in: 1000...9999))"
    }
}

private struct QuickScanTreeIDInput: View {
    let onChange: (String, Bool) -> Void

    @State private var draftTreeID: String
    @State private var isValid = true
    @State private var validationErrorMessage: String?
    @State private var syncTask: Task<Void, Never>?

    init(initialTreeID: String, onChange: @escaping (String, Bool) -> Void) {
        self.onChange = onChange
        _draftTreeID = State(initialValue: initialTreeID)
        _isValid = State(initialValue: TreeIdentifierPolicy.isValid(initialTreeID))
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

            TextField(L10n.QuickScan.treeIDPlaceholder, text: $draftTreeID)
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
                .onSubmit(syncImmediately)

            if let error = validationErrorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.harvest)
            }
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .onDisappear {
            syncImmediately()
            syncTask?.cancel()
        }
        .onChange(of: draftTreeID) { newValue in
            let normalized = TreeIdentifierPolicy.normalized(newValue)
            if normalized.isEmpty {
                isValid = false
                validationErrorMessage = nil
            } else if let issue = TreeIdentifierPolicy.validationIssue(for: normalized) {
                isValid = false
                validationErrorMessage = L10n.QuickScan.validationError(for: issue)
            } else {
                isValid = true
                validationErrorMessage = nil
            }
            syncTask?.cancel()
            syncTask = Task {
                try? await Task.sleep(nanoseconds: 140_000_000)
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

    private func publish(_ value: String) {
        let normalized = TreeIdentifierPolicy.normalized(value)
        onChange(normalized, TreeIdentifierPolicy.isValid(normalized))
    }
}
