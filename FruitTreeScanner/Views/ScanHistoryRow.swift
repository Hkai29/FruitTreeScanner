import SwiftUI

struct ScanHistoryRecordPresentation: Equatable {
    enum Issue: Equatable {
        case missingResult
        case unreadableJSON
        case unreadableCSV
        case revisionMismatch
        case unknown
    }

    enum State: Equatable {
        case complete
        case incomplete(Issue)
        case invalid(Issue)
    }

    let state: State

    init(record: ScanFileRecord) {
        let issue: Issue
        switch record.persistenceFailureReason {
        case "orphanPLYDetected":
            issue = .missingResult
        case "scanResultJSONFailed":
            issue = .unreadableJSON
        case "scanResultCSVFailed":
            issue = .unreadableCSV
        case "scanResultRevisionMismatch":
            issue = .revisionMismatch
        default:
            issue = .unknown
        }

        switch record.persistenceState {
        case .complete:
            state = .complete
        case .incomplete:
            state = .incomplete(issue)
        case .invalid:
            state = .invalid(issue)
        }
    }

    var showsReliableResult: Bool {
        state == .complete
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

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        statusIcon
                        fileInfo
                        Spacer(minLength: 4)
                        actionsMenu
                    }

                    HStack(alignment: .center, spacing: 10) {
                        resultSummary
                        Spacer(minLength: 4)
                        previewButton
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statusIcon
                        fileInfo
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        previewButton
                        actionsMenu
                    }
                    resultSummary
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
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

    private var resultSummary: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    statusTitleText
                    statusDetailText
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    statusTitleText
                    Spacer(minLength: 8)
                    statusDetailText
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusTitle)
        .accessibilityValue(statusDetail)
    }

    private var statusTitleText: some View {
        Text(statusTitle)
            .font(.caption.weight(.semibold))
            .foregroundColor(statusTint)
            .lineLimit(1)
    }

    private var statusDetailText: some View {
        Text(statusDetail)
            .font(.caption.monospacedDigit())
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    private var statusIcon: some View {
        Image(systemName: statusSystemImage)
            .font(.body.weight(.semibold))
            .foregroundColor(statusTint)
            .frame(width: 36, height: 36)
            .background(statusTint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Image(systemName: "cube.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ScanHistoryText.preview)
        .accessibilityHint(ScanHistoryText.previewHint)
    }

    private var actionsMenu: some View {
        Menu {
            Button(action: onPreview) {
                Label(ScanHistoryText.preview, systemImage: "cube.transparent")
            }
            Button(action: onRescan) {
                Label(ScanHistoryText.rescan, systemImage: "viewfinder")
            }
            Button(action: onMarkReview) {
                Label(ScanHistoryText.markReview, systemImage: "flag")
            }
            Button(action: onShare) {
                Label(ScanHistoryText.share, systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label(ScanHistoryText.deleteRecord, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
        }
        .accessibilityLabel(ScanHistoryText.moreActions)
    }

    private var fileSize: String {
        guard record.fileSizeBytes > 0 else { return ScanHistoryText.unknownSize }
        let mb = Double(record.fileSizeBytes) / 1_048_576
        return ScanHistoryText.fileSize(megabytes: mb)
    }

    private var presentation: ScanHistoryRecordPresentation {
        ScanHistoryRecordPresentation(record: record)
    }

    private var statusTitle: String {
        switch presentation.state {
        case .complete:
            return ScanHistoryText.complete
        case .incomplete:
            return ScanHistoryText.incomplete
        case .invalid:
            return ScanHistoryText.invalid
        }
    }

    private var statusDetail: String {
        switch presentation.state {
        case .complete:
            return "\(ScanHistoryText.fruitCount(record.fruitCount)) · \(ScanHistoryText.yield(record.yieldKg))"
        case .incomplete(let issue):
            return issueText(issue, isInvalid: false)
        case .invalid(let issue):
            return issueText(issue, isInvalid: true)
        }
    }

    private var statusSystemImage: String {
        switch presentation.state {
        case .complete:
            return "checkmark.circle.fill"
        case .incomplete:
            return "exclamationmark.circle.fill"
        case .invalid:
            return "xmark.octagon.fill"
        }
    }

    private var statusTint: Color {
        switch presentation.state {
        case .complete:
            return Design.Colors.Dark.success
        case .incomplete:
            return Design.Colors.Dark.warning
        case .invalid:
            return Design.Colors.Dark.error
        }
    }

    private func issueText(
        _ issue: ScanHistoryRecordPresentation.Issue,
        isInvalid: Bool
    ) -> String {
        switch issue {
        case .missingResult:
            return ScanHistoryText.missingResult
        case .unreadableJSON:
            return ScanHistoryText.unreadableJSON
        case .unreadableCSV:
            return ScanHistoryText.unreadableCSV
        case .revisionMismatch:
            return ScanHistoryText.revisionMismatch
        case .unknown:
            return isInvalid ? ScanHistoryText.invalidUnknown : ScanHistoryText.incompleteUnknown
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.scanDate)
    }
}
