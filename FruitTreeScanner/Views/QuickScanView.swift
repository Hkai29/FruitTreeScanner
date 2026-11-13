// QuickScanView.swift
// 快速扫描入口：不归档地块与标签，只确认现场状态后直接进入采集。
//
// 与新建扫描流程共用同一套令牌与组件，只保留单屏所需的最少信息。

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
    private let settings: SettingsStore

    @Environment(\.dismiss) var dismiss
    @StateObject private var gps = GPSRecorder()
    @StateObject private var launchGate = ScanLaunchSubmissionGate()
    @StateObject private var treeIdentifierDraft = QuickScanTreeIdentifierDraft(
        value: QuickScanView.makeDefaultTreeID()
    )
    @State private var selectedFruitCategory: FruitCategory

    private let contentWidth: CGFloat = 1080

    /// 快速采集"不做什么"的说明：不预分配地块与标签，但扫描本身照常保存。
    private static let scopeNote = NSLocalizedString(
        "quick_scan.scope_note",
        value: "不预分配地块与标签：这次扫描仍会照常保存为一条扫描记录，地块与标签可以稍后补上。",
        comment: "Quick scan explains what is not pre-assigned"
    )

    @MainActor
    init(settings: SettingsStore = .shared, onLaunchScan: @escaping (ScanLaunchRequest) -> Void) {
        self.settings = settings
        self.onLaunchScan = onLaunchScan
        _selectedFruitCategory = State(initialValue: FruitCategory.scanCategory(for: settings.fruitType))
    }

    private var canLaunch: Bool {
        !launchGate.isSubmitting && treeIdentifierDraft.validatedValue != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StartStepHeader(
                        step: 1,
                        totalSteps: 1,
                        title: L10n.QuickScan.headerTitle,
                        subtitle: L10n.QuickScan.headerSubtitle,
                        systemImage: "bolt.fill"
                    )

                    treeIDSection

                    fruitCategorySection

                    scopeNotice

                    gpsStatusRow
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                StartFlowNavigationHeader(title: L10n.QuickScan.navigationTitle, cancelTitle: L10n.QuickScan.close,
                                          cancelIdentifier: "quick.close", onCancel: dismiss.callAsFunction)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                launchBand
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .workspacePage()
    }

    // MARK: - 编号

    private var treeIDSection: some View {
        InstrumentPanel(
            label: L10n.QuickScan.treeID,
            trailing: AnyView(
                Text(identifierStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(identifierStatusColor)
                    .fixedSize(horizontal: false, vertical: true)
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                InstrumentTextField(
                    placeholder: L10n.QuickScan.treeIDPlaceholder,
                    text: $treeIdentifierDraft.value,
                    keyboard: .asciiCapable,
                    isMonospaced: true
                )
                .accessibilityLabel(L10n.QuickScan.treeID)

                if let error = validationErrorMessage {
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Design.Colors.Workspace.failure)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 水果类别

    private var fruitCategorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionLabel(title: L10n.FruitCategoryVerification.selectionTitle)

            HStack(spacing: 10) {
                Text(L10n.FruitCategoryVerification.fixedForScan)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                fruitCategoryMenu
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

    // MARK: - 说明与定位

    private var scopeNotice: some View {
        InstrumentNotice(message: Self.scopeNote, tone: .neutral, systemImage: "info.circle")
    }

    private var gpsStatusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: gps.isAvailable ? "location.fill" : "location.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(gps.isAvailable
                                 ? Design.Colors.Workspace.accent
                                 : Design.Colors.Workspace.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(gps.isAvailable ? L10n.QuickScan.gpsAvailable : L10n.QuickScan.gpsUnavailable)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Workspace.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 启动

    private var launchBand: some View {
        Button(action: launchQuickScan) {
            HStack(spacing: 6) {
                if launchGate.isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(launchGate.isSubmitting ? L10n.QuickScan.launching : L10n.QuickScan.launch)
                    .font(.headline)
            }
            .foregroundColor(canLaunch ? .white : Design.Colors.Workspace.secondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(canLaunch ? Design.Colors.Workspace.accent : Design.Colors.Workspace.inset)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
        }
        .disabled(!canLaunch)
        .accessibilityLabel(launchGate.isSubmitting ? L10n.QuickScan.launching : L10n.QuickScan.launch)
    }

    // MARK: - 状态

    private var identifierStatusText: String {
        treeIdentifierDraft.isValid
            ? L10n.QuickScan.treeIDValid
            : (validationErrorMessage != nil ? L10n.QuickScan.treeIDInvalid : L10n.QuickScan.treeIDRequired)
    }

    private var identifierStatusColor: Color {
        treeIdentifierDraft.isValid
            ? Design.Colors.Workspace.accent
            : (validationErrorMessage == nil ? Design.Colors.Workspace.secondary : Design.Colors.Workspace.failure)
    }

    private var validationErrorMessage: String? {
        guard !treeIdentifierDraft.normalizedValue.isEmpty,
              let issue = treeIdentifierDraft.validationIssue else {
            return nil
        }
        return L10n.QuickScan.validationError(for: issue)
    }

    // MARK: - 提交

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
                settings.fruitType = request.selectedFruitCategory.rawValue
                onLaunchScan(request)
            }
        )
    }

    private static func makeDefaultTreeID() -> String {
        "Q\(Int.random(in: 1000...9999))"
    }
}
