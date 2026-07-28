import SwiftUI

struct ScanHistoryRecordPresentation: Equatable, Sendable {
    enum Integrity: Equatable, Sendable {
        case complete
        case incomplete
        case invalid
    }

    enum Detail: Equatable, Sendable {
        case none
        case missingResult
        case unreadableJSON
        case unreadableCSV
        case revisionMismatch
        case incompleteUnknown
        case invalidUnknown
    }

    let integrity: Integrity
    let detail: Detail
    let fruitCount: Int?
    let yieldKg: Float?

    var hasReliableResult: Bool {
        integrity == .complete
    }

    var showsRecoveryAction: Bool {
        !hasReliableResult
    }

    init(record: ScanFileRecord) {
        switch record.persistenceState {
        case .complete:
            integrity = .complete
            detail = .none
            fruitCount = record.fruitCount
            yieldKg = record.yieldKg
        case .incomplete:
            integrity = .incomplete
            detail = record.persistenceFailureReason == "orphanPLYDetected"
                ? .missingResult
                : .incompleteUnknown
            fruitCount = nil
            yieldKg = nil
        case .invalid:
            integrity = .invalid
            switch record.persistenceFailureReason {
            case "scanResultJSONFailed":
                detail = .unreadableJSON
            case "scanResultCSVFailed":
                detail = .unreadableCSV
            case "scanResultRevisionMismatch":
                detail = .revisionMismatch
            default:
                detail = .invalidUnknown
            }
            fruitCount = nil
            yieldKg = nil
        }
    }
}

struct ScanHistoryStatusVisualPolicy: Equatable, Sendable {
    enum ForegroundRole: Equatable, Sendable {
        case semanticAccent
        case primaryText
    }

    let symbolForeground: ForegroundRole
    let titleForeground: ForegroundRole
    let recoverySymbolForeground: ForegroundRole
    let recoveryTextForeground: ForegroundRole

    init() {
        symbolForeground = .semanticAccent
        titleForeground = .primaryText
        recoverySymbolForeground = .semanticAccent
        recoveryTextForeground = .primaryText
    }
}

struct ScanHistoryRow: View {
    let record: ScanFileRecord
    let onPreview: () -> Void
    let onShare: () -> Void
    let onRescan: () -> Void
    let onMarkReview: () -> Void
    let onDelete: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: ScanHistoryRecordPresentation {
        ScanHistoryRecordPresentation(record: record)
    }

    private let statusVisualPolicy = ScanHistoryStatusVisualPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            recordHeader

            outcomeRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    @ViewBuilder
    private var recordHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    recordIcon
                    fileInfo
                        .layoutPriority(1)
                }

                HStack(spacing: 4) {
                    Spacer()
                    rowControls
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                recordIcon

                fileInfo
                    .layoutPriority(1)

                Spacer(minLength: 4)

                rowControls
            }
        }
    }

    private var recordIcon: some View {
        Image(systemName: "cube.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Design.Colors.harvest)
            .frame(width: 32, height: 32)
            .background(Design.Colors.harvest.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var rowControls: some View {
        HStack(spacing: 4) {
            Button(action: onPreview) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("history.row.preview_point_cloud", value: "Preview Point Cloud"))

            actionsMenu
        }
    }

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.fileURL.lastPathComponent)
                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text(fileSize)
                Text(dateString)
            }
            .font(.caption)
            .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.fileURL.lastPathComponent)
        .accessibilityValue("\(fileSize), \(dateString)")
    }

    @ViewBuilder
    private var outcomeRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                integrityStatus
                outcomeTrailingContent
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                integrityStatus
                    .layoutPriority(1)

                Spacer(minLength: 4)

                outcomeTrailingContent
            }
        }
    }

    @ViewBuilder
    private var outcomeTrailingContent: some View {
        if presentation.hasReliableResult {
            resultSummary
        } else {
            recoveryButton
        }
    }

    private var integrityStatus: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    statusForegroundColor(for: statusVisualPolicy.symbolForeground)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        statusForegroundColor(for: statusVisualPolicy.titleForeground)
                    )

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var resultSummary: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(countText)
                .font(.caption.weight(.semibold))
                .foregroundColor(Design.Colors.harvest)

            Text(yieldText)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(minWidth: 58, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(countText), \(yieldText)")
    }

    private var recoveryButton: some View {
        Button(action: onRescan) {
            Label {
                Text(localized("history.row.rescan_action", value: "Rescan"))
                    .foregroundColor(
                        statusForegroundColor(for: statusVisualPolicy.recoveryTextForeground)
                    )
            } icon: {
                Image(systemName: "viewfinder")
                    .foregroundColor(
                        statusForegroundColor(for: statusVisualPolicy.recoverySymbolForeground)
                    )
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: Design.Touch.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(statusColor.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHint(
            localized(
                "history.row.rescan_accessibility_hint",
                value: "Starts a new scan for this tree. This record's count and yield remain unavailable."
            )
        )
    }

    private var actionsMenu: some View {
        Menu {
            Button(action: onPreview) {
                Label(L10n.History.previewPointCloud, systemImage: "cube.transparent")
            }
            Button(action: onRescan) {
                Label(L10n.History.rescanTree, systemImage: "viewfinder")
            }
            Button(action: onMarkReview) {
                Label(L10n.History.markReview, systemImage: "flag")
            }
            Button(action: onShare) {
                Label(L10n.History.sharePointCloud, systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label(L10n.History.deleteRecord, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
        }
        .accessibilityLabel(L10n.History.moreActions)
    }

    private var statusTitle: String {
        switch presentation.integrity {
        case .complete:
            return localized("history.integrity.complete.title", value: "Result Complete")
        case .incomplete:
            return localized("history.integrity.incomplete.title", value: "Recovery Needed")
        case .invalid:
            return localized("history.integrity.invalid.title", value: "Result Damaged")
        }
    }

    private var statusMessage: String? {
        switch presentation.detail {
        case .none:
            return nil
        case .missingResult:
            return localized(
                "history.integrity.incomplete.missing_result",
                value: "The result file is missing. Count and yield are unavailable."
            )
        case .unreadableJSON:
            return localized(
                "history.integrity.invalid.json",
                value: "The result JSON can't be read. Count and yield are unavailable."
            )
        case .unreadableCSV:
            return localized(
                "history.integrity.invalid.csv",
                value: "The result CSV can't be read. Count and yield are unavailable."
            )
        case .revisionMismatch:
            return localized(
                "history.integrity.invalid.revision",
                value: "The result files don't match. Count and yield are unavailable."
            )
        case .incompleteUnknown:
            return localized(
                "history.integrity.incomplete.unknown",
                value: "The result wasn't fully saved. Count and yield are unavailable."
            )
        case .invalidUnknown:
            return localized(
                "history.integrity.invalid.unknown",
                value: "The result files can't be verified. Count and yield are unavailable."
            )
        }
    }

    private var statusIcon: String {
        switch presentation.integrity {
        case .complete:
            return "checkmark.circle.fill"
        case .incomplete:
            return "exclamationmark.triangle.fill"
        case .invalid:
            return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch presentation.integrity {
        case .complete:
            return Design.Colors.Dark.success
        case .incomplete:
            return Design.Colors.Dark.warning
        case .invalid:
            return Design.Colors.Dark.error
        }
    }

    private func statusForegroundColor(
        for role: ScanHistoryStatusVisualPolicy.ForegroundRole
    ) -> Color {
        switch role {
        case .semanticAccent:
            return statusColor
        case .primaryText:
            return Design.Colors.Dark.textPrimary
        }
    }

    private var countText: String {
        guard let fruitCount = presentation.fruitCount else {
            return localized("history.row.metrics_unavailable", value: "Metrics Unavailable")
        }
        return String.localizedStringWithFormat(
            localized("history.row.count_format", value: "%d fruits"),
            fruitCount
        )
    }

    private var yieldText: String {
        guard let yieldKg = presentation.yieldKg else {
            return localized("history.row.metrics_unavailable", value: "Metrics Unavailable")
        }
        return String.localizedStringWithFormat(
            localized("history.row.yield_format", value: "%.1f kg"),
            Double(yieldKg)
        )
    }

    private var fileSize: String {
        guard record.fileSizeBytes > 0 else {
            return L10n.History.unknownSize
        }
        let mb = Double(record.fileSizeBytes) / 1_048_576
        return L10n.History.fileSizeMegabytes(mb)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMddjmm")
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.scanDate)
    }

    private func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}
