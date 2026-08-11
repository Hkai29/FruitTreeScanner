import SwiftUI

enum ImportStatus: Equatable {
    case idle
    case selecting
    case processing(String)
    case success(String)
    case error(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }

    var afterImporterDismissal: ImportStatus {
        if case .selecting = self {
            return .idle
        }
        return self
    }

    var accessibilityAnnouncement: String? {
        switch self {
        case .idle, .selecting:
            return nil
        case .processing(let filename):
            return "\(L10n.Import.processingTitle). \(filename)"
        case .success(let filename):
            return "\(L10n.Import.successTitle). \(L10n.Import.successMessage(fileName: filename))"
        case .error(let message):
            return "\(L10n.Import.errorTitle). \(message)"
        }
    }
}

enum ImportFileErrorClassifier {
    static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }
}

struct ImportStatusView: View {
    let status: ImportStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                ImportStatusPanel(
                    icon: "doc.badge.plus",
                    title: L10n.Import.idleTitle,
                    message: L10n.Import.idleMessage
                )

            case .selecting:
                ImportStatusPanel(
                    icon: "folder",
                    title: L10n.Import.selectingTitle,
                    message: L10n.Import.selectingMessage
                )

            case .processing(let filename):
                ImportStatusPanel(
                    icon: "arrow.triangle.2.circlepath",
                    title: L10n.Import.processingTitle,
                    message: filename,
                    showsProgress: true
                )

            case .success(let filename):
                ImportStatusPanel(
                    icon: "checkmark.circle.fill",
                    title: L10n.Import.successTitle,
                    message: L10n.Import.successMessage(fileName: filename),
                    tint: Design.Colors.forest
                )

            case .error(let message):
                ImportStatusPanel(
                    icon: "exclamationmark.triangle.fill",
                    title: L10n.Import.errorTitle,
                    message: message,
                    tint: Design.Colors.error
                )
            }
        }
    }
}
