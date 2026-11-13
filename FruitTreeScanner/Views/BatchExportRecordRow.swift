// BatchExportRecordRow.swift
// 可导出记录行：选择状态 + 树号 + 真实读数 + 不可用原因。
//
// 只有落盘状态为 .complete 的记录可以导出；其余记录在行内给出真实原因。

import SwiftUI

struct BatchExportRecordRow: View {
    let record: ScanFileRecord
    let isExportable: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onToggle) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout
                } else {
                    compactLayout
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Design.Touch.minimumHeight, alignment: .leading)
            .background(
                isSelected
                    ? Design.Colors.Workspace.accentSoft.opacity(0.45)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.BatchExport.recordAccessibilityLabel(
                treeID: record.treeID,
                fruitCount: record.fruitCount,
                yieldKg: record.yieldKg
            )
        )
        .accessibilityValue(accessibilityState)
        .accessibilityHint(isExportable ? L10n.BatchExport.toggleSelectionHint() : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("batchExport.record.\(record.id)")
    }

    // MARK: - 布局

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            selectionIndicator
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                measurementDetails
                if !isExportable { unavailableNotice }
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                selectionIndicator
                recordTitle
            }
            measurementDetails
            if !isExportable { unavailableNotice }
            scanMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 内容

    private var selectionIndicator: some View {
        Image(systemName: selectionIcon)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(selectionColor)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            recordTitle
            if !record.fruitType.isEmpty {
                Text(L10n.BatchExport.fruitTypeLabel(record.fruitType))
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            scanMetadata
        }
    }

    private var recordTitle: some View {
        Text(record.treeID)
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .foregroundColor(Design.Colors.Workspace.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unavailableNotice: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(unavailableTint)
                .accessibilityHidden(true)
            Text(unavailableMessage)
                .font(.caption)
                .foregroundColor(unavailableTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var measurementDetails: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                measurements.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) { measurements }
        }
        .font(.footnote)
        .foregroundColor(Design.Colors.Workspace.secondary)
    }

    private var measurements: some View {
        Group {
            Label(
                L10n.BatchExport.fruitCountLabel(record.fruitCount),
                systemImage: "leaf.fill"
            )
            .fixedSize(horizontal: false, vertical: true)
            Label(
                L10n.BatchExport.yieldLabel(record.yieldKg),
                systemImage: "scalemass"
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(record.scanDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.muted)
                .lineLimit(1)
            if record.gpsLat != 0 {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - 状态

    private var unavailableMessage: String {
        L10n.BatchExport.unavailableMessage(for: record.persistenceState)
    }

    /// 不可用记录按既有约定着色：未完整保存用琥珀，数据无效用锈红。
    private var unavailableTint: Color {
        switch record.persistenceState {
        case .complete: return Design.Colors.Workspace.secondary
        case .incomplete: return Design.Colors.Workspace.attention
        case .invalid: return Design.Colors.Workspace.failure
        }
    }

    private var accessibilityState: String {
        L10n.BatchExport.recordAccessibilityValue(
            isExportable: isExportable,
            isSelected: isSelected,
            persistenceState: record.persistenceState
        )
    }

    private var selectionIcon: String {
        if !isExportable { return "exclamationmark.circle.fill" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var selectionColor: Color {
        if !isExportable { return unavailableTint }
        return isSelected ? Design.Colors.Workspace.accent : Design.Colors.Workspace.faint
    }
}
