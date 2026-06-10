import SwiftUI

enum AppNavigation: String {
    case scanner
    case history
    case batchExport
    case map

    static let defaultsKey = "com.hkai29.fruitscanner.pendingNavigation"
    static let notificationName = Notification.Name("com.hkai29.fruitscanner.navigation")

    static func clearPersistedRequest() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    init?(url: URL) {
        guard url.scheme == "fruittreescanner" else { return nil }

        let target = url.host ?? url.pathComponents.dropFirst().first
        switch target?.lowercased() {
        case "scanner", "scan", "start-scan":
            self = .scanner
        case "history", "scan-history":
            self = .history
        case "batch-export", "export":
            self = .batchExport
        case "map", "orchard-map":
            self = .map
        default:
            return nil
        }
    }
}

final class NavigationRouter: ObservableObject {
    @Published var pendingDestination: AppNavigation?

    init() {
        consumePendingUserDefaults()
    }

    func handle(_ destination: AppNavigation) {
        pendingDestination = destination
    }

    func clear() {
        pendingDestination = nil
    }

    func consumePendingUserDefaults() {
        guard let raw = UserDefaults.standard.string(forKey: AppNavigation.defaultsKey),
              let destination = AppNavigation(rawValue: raw) else { return }
        AppNavigation.clearPersistedRequest()
        pendingDestination = destination
    }
}
