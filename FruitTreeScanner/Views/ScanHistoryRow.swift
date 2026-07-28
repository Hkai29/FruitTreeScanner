import SwiftUI

struct ScanHistoryRow: View {
    let record: ScanFileRecord
    let onPreview: () -> Void
    let onShare: () -> Void
    let onRescan: () -> Void
    let onMarkReview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 32, height: 32)
                .background(Design.Colors.harvest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            fileInfo

            Spacer(minLength: 8)

            resultSummary

            Button(action: onPreview) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.History.previewPointCloud)

            actionsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.fileURL.lastPathComponent)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text(fileSize)
                Text(dateString)
            }
            .font(.system(size: 11))
            .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private var resultSummary: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(record.fruitCount > 0 ? L10n.History.fruitCount(record.fruitCount) : L10n.History.uncounted)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(record.fruitCount > 0 ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)

            Text(record.yieldKg > 0 ? L10n.History.yieldKilograms(record.yieldKg) : "--")
                .font(Design.Typography.monoSmall)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(minWidth: 58, alignment: .trailing)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(L10n.History.moreActions)
    }

    private var fileSize: String {
        guard record.fileSizeBytes > 0 else { return L10n.History.unknownSize }
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
}
